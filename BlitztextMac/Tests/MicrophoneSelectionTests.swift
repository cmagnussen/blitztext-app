import XCTest

/// The chosen microphone is the macOS input only while a dictation records.
final class MicrophoneSelectionTests: XCTestCase {
    private let change = MicrophoneSelection.Switch(previousUID: "BuiltInMicrophoneDevice", chosenUID: "USB-Headset")

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
