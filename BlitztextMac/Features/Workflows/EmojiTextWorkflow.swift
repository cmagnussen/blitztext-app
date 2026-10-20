import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class EmojiTextWorkflow: Workflow {
    let type = WorkflowType.emojiText
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    private(set) var transcript: String?

    private let recorder = AudioRecorder()
    private let settings: EmojiTextSettings
    private let language: String
    private let localModelName: String
    private let rewriteEngine: TextRewriter.Engine
    private let postProcessor: TranscriptPostProcessor
    /// Text around the cursor for the AI step, nil when not allowed or not readable.
    private let fieldContext: @MainActor () -> String?
    private var processingTask: Task<Void, Never>?

    init(
        settings: EmojiTextSettings,
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
    }

    // MARK: - Recording State

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        phase = .running("Aufnahme l\u{00E4}uft ...")
        recorder.startRecording()

        if let error = recorder.errorMessage {
            phase = .error(error)
        }
    }

    func stop() {
        if recorder.isRecording {
            recorder.stopRecording()
            guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
                recorder.discardRecording()
                phase = .error("Keine Aufnahme erkannt.")
                return
            }
            processRecording()
        } else {
            processingTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        if recorder.isRecording {
            recorder.stopRecording()
            recorder.discardRecording()
        }
        phase = .idle
    }

    // MARK: - Two-Phase Processing: Whisper -> Emoji

    private func processRecording() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running("Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration

        processingTask = Task {
            // The recording is not kept once it is transcribed (docs/privacy.md).
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                // Phase 1: local transcription (Parakeet or WhisperKit)
                let rawText = try await LocalTranscriptionService.transcribe(
                    audioURL: url,
                    language: language,
                    modelName: localModelName
                ) { [weak self] in
                    self?.phase = .running(LocalTranscriptionService.slowPreparationMessage)
                }
                let cleanedRawText = TranscriptionQualityService.cleanedTranscript(rawText)
                guard !TranscriptionQualityService.isLikelyArtifact(cleanedRawText, recordingDuration: recordingDuration) else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                let processedRawText = postProcessor.process(cleanedRawText)
                guard !processedRawText.isEmpty else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                if Task.isCancelled { return }
                transcript = processedRawText

                // Phase 2: Add emojis
                phase = .running("Emojis werden eingef\u{00FC}gt ...")

                let result = try await TextRewriter.rewrite(
                    processedRawText,
                    instruction: ModePrompts.withFieldContext(ModePrompts.emoji(settings), context: fieldContext()),
                    engine: rewriteEngine
                )
                let cleanedResult = TranscriptionQualityService.cleanedTranscript(result)
                guard cleanedResult != ModePrompts.nothingRecognizedMarker else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }
                phase = .done(cleanedResult)
                onOutput?(cleanedResult)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
