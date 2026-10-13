import Foundation
import AppKit
import Observation
import OSLog

private let tapTalkLogger = Logger(subsystem: "app.blitztext.mac", category: "TapTalk")

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

    private let recorder = AudioRecorder()
    private let language: String
    private let localModelName: String
    private let postProcessor: TranscriptPostProcessor
    private var transcriptionTask: Task<Void, Never>?

    init(
        type: WorkflowType = .tapTalk,
        language: String = "de",
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(correctCustomTerms: false, removeFillerWords: false)
    ) {
        self.type = type
        self.language = language
        self.localModelName = localModelName
        self.postProcessor = postProcessor
    }

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
        phase = .idle
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    private func transcribe() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running("Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let requestLanguage = language
        let stopTime = Date()

        transcriptionTask = Task(priority: .userInitiated) {
            let requestStart = Date()
            do {
                let text = try await LocalTranscriptionService.transcribe(
                    audioURL: url,
                    language: requestLanguage,
                    modelName: localModelName
                ) { [weak self] in
                    self?.phase = .running(LocalTranscriptionService.slowPreparationMessage)
                }
                try Task.checkCancellation()

                let responseReceivedAt = Date()
                let cleaned = TranscriptionQualityService.cleanedTranscript(text)
                guard !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: recordingDuration) else {
                    tapTalkLogger.info(
                        "TapTalk rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
                    )
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                let processed = postProcessor.process(cleaned)
                guard !processed.isEmpty else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                tapTalkLogger.info(
                    "TapTalk ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms (request \(elapsedMilliseconds(since: requestStart, until: responseReceivedAt)) ms)"
                )
                phase = .done(processed)
                onOutput?(processed)
            } catch {
                tapTalkLogger.error(
                    "TapTalk failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .public)"
                )
                phase = .error(error.localizedDescription)
            }
        }
    }
}
