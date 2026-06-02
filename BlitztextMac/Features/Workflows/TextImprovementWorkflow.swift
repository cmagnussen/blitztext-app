import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TextImprovementWorkflow: Workflow {
    let type = WorkflowType.textImprover
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder = AudioRecorder()
    private let settings: TextImprovementSettings
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private let llmConfig: LLMConfig
    private var processingTask: Task<Void, Never>?

    init(
        settings: TextImprovementSettings,
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        llmConfig: LLMConfig = .openAI
    ) {
        self.settings = settings
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
        self.llmConfig = llmConfig
    }

    // MARK: - Recording State

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        phase = .running("Aufnahme läuft ...")
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
        }
        recorder.discardRecording()
        phase = .idle
    }

    // MARK: - Two-Phase Processing: Whisper -> GPT

    private func processRecording() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running("Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? settings.customTerms : []

        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            do {
                // Phase 1: Whisper transcription (remote oder lokal)
                let rawText = try await TranscriptionService.transcribe(
                    audioURL: url,
                    customTerms: vocabularyHints,
                    language: language,
                    backend: backend,
                    localModelName: localModelName
                )
                let cleanedRawText = TranscriptionQualityService.cleanedTranscript(rawText)
                guard !TranscriptionQualityService.isLikelyArtifact(cleanedRawText, recordingDuration: recordingDuration) else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                if Task.isCancelled { return }

                // Phase 2: GPT improvement
                phase = .running("Text wird verbessert ...")

                let improved = try await LLMService.improve(
                    text: cleanedRawText,
                    settings: settings,
                    config: llmConfig
                )

                let cleanedImproved = TranscriptionQualityService.cleanedTranscript(improved)
                phase = .done(cleanedImproved)
                onOutput?(cleanedImproved)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
