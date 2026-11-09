import XCTest

/// Meeting audio is unencrypted and deleted after the evaluation; a backup must not keep it.
final class MeetingAudioBackupTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-meeting-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testRecordingIsExcludedFromBackup() throws {
        let audio = folder.appendingPathComponent("meeting.wav")
        try Data([0, 1, 2, 3]).write(to: audio)
        XCTAssertEqual(try audio.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)

        MeetingStore.excludeFromBackup(audio)

        XCTAssertEqual(try audio.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    /// The encrypted meetings next to the audio stay in the backup.
    func testOnlyTheRecordingIsExcluded() throws {
        let audio = folder.appendingPathComponent("meeting.wav")
        let meetings = folder.appendingPathComponent(".meetings")
        try Data([0]).write(to: audio)
        try Data([0]).write(to: meetings)

        MeetingStore.excludeFromBackup(audio)

        XCTAssertEqual(try meetings.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
    }

    /// A file that is not there (the capture failed) is no error.
    func testMissingFileIsIgnored() {
        MeetingStore.excludeFromBackup(folder.appendingPathComponent("missing.caf"))
    }
}
