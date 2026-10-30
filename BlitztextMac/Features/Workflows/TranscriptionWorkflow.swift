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

    private let dictation: DictationRun
    private let language: String
    private let localModelName: String
    private let postProcessor: TranscriptPostProcessor

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
        dictation = DictationRun(recorder: AudioRecorder())
        dictation.onPhase = { [weak self] phase in self?.phase = phase }
        dictation.onOutput = { [weak self] text in self?.onOutput?(text) }
    }

    func start() {
        dictation.start()
    }

    func stop() {
        dictation.stop(processing: transcribe)
    }

    func reset() {
        dictation.cancel()
    }

    var isRecording: Bool { dictation.isRecording }
    var audioLevel: Float { dictation.audioLevel }

    private func transcribe(
        _ recording: URL,
        seconds recordingDuration: TimeInterval,
        step: @escaping @MainActor (String) -> Void
    ) async throws -> String? {
        let stopTime = Date()
        do {
            let text = try await LocalTranscriptionService.transcribe(
                audioURL: recording,
                language: language,
                modelName: localModelName
            ) {
                step(LocalTranscriptionService.slowPreparationMessage)
            }

            let responseReceivedAt = Date()
            let cleaned = TranscriptionQualityService.cleanedTranscript(text)
            guard !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: recordingDuration) else {
                tapTalkLogger.info(
                    "TapTalk rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
                )
                return nil
            }

            let processed = postProcessor.process(cleaned)
            guard !processed.isEmpty else { return nil }

            tapTalkLogger.info(
                "TapTalk ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms"
            )
            return processed
        } catch {
            tapTalkLogger.error(
                "TapTalk failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}
