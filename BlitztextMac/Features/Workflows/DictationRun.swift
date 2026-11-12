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

/// An error that may say the recording held no speech (`LocalTranscriptionError.noSpeech`).
protocol NoSpeechVerdict: Error {
    var meansNoSpeech: Bool { get }
}

/// Recording, processing and cancelling of one dictation, the same in every mode. The modes
/// only differ in what they do with the recording (transcribe, then maybe rewrite).
@MainActor
final class DictationRun {
    nonisolated static let recordingMessage = "Aufnahme l\u{00E4}uft ..."
    nonisolated static let transcribingMessage = "Wird transkribiert ..."
    nonisolated static let nothingRecognizedMessage = "Keine Aufnahme erkannt."
    /// Shorter recordings without speech are not kept (`UnfinishedRecordings`).
    nonisolated static let minimumSecondsKeptWithoutSpeech = HallucinationFilter.accidentalRecordingSeconds

    /// Turns the recording into the text to insert; nil when nothing usable was said.
    /// `step` shows what runs, e.g. "Text wird verbessert ...".
    typealias Processing = @MainActor (
        _ recording: URL,
        _ seconds: TimeInterval,
        _ step: @escaping @MainActor (String) -> Void
    ) async throws -> String?

    var onPhase: (@MainActor (WorkflowPhase) -> Void)?
    var onOutput: (@MainActor (String) -> Void)?
    /// The AI step failed on a finished transcript (`AIStepFailed`): the word-for-word
    /// text to keep, on the clipboard and in the history. Comes right before the error phase.
    var onKeptTranscript: (@MainActor (String) -> Void)?

    private let recorder: any DictationRecorder
    private var processing: Task<Void, Never>?
    /// Counts processing runs; a cancel moves it on, so a cancelled run reports nothing more.
    private var currentRun = 0

    /// Waits until the recording file holds the recorded audio (`RecordingFile`); tests
    /// pass a stand-in, their fake recordings are not audio.
    typealias RecordingCheck = (_ recording: URL, _ seconds: TimeInterval) async throws -> Void
    private let recordingCheck: RecordingCheck

    /// A copy of the recording kept while it is transcribed, so an error or a crash keeps
    /// what was said (`UnfinishedRecordings`, sealed). `secure` writes the copy and returns
    /// it, nil when there is none; the model reads the recording itself. `release` ends the
    /// transcription. Tests keep no copy.
    struct Safekeeping {
        var secure: @MainActor (URL) -> URL?
        var release: @MainActor (URL) -> Void
        /// Deletes kept recordings past their time; runs after every dictation, so the
        /// 24 hours hold also for people who never open the menu.
        var sweep: @MainActor () -> Void = {}

        static let none = Safekeeping(secure: { _ in nil }, release: { _ in })
    }
    private let safekeeping: Safekeeping

    init(
        recorder: any DictationRecorder,
        recordingCheck: @escaping RecordingCheck = { try await RecordingFile.waitUntilComplete($0, expected: $1) },
        safekeeping: Safekeeping = UnfinishedRecordings.safekeeping
    ) {
        self.recorder = recorder
        self.recordingCheck = recordingCheck
        self.safekeeping = safekeeping
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
            var kept: URL?
            var keepCopy = false
            // The recording is not kept once it is transcribed (docs/privacy.md); only a failed
            // transcription keeps its sealed copy for a while, to be transcribed again.
            defer {
                try? FileManager.default.removeItem(at: url)
                if let kept {
                    safekeeping.release(kept)
                    if !keepCopy { try? FileManager.default.removeItem(at: kept) }
                }
                safekeeping.sweep()
            }
            do {
                try await recordingCheck(url, seconds)
                kept = safekeeping.secure(url)
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
            } catch let failed as AIStepFailed {
                // What was said is not lost; the message says where it is.
                guard run == currentRun else { return }
                onKeptTranscript?(failed.transcript)
                onPhase?(.error(failed.keptMessage))
            } catch {
                // The cancel itself makes the engines throw; that is no error to show, and
                // the recording goes, as the cancel asked.
                guard run == currentRun else { return }
                // "No speech" on a short recording is an accidental shortcut: it goes. On a
                // longer one only Whisper's phrase on a cough says so, and someone may have
                // spoken too quietly, so it is kept like a failure.
                let accidental = (error as? NoSpeechVerdict)?.meansNoSpeech == true
                    && seconds < Self.minimumSecondsKeptWithoutSpeech
                guard let copy = kept, !(error is CancellationError), !accidental else {
                    onPhase?(.error(error.localizedDescription))
                    return
                }
                keepCopy = true
                // Released before the error phase, which refreshes the menu: the recording is
                // listed there at once, also while the menu is open.
                safekeeping.release(copy)
                kept = nil
                onPhase?(.error(error.localizedDescription.appendingSentence(UnfinishedRecordings.notice)))
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
