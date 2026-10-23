import Foundation

/// The microphone as a dictation uses it: `AudioRecorder` in the app, a stand-in in tests.
protocol DictationRecorder: AnyObject {
    var isRecording: Bool { get }
    var errorMessage: String? { get }
    var recordingURL: URL? { get }
    var lastRecordingDuration: TimeInterval { get }
    var audioLevel: Float { get }

    func startRecording()
    func stopRecording()
    func discardRecording()
}

/// Recording, processing and cancelling of one dictation, the same in every mode. The modes
/// only differ in what they do with the recording (transcribe, then maybe rewrite).
@MainActor
final class DictationRun {
    nonisolated static let recordingMessage = "Aufnahme l\u{00E4}uft ..."
    nonisolated static let transcribingMessage = "Wird transkribiert ..."
    nonisolated static let nothingRecognizedMessage = "Keine Aufnahme erkannt."

    /// Turns the recording into the text to insert; nil when nothing usable was said.
    /// `step` shows what runs, e.g. "Text wird verbessert ...".
    typealias Processing = @MainActor (
        _ recording: URL,
        _ seconds: TimeInterval,
        _ step: @escaping @MainActor (String) -> Void
    ) async throws -> String?

    var onPhase: (@MainActor (WorkflowPhase) -> Void)?
    var onOutput: (@MainActor (String) -> Void)?

    private let recorder: any DictationRecorder
    private var processing: Task<Void, Never>?
    /// Counts processing runs; a cancel moves it on, so a cancelled run reports nothing more.
    private var currentRun = 0

    init(recorder: any DictationRecorder) {
        self.recorder = recorder
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    /// The phase changes only once the microphone runs: the pill and the menu bar icon
    /// read `isRecording` right then to show the recording.
    func start() {
        recorder.startRecording()
        if let error = recorder.errorMessage {
            onPhase?(.error(error))
        } else {
            onPhase?(.running(Self.recordingMessage))
        }
    }

    /// Ends the recording and processes it. Called while processing, it cancels instead.
    @discardableResult
    func stop(processing work: @escaping Processing) -> Task<Void, Never>? {
        guard recorder.isRecording else {
            cancel()
            return nil
        }
        recorder.stopRecording()
        guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
            recorder.discardRecording()
            onPhase?(.error(Self.nothingRecognizedMessage))
            return nil
        }
        guard let url = recorder.recordingURL else {
            onPhase?(.error("Keine Aufnahme vorhanden."))
            return nil
        }

        onPhase?(.running(Self.transcribingMessage))
        currentRun += 1
        let run = currentRun
        let seconds = recorder.lastRecordingDuration
        let task = Task(priority: .userInitiated) {
            // The recording is not kept once it is transcribed (docs/privacy.md).
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await work(url, seconds) { message in
                    self.report(.running(message), of: run)
                }
                // Cancelled meanwhile: an engine may still return its text; it is not pasted.
                guard run == currentRun else { return }
                guard let text, !text.isEmpty else {
                    onPhase?(.error(Self.nothingRecognizedMessage))
                    return
                }
                onPhase?(.done(text))
                onOutput?(text)
            } catch {
                // The cancel itself makes the engines throw; that is no error to show.
                report(.error(error.localizedDescription), of: run)
            }
        }
        processing = task
        return task
    }

    /// Ends the dictation without a result: a recording is discarded, processing stops
    /// and reports nothing more.
    func cancel() {
        currentRun += 1
        processing?.cancel()
        if recorder.isRecording {
            recorder.stopRecording()
            recorder.discardRecording()
        }
        onPhase?(.idle)
    }

    private func report(_ phase: WorkflowPhase, of run: Int) {
        guard run == currentRun else { return }
        onPhase?(phase)
    }
}

/// What a shortcut or Escape does while a dictation may already run.
enum DictationControl {
    enum Action: Equatable {
        case start
        /// End the recording and process it.
        case stop
        /// End the dictation without a result.
        case cancel
        case ignore
    }

    /// A shortcut never cancels a dictation that is being transcribed or rewritten; only
    /// Escape does.
    static func shortcutDown(holdToRecord: Bool, phase: WorkflowPhase?, isRecording: Bool) -> Action {
        guard case .running = phase else { return .start }
        // Hold mode: another shortcut while one is held, or pressing again right after
        // letting go. The running dictation finishes and pastes first.
        guard !holdToRecord else { return .ignore }
        // Toggle mode: any shortcut ends the recording; a second stop during the
        // transcription would cancel its result.
        return isRecording ? .stop : .ignore
    }

    static func shortcutUp(holdToRecord: Bool, isRecording: Bool) -> Action {
        holdToRecord && isRecording ? .stop : .ignore
    }

    /// Escape ends a recording (its text is still made) and cancels processing quietly.
    static func escape(phase: WorkflowPhase?, isRecording: Bool) -> Action {
        if isRecording { return .stop }
        guard case .running = phase else { return .ignore }
        return .cancel
    }
}
