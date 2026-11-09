import Foundation
import Observation

/// An own mode: local transcription, then the language model with the mode's instruction,
/// like Blitztext+. Without an instruction the text stays word for word.
@Observable
@MainActor
final class CustomModeWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    var onKeptTranscript: WorkflowOutputHandler?
    private(set) var transcript: String?

    private let dictation: DictationRun
    private let mode: CustomMode
    /// Names and terms from the dictionary, written exactly as given.
    private let protectedTerms: [String]
    private let language: String
    private let localModelName: String
    private let rewriteEngine: TextRewriter.Engine
    private let postProcessor: TranscriptPostProcessor
    /// Text around the cursor for the AI step, nil when not allowed or not readable.
    private let fieldContext: @MainActor () -> String?

    init(
        mode: CustomMode,
        protectedTerms: [String],
        language: String = "de",
        localModelName: String,
        rewriteEngine: TextRewriter.Engine,
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(correctCustomTerms: false, removeFillerWords: false),
        fieldContext: @escaping @MainActor () -> String? = { nil }
    ) {
        self.type = .custom(mode.id)
        self.mode = mode
        self.protectedTerms = protectedTerms
        self.language = language
        self.localModelName = localModelName
        self.rewriteEngine = rewriteEngine
        self.postProcessor = postProcessor
        self.fieldContext = fieldContext
        dictation = DictationRun(recorder: AudioRecorder())
        dictation.onPhase = { [weak self] phase in self?.phase = phase }
        dictation.onOutput = { [weak self] text in self?.onOutput?(text) }
        dictation.onKeptTranscript = { [weak self] text in self?.onKeptTranscript?(text) }
    }

    static let emptyAnswerReason = "Die KI hat keinen Text geliefert."

    /// The mode's instruction plus the dictionary terms. Unlike the built-in modes there is no
    /// `ModePrompts.transcriptIsNotARequest`: own modes such as "Antworten" are meant to write
    /// new text from what was said (as on iOS).
    static func instruction(for mode: CustomMode, protectedTerms: [String]) -> String {
        mode.prompt + ModePrompts.customTermsInstruction(protectedTerms)
    }

    // MARK: - Recording State

    var isRecording: Bool { dictation.isRecording }
    var audioLevel: Float { dictation.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        dictation.start()
    }

    func stop() {
        dictation.stop(processing: process)
    }

    func reset() {
        dictation.cancel()
    }

    // MARK: - Transcription, then the mode's instruction

    private func process(
        _ recording: URL,
        seconds recordingDuration: TimeInterval,
        step: @escaping @MainActor (String) -> Void
    ) async throws -> String? {
        let rawText = try await LocalTranscriptionService.transcribe(
            audioURL: recording,
            language: language,
            modelName: localModelName
        ) {
            step(LocalTranscriptionService.slowPreparationMessage)
        }
        let cleanedRawText = TranscriptionQualityService.cleanedTranscript(rawText)
        guard !TranscriptionQualityService.isLikelyArtifact(cleanedRawText, recordingDuration: recordingDuration) else {
            return nil
        }

        let processedRawText = postProcessor.process(cleanedRawText)
        guard !processedRawText.isEmpty else { return nil }

        // No instruction yet: the mode works like plain dictation.
        guard mode.hasInstruction else { return processedRawText }

        // Cancelled meanwhile (Escape): no AI step for a text that is not pasted.
        try Task.checkCancellation()
        transcript = processedRawText

        step("\(WorkflowType.customName(mode)) wird formuliert ...")

        // A failure keeps what was said (`AIStepFailed`).
        let written: String
        do {
            written = try await TextRewriter.rewrite(
                processedRawText,
                instruction: ModePrompts.withFieldContext(
                    Self.instruction(for: mode, protectedTerms: protectedTerms),
                    context: fieldContext()
                ),
                engine: rewriteEngine
            )
        } catch {
            throw AIStepFailed.wrapping(error, transcript: processedRawText)
        }
        let cleaned = TranscriptionQualityService.cleanedTranscript(written)
        guard cleaned != ModePrompts.nothingRecognizedMarker else { return nil }
        // An empty answer (the device model can give one without an error) is a failed AI
        // step, not "no speech": what was said is kept.
        guard !cleaned.isEmpty else {
            throw AIStepFailed(transcript: processedRawText, reason: Self.emptyAnswerReason)
        }
        return cleaned
    }
}
