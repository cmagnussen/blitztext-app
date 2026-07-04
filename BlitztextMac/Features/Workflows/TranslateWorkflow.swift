import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TranslateWorkflow: Workflow {
    let type = WorkflowType.translate
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder = AudioRecorder()
    private let customTerms: [String]
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private let llmConfig: LLMConfig
    private let tone: TextImprovementSettings.TextTone
    private var processingTask: Task<Void, Never>?

    init(
        customTerms: [String] = [],
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        llmConfig: LLMConfig = .openAI,
        tone: TextImprovementSettings.TextTone = .neutral
    ) {
        self.customTerms = customTerms
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
        self.llmConfig = llmConfig
        self.tone = tone
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

    // MARK: - Two-Phase Processing: Whisper -> Übersetzung

    private func processRecording() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running("Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []

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

                // Phase 2: Übersetzung
                phase = .running("Wird übersetzt ...")

                let translated = try await LLMService.translate(
                    text: cleanedRawText,
                    tone: tone,
                    config: llmConfig
                )
                let cleanedTranslated = TranscriptionQualityService.cleanedTranscript(translated)
                phase = .done(cleanedTranslated)
                onOutput?(cleanedTranslated)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
