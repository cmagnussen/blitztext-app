import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class FormatWorkflow: Workflow {
    let type = WorkflowType.format
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    /// nil = Format-Auswahl wird angezeigt (noch keine Aufnahme). Gesetzt = Aufnahme läuft/lief.
    private(set) var selectedFormat: TextFormatKind?

    private let recorder = AudioRecorder()
    private let customTerms: [String]
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private let llmConfig: LLMConfig
    private var processingTask: Task<Void, Never>?

    init(
        customTerms: [String] = [],
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        llmConfig: LLMConfig = .openAI
    ) {
        self.customTerms = customTerms
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
        self.llmConfig = llmConfig
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    /// Zeigt zuerst die Format-Auswahl an; nimmt noch NICHT auf.
    func start() {
        selectedFormat = nil
        phase = .idle
    }

    /// Vom Chooser aufgerufen: Format merken und Aufnahme starten.
    func selectFormat(_ kind: TextFormatKind) {
        selectedFormat = kind
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
        selectedFormat = nil
        phase = .idle
    }

    private func processRecording() {
        guard let kind = selectedFormat else {
            phase = .error("Kein Format gewählt.")
            return
        }
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

                phase = .running("Wird formatiert ...")

                let formatted = try await LLMService.format(
                    text: cleanedRawText,
                    kind: kind,
                    config: llmConfig
                )
                let cleaned = TranscriptionQualityService.cleanedTranscript(formatted)
                phase = .done(cleaned)
                onOutput?(cleaned)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
