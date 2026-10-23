import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class DampfAblassenWorkflow: Workflow {
    let type = WorkflowType.dampfAblassen
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    private(set) var transcript: String?

    private let dictation: DictationRun
    private let settings: DampfAblassenSettings
    private let language: String
    private let localModelName: String
    private let rewriteEngine: TextRewriter.Engine
    private let postProcessor: TranscriptPostProcessor
    /// Text around the cursor for the AI step, nil when not allowed or not readable.
    private let fieldContext: @MainActor () -> String?

    init(
        settings: DampfAblassenSettings,
        language: String = "de",
        localModelName: String,
        rewriteEngine: TextRewriter.Engine,
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(correctCustomTerms: false, removeFillerWords: false),
        fieldContext: @escaping @MainActor () -> String? = { nil }
    ) {
        self.settings = settings
        self.language = language
        self.localModelName = localModelName
        self.rewriteEngine = rewriteEngine
        self.postProcessor = postProcessor
        self.fieldContext = fieldContext
        dictation = DictationRun(recorder: AudioRecorder())
        dictation.onPhase = { [weak self] phase in self?.phase = phase }
        dictation.onOutput = { [weak self] text in self?.onOutput?(text) }
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

    // MARK: - Two-Phase Processing: Whisper -> GPT Rage Mode

    private func process(
        _ recording: URL,
        seconds recordingDuration: TimeInterval,
        step: @escaping @MainActor (String) -> Void
    ) async throws -> String? {
        // Phase 1: local transcription (Parakeet or WhisperKit)
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

        // Cancelled meanwhile (Escape): no AI step for a text that is not pasted.
        try Task.checkCancellation()
        transcript = processedRawText

        // Phase 2: AI rewrite (on device or the connected provider)
        step("Wird umformuliert ...")

        let answer = try await TextRewriter.rewrite(
            processedRawText,
            instruction: ModePrompts.withFieldContext(ModePrompts.dampfAblassen(settings), context: fieldContext()),
            engine: rewriteEngine
        )
        let cleanedAnswer = TranscriptionQualityService.cleanedTranscript(answer)
        guard cleanedAnswer != ModePrompts.nothingRecognizedMarker else { return nil }
        return cleanedAnswer
    }
}
