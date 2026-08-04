import Foundation
import AppKit
import Observation
import OSLog

private let transcriptionLogger = Logger(subsystem: "app.blitztext.mac", category: "Transcription")

private func elapsedMilliseconds(since start: Date, until end: Date = Date()) -> Int {
    Int((end.timeIntervalSince(start) * 1000).rounded())
}

@Observable
@MainActor
final class TranscriptionWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder: AudioRecorder
    private let customTerms: [String]
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private var transcriptionTask: Task<Void, Never>?

    init(
        type: WorkflowType = .transcription,
        customTerms: [String] = [],
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        inputDeviceUID: String? = nil
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
        self.recorder = AudioRecorder(inputDeviceUID: inputDeviceUID)
    }

    func start() {
        recorder.startRecording()

        if let error = recorder.errorMessage {
            phase = .error(error)
        } else {
            phase = .running("Aufnahme läuft ...")
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
            transcribe()
        } else {
            transcriptionTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        transcriptionTask?.cancel()
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
        phase = .idle
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    private func transcribe() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running(backend == .local ? "Wird lokal transkribiert ..." : "Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []
        let requestLanguage = language
        let stopTime = Date()

        transcriptionTask = Task(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            let requestStart = Date()
            do {
                let text: String
                switch backend {
                case .remote:
                    text = try await TranscriptionService.transcribe(
                        audioURL: url,
                        customTerms: vocabularyHints,
                        language: requestLanguage
                    )
                case .local:
                    text = try await LocalTranscriptionService.shared.transcribe(
                        audioURL: url,
                        language: requestLanguage,
                        modelName: localModelName
                    )
                }
                try Task.checkCancellation()

                let responseReceivedAt = Date()
                let cleaned = backend == .local
                    ? TranscriptionQualityService.cleanedLocalTranscript(text)
                    : TranscriptionQualityService.cleanedTranscript(text)
                guard !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: recordingDuration) else {
                    transcriptionLogger.info(
                        "Transcription rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
                    )
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                transcriptionLogger.info(
                    "Transcription ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms (request \(elapsedMilliseconds(since: requestStart, until: responseReceivedAt)) ms)"
                )
                phase = .done(cleaned)
                onOutput?(cleaned)
            } catch {
                transcriptionLogger.error(
                    "Transcription failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .private)"
                )
                phase = .error(error.localizedDescription)
            }
        }
    }
}
