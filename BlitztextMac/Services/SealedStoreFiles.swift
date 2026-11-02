import Foundation

/// The files of a store sealed with the Keychain file key: the history and the meetings.
///
/// When the main file does not open because the Keychain did not give the key (a Jamf restart
/// outside the user's session, a locked keychain), the store keeps saving: what is recorded
/// then goes to a side file sealed with the machine key, which every launch can read. Once the
/// key is there again, the side file is merged into the main file and removed, so nothing
/// recorded in such a session is lost. Tests pass their own folder and keys.
struct SealedStoreFiles {
    let mainURL: URL
    let pendingURL: URL
    var seal: (Data) throws -> Data
    var sealPending: (Data) throws -> Data
    var open: (Data) -> Data?
    var keyIsUnavailable: () -> Bool
    /// Moves a main file still sealed with a machine-derived key to the Keychain key.
    var migrateLegacy: (URL) -> Void

    enum Read<Value> {
        case missing
        case value(Value)
        case unreadable
    }

    func readMain<Value: Decodable>(_ type: Value.Type) -> Read<Value> {
        guard let stored = try? Data(contentsOf: mainURL) else { return .missing }
        guard let data = open(stored), let value = try? JSONDecoder().decode(type, from: data) else { return .unreadable }
        return .value(value)
    }

    /// Nil when there is no side file, or none this build can read.
    func readPending<Value: Decodable>(_ type: Value.Type) -> Value? {
        guard let stored = try? Data(contentsOf: pendingURL), let data = open(stored) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func writeMain<Value: Encodable>(_ value: Value) throws {
        try write(value, sealedWith: seal, to: mainURL)
    }

    func writePending<Value: Encodable>(_ value: Value) throws {
        try write(value, sealedWith: sealPending, to: pendingURL)
    }

    func removeMain() {
        try? FileManager.default.removeItem(at: mainURL)
    }

    func removePending() {
        try? FileManager.default.removeItem(at: pendingURL)
    }

    /// A main file that does not open although the key is there (another Mac's key, a later
    /// format): kept aside instead of being overwritten, so it can still be recovered.
    func moveMainAside(now: Date = Date()) {
        let aside = mainURL.deletingLastPathComponent()
            .appendingPathComponent(mainURL.lastPathComponent + ".unreadable-\(Int(now.timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: mainURL, to: aside)
    }

    private func write<Value: Encodable>(_ value: Value, sealedWith seal: (Data) throws -> Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try seal(try JSONEncoder().encode(value)).write(to: url, options: .atomic)
    }
}

extension SealedStoreFiles {
    /// The Keychain file key, or the machine key while there is none (`KeychainService`).
    static func keychain(main: URL, pending: URL) -> SealedStoreFiles {
        SealedStoreFiles(
            mainURL: main,
            pendingURL: pending,
            seal: KeychainService.sealData,
            sealPending: KeychainService.sealWithMachineKey,
            open: KeychainService.openData,
            keyIsUnavailable: { KeychainService.fileKeyIsUnavailable },
            migrateLegacy: { KeychainService.migrateIfLegacy(at: $0) }
        )
    }

    static var history: SealedStoreFiles {
        keychain(main: AppSupportPaths.historyURL, pending: AppSupportPaths.historyPendingURL)
    }
}

/// Records kept in the side file merged into the ones of the main file: for the same id the
/// side file wins (it is newer), newest first.
enum LockedOutMerge {
    static func merged<Record: Identifiable>(
        _ main: [Record], _ pending: [Record], date: (Record) -> Date
    ) -> [Record] where Record.ID: Hashable {
        let pendingIDs = Set(pending.map(\.id))
        return (pending + main.filter { !pendingIDs.contains($0.id) })
            .sorted { date($0) > date($1) }
    }
}
