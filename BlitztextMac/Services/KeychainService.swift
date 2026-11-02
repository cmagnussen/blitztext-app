import Foundation
import CryptoKit
import IOKit
import Security

/// AES-GCM encryption for local files such as the history and the meetings.
///
/// The key is a random 256-bit value, created on first use and kept in the Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so the files are bound to this Mac
/// and a copy of a file alone is not enough to read it.
///
/// Builds up to 1.15 derived the key from the machine (IOPlatformUUID plus a salt in the
/// source, which any process can compute). Those keys stay for reading only; files move to
/// the Keychain key the next time they are written, and `migrateIfLegacy` does that on launch.
enum KeychainService {
    private static let service = "app.blitztext.file-key"
    private static let account = "files"

    private static let lock = NSLock()
    private static var fileKeyCache = FileKeyCache()

    /// What the Keychain returned for the file key.
    enum StoredKey: Equatable {
        case found(Data)
        case missing
        /// Locked, access denied, a prompt that would have been needed, or an entry that is not
        /// a 256-bit key.
        case unavailable
    }

    /// The Keychain key, or the machine key while the Keychain cannot give one: a fresh key
    /// that only lives in memory would make the file unreadable after the next launch.
    private static var encryptionKey: SymmetricKey {
        fileKey ?? machineKey
    }

    private static var decryptionKeys: [SymmetricKey] {
        [fileKey].compactMap { $0 } + legacyKeys
    }

    /// Builds with the Blitztext server stored its link and team password in this file.
    static func removeLegacyServerCredentials() {
        try? FileManager.default.removeItem(at: AppSupportPaths.credentialsURL)
    }

