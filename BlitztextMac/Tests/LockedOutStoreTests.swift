import CryptoKit
import XCTest

/// History and meetings while the Keychain does not give the file key (review of #69): nothing
/// recorded then is lost, it waits in a side file and is merged in once the key is back.
/// A folder of its own and fake keys, never Application Support or the real Keychain.
@MainActor
final class LockedOutStoreTests: XCTestCase {
    /// Stands in for `KeychainService`: the file key while available, else the machine key.
    private final class FakeKeys {
        let fileKey = SymmetricKey(size: .bits256)
        let machineKey = SymmetricKey(size: .bits256)
        var fileKeyAvailable = true

        func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
            try XCTUnwrap(AES.GCM.seal(data, using: key).combined)
        }

        func open(_ data: Data) -> Data? {
            guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
            let keys = (fileKeyAvailable ? [fileKey] : []) + [machineKey]
            return keys.lazy.compactMap { try? AES.GCM.open(box, using: $0) }.first
        }
    }

    private var folder: URL!
    private let keys = FakeKeys()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func files(_ name: String) -> SealedStoreFiles {
        let keys = keys
        return SealedStoreFiles(
            mainURL: folder.appendingPathComponent(".\(name)"),
            pendingURL: folder.appendingPathComponent(".\(name)-pending"),
            seal: { try keys.seal($0, with: keys.fileKeyAvailable ? keys.fileKey : keys.machineKey) },
            sealPending: { try keys.seal($0, with: keys.machineKey) },
            open: { keys.open($0) },
            keyIsUnavailable: { !keys.fileKeyAvailable },
            migrateLegacy: { _ in }
        )
    }

    private func entry(_ text: String, minutesAgo: Double) -> TranscriptHistoryEntry {
        TranscriptHistoryEntry(id: UUID(), createdAt: Date().addingTimeInterval(-minutesAgo * 60), workflow: .tapTalk, text: text)
    }

    private func contents(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    // MARK: History

    /// A Jamf restart outside the user's session: the history sealed with the Keychain key does
    /// not open. Before, everything dictated in that session was lost.
    func testHistoryWithoutTheKeyKeepsNewEntriesAndMergesThemLater() throws {
        let files = files("history")
        let old = entry("Vorher", minutesAgo: 30)
        try files.writeMain([old])
        let sealedMain = contents(files.mainURL)

        keys.fileKeyAvailable = false
        let lockedOut = TranscriptHistoryStore(retention: .day, files: files)
        XCTAssertEqual(lockedOut.entries, [])
        lockedOut.add("Im Zug diktiert", workflow: .tapTalk)
        XCTAssertEqual(contents(files.mainURL), sealedMain, "the main file stays untouched")
        XCTAssertNotNil(contents(files.pendingURL))

        // The next launch without the key still shows what waits in the side file.
        XCTAssertEqual(TranscriptHistoryStore(retention: .day, files: files).entries.map(\.text), ["Im Zug diktiert"])

        // A launch with the key merges both and removes the side file.
        keys.fileKeyAvailable = true
        let merged = TranscriptHistoryStore(retention: .day, files: files)
        XCTAssertEqual(merged.entries.map(\.text), ["Im Zug diktiert", "Vorher"])
        XCTAssertNil(contents(files.pendingURL))
        guard case .value(let stored) = files.readMain([TranscriptHistoryEntry].self) else { return XCTFail("main file") }
        XCTAssertEqual(stored.map(\.text), ["Im Zug diktiert", "Vorher"])
    }

    /// The key comes back while the app runs (a keychain unlocked later): the next save merges.
    func testHistoryMergesOnceTheKeyIsBackInTheSameSession() throws {
        let files = files("history")
        try files.writeMain([entry("Vorher", minutesAgo: 30)])

        keys.fileKeyAvailable = false
        let store = TranscriptHistoryStore(retention: .day, files: files)
        store.add("Eins", workflow: .tapTalk)
        keys.fileKeyAvailable = true
        store.add("Zwei", workflow: .tapTalk)

        XCTAssertEqual(store.entries.map(\.text), ["Zwei", "Eins", "Vorher"])
        XCTAssertNil(contents(files.pendingURL))
        guard case .value(let stored) = files.readMain([TranscriptHistoryEntry].self) else { return XCTFail("main file") }
        XCTAssertEqual(stored.map(\.text), ["Zwei", "Eins", "Vorher"])
    }

    /// The key is there and the file still does not open (another Mac's key): kept aside,
    /// never overwritten, and the history goes on.
    func testHistoryThatDoesNotOpenWithTheKeyIsKeptAside() throws {
        let files = files("history")
        let foreign = try XCTUnwrap(AES.GCM.seal(Data("[]".utf8), using: SymmetricKey(size: .bits256)).combined)
        try foreign.write(to: files.mainURL)

        let store = TranscriptHistoryStore(retention: .day, files: files)
        store.add("Neu", workflow: .tapTalk)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix(".history.unreadable-") })
        guard case .value(let stored) = files.readMain([TranscriptHistoryEntry].self) else { return XCTFail("main file") }
        XCTAssertEqual(stored.map(\.text), ["Neu"])
    }

    // MARK: Meetings

    /// Before, every save failed: the meeting was gone after a relaunch and the notice blamed a
    /// full disk. Now it waits in the side file, which counts as saved, so its audio may go.
    func testMeetingWithoutTheKeyCountsAsSavedAndIsMergedLater() throws {
        let files = files("meetings")
        let earlier = MeetingRecord(id: UUID(), createdAt: Date().addingTimeInterval(-3600), title: "Vorher", duration: 600, status: .done)
        try files.writeMain([earlier])
        let sealedMain = contents(files.mainURL)

        keys.fileKeyAvailable = false
        let lockedOut = MeetingStore(files: files)
        XCTAssertEqual(lockedOut.meetings, [])
        let today = MeetingRecord(id: UUID(), createdAt: Date(), title: "Heute", duration: 900, status: .done)
        XCTAssertTrue(lockedOut.upsert(today))
        XCTAssertEqual(contents(files.mainURL), sealedMain)
        XCTAssertEqual(files.readPending([MeetingRecord].self), [today])

        keys.fileKeyAvailable = true
        let merged = MeetingStore(files: files)
        XCTAssertEqual(merged.meetings.map(\.title), ["Heute", "Vorher"])
        XCTAssertNil(contents(files.pendingURL))
    }

    func testMeetingsMergeOnceTheKeyIsBackInTheSameSession() throws {
        let files = files("meetings")
        let earlier = MeetingRecord(id: UUID(), createdAt: Date().addingTimeInterval(-3600), title: "Vorher", duration: 600, status: .done)
        try files.writeMain([earlier])

        keys.fileKeyAvailable = false
        let store = MeetingStore(files: files)
        var today = MeetingRecord(id: UUID(), createdAt: Date(), title: "Heute", duration: 900, status: .pending)
        XCTAssertTrue(store.upsert(today))
        keys.fileKeyAvailable = true
        today.status = .done
        XCTAssertTrue(store.upsert(today))

        XCTAssertEqual(store.meetings.map(\.title), ["Heute", "Vorher"])
        XCTAssertEqual(store.meeting(id: today.id)?.status, .done)
        XCTAssertNil(contents(files.pendingURL))
    }

    /// The side file wins for the same id (it is newer), newest first.
    func testMergeKeepsTheNewerRecord() {
        let id = UUID()
        let main = [entry("Alt", minutesAgo: 10), TranscriptHistoryEntry(id: id, createdAt: Date(), workflow: .tapTalk, text: "Erste Fassung")]
        let pending = [TranscriptHistoryEntry(id: id, createdAt: Date(), workflow: .tapTalk, text: "Zweite Fassung")]
        let merged = LockedOutMerge.merged(main, pending, date: \.createdAt)
        XCTAssertEqual(merged.map(\.text), ["Zweite Fassung", "Alt"])
    }
}
