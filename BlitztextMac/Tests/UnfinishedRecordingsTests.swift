import XCTest

/// Kept dictations are sealed (public issue #54). Every test works in a folder of its own,
/// never in Application Support.
final class UnfinishedRecordingsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-unfinished-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Stand-in for the file key: reversible, and the plain bytes never appear.
    private static func seal(_ data: Data) -> Data { Data("SEALED".utf8) + Data(data.reversed()) }
    private static func open(_ data: Data) -> Data? {
        guard data.starts(with: Data("SEALED".utf8)) else { return nil }
        return Data(data.dropFirst(6).reversed())
    }

    private func recording(_ text: String = "RIFF voice of the user") throws -> URL {
        let url = folder.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testKeptCopyIsSealedPrivateAndOutOfBackups() throws {
        let recording = try recording()
        let kept = try XCTUnwrap(UnfinishedRecordings.writeSealed(
            contentsOf: recording, seconds: 12.34, seal: Self.seal, in: folder.appendingPathComponent("Unfinished")
        ))
        let stored = try Data(contentsOf: kept)
        XCTAssertNil(stored.range(of: Data("voice of the user".utf8)))
        XCTAssertEqual(Self.open(stored), try Data(contentsOf: recording))
        XCTAssertEqual(kept.pathExtension, UnfinishedRecordings.sealedExtension)
        let permissions = try FileManager.default.attributesOfItem(atPath: kept.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try kept.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The recording itself is the model's; the copy does not touch it.
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }

    /// The real seal of a kept recording: a session that never asked the Keychain (as in
    /// this test process) uses the machine key, and opening works without asking either.
    func testSealWithoutAskingRoundTrips() throws {
        let audio = Data("RIFF voice of the user".utf8)
        let sealed = try KeychainService.sealDataWithoutAsking(audio)
        XCTAssertNil(sealed.range(of: Data("voice".utf8)))
        XCTAssertEqual(KeychainService.openDataWithoutAsking(sealed), audio)
        XCTAssertNil(KeychainService.openDataWithoutAsking(Data("not sealed".utf8)))
    }

    func testLengthTravelsInTheName() {
        let url = folder.appendingPathComponent(UnfinishedRecordings.fileName(seconds: 134.26))
        XCTAssertEqual(UnfinishedRecordings.seconds(fromName: url), 134.3)
        XCTAssertNil(UnfinishedRecordings.seconds(fromName: folder.appendingPathComponent("snapshot.sealed")))
    }

    func testFailedSealLeavesNothing() throws {
        struct Locked: Error {}
        let target = folder.appendingPathComponent("Unfinished")
        XCTAssertNil(UnfinishedRecordings.writeSealed(contentsOf: try recording(), seconds: 1, seal: { _ in throw Locked() }, in: target))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    }

    func testOpenedCopyIsPlainAndPrivate() throws {
        let recording = try recording()
        let kept = try XCTUnwrap(UnfinishedRecordings.writeSealed(contentsOf: recording, seconds: 3, seal: Self.seal, in: folder))
        let item = UnfinishedRecordings.Item(url: kept, recordedAt: Date(), seconds: 3)
        let copy = try XCTUnwrap(UnfinishedRecordings.openedCopy(of: item, open: Self.open, openAsking: { _ in XCTFail("asked the Keychain"); return nil }))
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: recording))
        // The launch cleanup knows the prefix, so a crash leaves no plain copy for long.
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("blitztext-import-"))
        let permissions = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testOpenedCopyNeedsTheKey() throws {
        let kept = try XCTUnwrap(UnfinishedRecordings.writeSealed(contentsOf: try recording(), seconds: 3, seal: Self.seal, in: folder))
        let item = UnfinishedRecordings.Item(url: kept, recordedAt: Date(), seconds: 3)
        XCTAssertNil(UnfinishedRecordings.openedCopy(of: item, open: { _ in nil }, openAsking: { _ in nil }))
    }

    /// Sealed with the file key in an earlier session: only then the Keychain is asked.
    func testOpenedCopyAsksOnlyWhenTheSessionKeysFail() throws {
        let kept = try XCTUnwrap(UnfinishedRecordings.writeSealed(contentsOf: try recording(), seconds: 3, seal: Self.seal, in: folder))
        let item = UnfinishedRecordings.Item(url: kept, recordedAt: Date(), seconds: 3)
        var asked = 0
        let copy = try XCTUnwrap(UnfinishedRecordings.openedCopy(of: item, open: { _ in nil }, openAsking: { asked += 1; return Self.open($0) }))
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertEqual(asked, 1)
    }

    func testSealedFileKeepsTheAgeOfAPlainOne() throws {
        let recorded = Date(timeIntervalSince1970: 1_793_610_660)
        let kept = try XCTUnwrap(UnfinishedRecordings.writeSealed(
            contentsOf: try recording(), seconds: 3, seal: Self.seal, recordedAt: recorded, in: folder
        ))
        let created = try kept.resourceValues(forKeys: [.creationDateKey]).creationDate
        XCTAssertEqual(created?.timeIntervalSince1970 ?? 0, recorded.timeIntervalSince1970, accuracy: 1)
    }
}
