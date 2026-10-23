import XCTest

/// Stand-in for the microphone: records at once, or fails like a denied microphone.
private final class FakeRecorder: DictationRecorder {
    var isRecording = false
    var errorMessage: String?
    var recordingURL: URL?
    var lastRecordingDuration: TimeInterval = 0
    var audioLevel: Float = 0

    var startError: String?
    var recordedSeconds: TimeInterval = 2
    private(set) var discarded = false

    func startRecording() {
        errorMessage = startError
        guard startError == nil else { return }
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
        lastRecordingDuration = recordedSeconds
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-test-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        recordingURL = url
    }

    func discardRecording() {
        discarded = true
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }
}

/// One dictation with the stand-in microphone; keeps what the run announces.
@MainActor
private final class Dictation {
    let recorder = FakeRecorder()
    let run: DictationRun
    private(set) var phases: [WorkflowPhase] = []
    private(set) var outputs: [String] = []
    /// Whether the microphone already recorded when each phase was announced.
    private(set) var recordingAtPhase: [Bool] = []

    init() {
        run = DictationRun(recorder: recorder)
        run.onPhase = { [unowned self] phase in
            phases.append(phase)
            recordingAtPhase.append(recorder.isRecording)
        }
        run.onOutput = { [unowned self] text in outputs.append(text) }
    }

    var errors: [String] {
        phases.compactMap { phase in
            if case .error(let message) = phase { return message }
            return nil
        }
    }
}

@MainActor
final class DictationRunTests: XCTestCase {
    // MARK: Start

    /// The pill and the menu bar icon decide "recording" when the phase changes, and only
    /// a recording pill takes the click that stops it.
    func testRecordingIsAnnouncedOnlyOnceTheMicrophoneRuns() {
        let dictation = Dictation()
        dictation.run.start()
        XCTAssertEqual(dictation.phases, [.running(DictationRun.recordingMessage)])
        XCTAssertEqual(dictation.recordingAtPhase, [true])
    }

    func testMicrophoneThatDoesNotStartOnlyReportsItsError() {
        let dictation = Dictation()
        dictation.recorder.startError = "Kein Mikrofon"
        dictation.run.start()
        XCTAssertEqual(dictation.phases, [.error("Kein Mikrofon")])
    }

    // MARK: Processing

    func testDeliversTheProcessedTextOnce() async {
        let dictation = Dictation()
        dictation.run.start()
        var heardSeconds: TimeInterval?
        await dictation.run.stop { _, seconds, _ in
            heardSeconds = seconds
            return "Hallo Welt"
        }?.value
        XCTAssertEqual(heardSeconds, 2)
        XCTAssertEqual(dictation.phases, [
            .running(DictationRun.recordingMessage),
            .running(DictationRun.transcribingMessage),
            .done("Hallo Welt"),
        ])
        XCTAssertEqual(dictation.outputs, ["Hallo Welt"])
    }

