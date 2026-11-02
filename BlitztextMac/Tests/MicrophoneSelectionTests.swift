import XCTest

/// The chosen microphone is the macOS input only while a dictation records.
final class MicrophoneSelectionTests: XCTestCase {
    private let change = MicrophoneSelection.Switch(previousUID: "BuiltInMicrophoneDevice", chosenUID: "USB-Headset")

    /// Review of #68: a dictation during a Blitztext meeting moved the meeting to its microphone.
    func testNoSwitchWhileAMeetingRecords() {
        XCTAssertTrue(MicrophoneSelection.shouldSwitch(preferredUID: "USB-Headset", meetingIsRecording: false))
        XCTAssertFalse(MicrophoneSelection.shouldSwitch(preferredUID: "USB-Headset", meetingIsRecording: true))
        XCTAssertFalse(MicrophoneSelection.shouldSwitch(preferredUID: "", meetingIsRecording: false))
    }

    /// Review of #69: a meeting started while a dictation recorded keeps its input; the switch
    /// is undone when the meeting ends, unless a dictation still records.
    func testRestoreWaitsForTheMeetingToEnd() {
        XCTAssertTrue(MicrophoneSelection.restoreIsDueAfterMeeting(wasRecording: true, isRecording: false, dictationIsRecording: false))
        XCTAssertFalse(MicrophoneSelection.restoreIsDueAfterMeeting(wasRecording: true, isRecording: false, dictationIsRecording: true))
        XCTAssertFalse(MicrophoneSelection.restoreIsDueAfterMeeting(wasRecording: false, isRecording: true, dictationIsRecording: false))
        XCTAssertFalse(MicrophoneSelection.restoreIsDueAfterMeeting(wasRecording: false, isRecording: false, dictationIsRecording: false))
    }

    func testRestoresWhileTheChosenMicrophoneIsStillTheInput() {
        XCTAssertTrue(MicrophoneSelection.shouldRestore(currentUID: "USB-Headset", after: change))
    }

    /// Changed in the System Settings meanwhile, or macOS fell back after unplugging: that wins.
    func testLeavesAnInputChosenMeanwhile() {
        XCTAssertFalse(MicrophoneSelection.shouldRestore(currentUID: "Webcam", after: change))
        XCTAssertFalse(MicrophoneSelection.shouldRestore(currentUID: nil, after: change))
    }

    /// Kept in the defaults until undone, so the next launch repairs a crash mid-recording.
    func testSwitchSurvivesARestart() throws {
        let data = try JSONEncoder().encode(change)
        XCTAssertEqual(try JSONDecoder().decode(MicrophoneSelection.Switch.self, from: data), change)
    }
}
