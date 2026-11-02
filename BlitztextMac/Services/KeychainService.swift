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
    private static var cachedFileKey: SymmetricKey?

    /// What the Keychain returned for the file key.
    enum StoredKey: Equatable {
        case found(Data)
        case missing
        /// Locked, access denied, or an entry that is not a 256-bit key.
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

    // MARK: - Keychain

    /// Found once, kept for the session; asked again while the Keychain cannot give one.
    private static var fileKey: SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedFileKey { return cachedFileKey }
        cachedFileKey = resolveFileKey(read: readStoredKey, add: addKey)
        return cachedFileKey
    }

    private static func readStoredKey() -> StoredKey {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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