    func testShowsEachProcessingStep() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, step in
            step("Text wird verbessert ...")
            return "Besser"
        }?.value
        XCTAssertTrue(dictation.phases.contains(.running("Text wird verbessert ...")))
        XCTAssertEqual(dictation.phases.last, .done("Besser"))
    }

    func testNothingRecognizedIsReported() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, _ in nil }?.value
        XCTAssertEqual(dictation.errors, [DictationRun.nothingRecognizedMessage])
        XCTAssertEqual(dictation.outputs, [])
    }

    func testFailureIsReported() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, _ in throw URLError(.timedOut) }?.value
        XCTAssertEqual(dictation.errors, [URLError(.timedOut).localizedDescription])
    }

    func testTooShortRecordingIsDiscardedUnprocessed() async {
        let dictation = Dictation()
        dictation.recorder.recordedSeconds = 0.1
        dictation.run.start()
        var processed = false
        await dictation.run.stop { _, _, _ in
            processed = true
            return "Text"
        }?.value
        XCTAssertFalse(processed)
        XCTAssertTrue(dictation.recorder.discarded)
        XCTAssertEqual(dictation.errors, [DictationRun.nothingRecognizedMessage])
    }

    /// docs/privacy.md: a recording is not kept once it is transcribed.
    func testRecordingIsDeletedAfterProcessing() async {
        let dictation = Dictation()
        dictation.run.start()
        var recording: URL?
        await dictation.run.stop { url, _, _ in
            recording = url
            return "Text"
        }?.value
        let url = try? XCTUnwrap(recording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url?.path ?? ""))
    }

    // MARK: Cancelling (Escape, a new dictation, closing the menu)

    /// A transcription or rewrite that finishes after the cancel must not paste.
    func testResultAfterCancelIsNotDelivered() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, _ in
            dictation.run.cancel()
            return "Zu spät"
        }?.value
        XCTAssertEqual(dictation.outputs, [])
        XCTAssertFalse(dictation.phases.contains(.done("Zu spät")))
        XCTAssertEqual(dictation.phases.last, .idle)
    }

    /// The cancel itself makes the engines throw; that is no error for the user, and it
    /// must not end the dictation that replaced this one.
    func testErrorAfterCancelIsNotReported() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, _ in
            dictation.run.cancel()
            throw CancellationError()
        }?.value
        XCTAssertEqual(dictation.errors, [])
        XCTAssertEqual(dictation.phases.last, .idle)
    }

    func testStepAfterCancelIsNotShown() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, step in
            dictation.run.cancel()
            step("Text wird verbessert ...")
            return nil
        }?.value
        XCTAssertFalse(dictation.phases.contains(.running("Text wird verbessert ...")))
        XCTAssertEqual(dictation.errors, [])
        XCTAssertEqual(dictation.phases.last, .idle)
    }

    func testStopWhileProcessingCancels() async {
        let dictation = Dictation()
        dictation.run.start()
        await dictation.run.stop { _, _, _ in
            _ = dictation.run.stop { _, _, _ in "Zweiter Stopp" }
            return "Zu spät"
        }?.value
        XCTAssertEqual(dictation.outputs, [])
        XCTAssertEqual(dictation.phases.last, .idle)
    }

    func testCancelWhileRecordingDiscardsTheRecording() {
        let dictation = Dictation()
        dictation.run.start()
        dictation.run.cancel()
        XCTAssertFalse(dictation.run.isRecording)
        XCTAssertTrue(dictation.recorder.discarded)
        XCTAssertEqual(dictation.phases.last, .idle)
    }
}

/// What a shortcut or Escape does while a dictation may already run.
final class DictationControlTests: XCTestCase {
    private let recording = WorkflowPhase.running(DictationRun.recordingMessage)
    private let transcribing = WorkflowPhase.running(DictationRun.transcribingMessage)

    func testShortcutStartsWhenNothingRuns() {
        for holdToRecord in [true, false] {
            XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: holdToRecord, phase: nil, isRecording: false), .start)
            XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: holdToRecord, phase: .done("Text"), isRecording: false), .start)
            XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: holdToRecord, phase: .error("Fehler"), isRecording: false), .start)
        }
    }

    /// Hold mode: pressing again right after letting go used to cancel the dictation that
    /// was still being transcribed, and its late error then ended the new recording.
    func testHoldShortcutLetsTheRunningDictationFinish() {
        XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: true, phase: transcribing, isRecording: false), .ignore)
        XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: true, phase: recording, isRecording: true), .ignore)
    }

    func testToggleShortcutStopsTheRecordingOnly() {
        XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: false, phase: recording, isRecording: true), .stop)
        XCTAssertEqual(DictationControl.shortcutDown(holdToRecord: false, phase: transcribing, isRecording: false), .ignore)
    }

    func testReleasingTheHoldShortcutOnlyEndsARecording() {
        XCTAssertEqual(DictationControl.shortcutUp(holdToRecord: true, isRecording: true), .stop)
        XCTAssertEqual(DictationControl.shortcutUp(holdToRecord: true, isRecording: false), .ignore)
        XCTAssertEqual(DictationControl.shortcutUp(holdToRecord: false, isRecording: true), .ignore)
    }

    func testEscapeEndsARecordingAndCancelsProcessing() {
        XCTAssertEqual(DictationControl.escape(phase: recording, isRecording: true), .stop)
        XCTAssertEqual(DictationControl.escape(phase: transcribing, isRecording: false), .cancel)
        XCTAssertEqual(DictationControl.escape(phase: nil, isRecording: false), .ignore)
        XCTAssertEqual(DictationControl.escape(phase: .done("Text"), isRecording: false), .ignore)
    }
}
