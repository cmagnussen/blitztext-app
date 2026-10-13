import Foundation
import CryptoKit
import IOKit

/// Device-bound AES-GCM encryption for local files such as the history.
/// The key derives from the machine, so encrypted files are not portable. No Keychain prompts.
enum KeychainService {
    // Derive key from machine-specific data so the file isn't portable.
    // v2 prefers IOPlatformUUID; v1 hostname-based key is kept for read migration.
    private static var encryptionKey: SymmetricKey {
        key(
            for: currentMachineIdentifier(),
            salt: "app.blitztext.salt.v2"
        )
    }

    private static var decryptionKeys: [SymmetricKey] {
        var keys = [encryptionKey]
        keys.append(contentsOf: legacyDecryptionKeys())
        return keys
    }

    /// Builds with the Blitztext server stored its link and team password in this file.
    static func removeLegacyServerCredentials() {
        try? FileManager.default.removeItem(at: AppSupportPaths.credentialsURL)
    }

    /// Encrypts arbitrary data with the device-bound key.
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

    // MARK: - Internal

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

    private static func legacyDecryptionKeys() -> [SymmetricKey] {
        var keys: [SymmetricKey] = []
        if let hostName = Host.current().name, !hostName.isEmpty {
            keys.append(key(for: hostName, salt: "app.blitztext.salt.v1"))
        }
        keys.append(key(for: "blitztext", salt: "app.blitztext.salt.v1"))
        return keys
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