    /// Encrypts arbitrary data with the file key.
    static func sealData(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: encryptionKey)
        guard let combined = sealed.combined else {
            throw KeychainError.saveFailed(-1)
        }
        return combined
    }

    static func openData(_ encrypted: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: encrypted) else { return nil }
        for key in decryptionKeys {
            if let data = try? AES.GCM.open(box, using: key) {
                return data
            }
        }
        return nil
    }

    /// Re-seals a file that still opens only with a machine-derived key. Returns whether the
    /// file was rewritten.
    @discardableResult
    static func migrateIfLegacy(at url: URL) -> Bool {
        guard let fileKey,
              let encrypted = try? Data(contentsOf: url),
              let sealed = resealed(encrypted, with: fileKey, legacyKeys: legacyKeys) else { return false }
        return (try? sealed.write(to: url, options: .atomic)) != nil
    }

    /// `encrypted` sealed with `fileKey`, or nil when it already uses that key or opens with
    /// none of `legacyKeys`.
    static func resealed(_ encrypted: Data, with fileKey: SymmetricKey, legacyKeys: [SymmetricKey]) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: encrypted),
              (try? AES.GCM.open(box, using: fileKey)) == nil else { return nil }
        for key in legacyKeys {
            if let data = try? AES.GCM.open(box, using: key) {
                return try? AES.GCM.seal(data, using: fileKey).combined
            }
        }
        return nil
    }

    /// The stored key, or a new one when there is none yet. Nil when the Keychain cannot be
    /// read or refuses the new key. Never deletes or replaces a stored key: a read that fails
    /// once (locked keychain, denied prompt) must not cost the files sealed with it.
    static func resolveFileKey(read: () -> StoredKey, add: (Data) -> OSStatus) -> SymmetricKey? {
        switch read() {
        case .found(let data):
            return SymmetricKey(data: data)
        case .unavailable:
            return nil
        case .missing:
            let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            switch add(created) {
            case errSecSuccess:
                return SymmetricKey(data: created)
            case errSecDuplicateItem:
                // Stored in the meantime: that one is the key.
                if case .found(let data) = read() { return SymmetricKey(data: data) }
                return nil
            default:
                return nil
            }
        }
    }

    /// The answer of the Keychain. A key that was found is kept for the session. A Keychain
    /// that cannot give one (locked, denied prompt, a session outside the user's keychain list)
    /// is left alone for `retryInterval` and then asked again, without UI: every save at every
    /// dictation must not bring a prompt back, but a keychain unlocked later must still count.
    struct FileKeyCache {
        private enum State {
            case unknown
            case available(SymmetricKey)
            case unavailable(since: Date)
        }

        static let retryInterval: TimeInterval = 5 * 60

        private var state = State.unknown

        /// - Parameter resolve: Gets `true` for the first question of the session, the only one
        ///   that may show UI (see `readMayShowUI`).
        mutating func key(now: Date = Date(), resolve: (_ isFirstAsk: Bool) -> SymmetricKey?) -> SymmetricKey? {
            let isFirstAsk: Bool
            switch state {
            case .available(let key):
                return key
            case .unavailable(let since):
                guard now.timeIntervalSince(since) >= Self.retryInterval else { return nil }
                isFirstAsk = false
            case .unknown:
                isFirstAsk = true
            }
            let key = resolve(isFirstAsk)
            state = key.map { .available($0) } ?? .unavailable(since: now)
            return key
        }
    }

    /// True when the Keychain did not give the file key (asked again at most every
    /// `FileKeyCache.retryInterval`). A file that does not open may then be sealed with it: the
    /// stores leave it as it is and keep what this session records in a side file with the
    /// machine key (`SealedStoreFiles`), merged in once the key is back.
    static var fileKeyIsUnavailable: Bool {
        fileKey == nil
    }

    /// Seals a side file written while the Keychain key is unavailable, with the machine key
    /// that every launch can open (`openData` tries it).
    static func sealWithMachineKey(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: machineKey).combined else {
            throw KeychainError.saveFailed(-1)
        }
        return combined
    }

    /// The Jamf postinstall restart passes `-BlitztextLaunchedByInstaller YES`. Such a session
    /// may run outside the user's keychain list, where macOS offered to reset the keychain.
    static var launchedByInstaller: Bool {
        UserDefaults.standard.bool(forKey: "BlitztextLaunchedByInstaller")
    }

    /// The first read of a normal launch may show the system prompt, e.g. to unlock a locked
    /// login keychain; otherwise those Macs would never get their key. Never after an
    /// installer restart, and never on a retry.
    static func readMayShowUI(isFirstAsk: Bool, launchedByInstaller: Bool) -> Bool {
        isFirstAsk && !launchedByInstaller
    }

    // MARK: - Keychain

    private static var fileKey: SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        let installer = launchedByInstaller
        return fileKeyCache.key { isFirstAsk in
            let interactive = readMayShowUI(isFirstAsk: isFirstAsk, launchedByInstaller: installer)
            return resolveFileKey(
                read: { interactive ? readStoredKey(interactive: true) : withoutUserInteraction { readStoredKey(interactive: false) } },
                // Adding a new key never shows UI: started outside the user's normal session (the
                // Jamf restart after an update), macOS showed "Schlüsselbund nicht gefunden" for
                // it, with a button that resets the user's keychain.
                add: { data in withoutUserInteraction { addKey(data) } }
            )
        }
    }

    /// Keychain calls inside fail instead of showing UI.
    private static func withoutUserInteraction<T>(_ body: () -> T) -> T {
        var previous = DarwinBoolean(true)
        let known = SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(known ? previous.boolValue : true) }
        return body()
    }

    private static func readStoredKey(interactive: Bool) -> StoredKey {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !interactive {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    private static func addKey(_ data: Data) -> OSStatus {
        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // MARK: - Machine-derived keys, read only

    /// The v2 key of builds up to 1.15: IOPlatformUUID plus a salt.
    private static var machineKey: SymmetricKey {
        key(for: currentMachineIdentifier(), salt: "app.blitztext.salt.v2")
    }

    private static var legacyKeys: [SymmetricKey] {
        var keys = [machineKey]
        if let hostName = Host.current().name, !hostName.isEmpty {
            keys.append(key(for: hostName, salt: "app.blitztext.salt.v1"))
        }
        keys.append(key(for: "blitztext", salt: "app.blitztext.salt.v1"))
        return keys
    }

    private static func key(for machineID: String, salt: String) -> SymmetricKey {
        let hash = SHA256.hash(data: Data((machineID + salt).utf8))
        return SymmetricKey(data: hash)
    }

    private static func currentMachineIdentifier() -> String {
        if let platformUUID = platformUUID(), !platformUUID.isEmpty {
            return platformUUID
        }
        if let hostName = Host.current().name, !hostName.isEmpty {
            return hostName
        }
        return "blitztext"
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return value
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(Int)

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Daten konnten nicht verschlüsselt werden."
        }
    }
}
