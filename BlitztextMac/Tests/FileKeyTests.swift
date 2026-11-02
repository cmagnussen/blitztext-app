import CryptoKit
import Security
import XCTest

/// The file key logic without the real Keychain: these tests never read or write it.
final class FileKeyTests: XCTestCase {
    private let stored = Data(repeating: 7, count: 32)

    func testUsesTheStoredKeyAndWritesNothing() {
        var adds = 0
        let key = KeychainService.resolveFileKey(read: { .found(stored) }, add: { _ in adds += 1; return errSecSuccess })
        XCTAssertEqual(key.map(raw), stored)
        XCTAssertEqual(adds, 0)
    }

    func testCreatesAKeyOnlyWhenNoneIsStored() {
        var added: Data?
        let key = KeychainService.resolveFileKey(read: { .missing }, add: { added = $0; return errSecSuccess })
        XCTAssertEqual(added?.count, 32)
        XCTAssertEqual(key.map(raw), added)
    }

    func testAKeychainThatCannotBeReadCreatesNoKey() {
        // A locked keychain or a denied prompt must not lead to a new key: files sealed with
        // the stored one would become unreadable.
        var adds = 0
        XCTAssertNil(KeychainService.resolveFileKey(read: { .unavailable }, add: { _ in adds += 1; return errSecSuccess }))
        XCTAssertEqual(adds, 0)
    }

    func testARefusedWriteGivesNoKey() {
        XCTAssertNil(KeychainService.resolveFileKey(read: { .missing }, add: { _ in errSecInteractionNotAllowed }))
    }

    func testAKeyStoredInTheMeantimeWins() {
        var reads = 0
        let key = KeychainService.resolveFileKey(
            read: {
                reads += 1
                return reads == 1 ? .missing : .found(stored)
            },
            add: { _ in errSecDuplicateItem }
        )
        XCTAssertEqual(key.map(raw), stored)
    }

    func testResealsALegacyFileOnce() throws {
        let legacy = SymmetricKey(size: .bits256)
        let fileKey = SymmetricKey(size: .bits256)
        let old = try XCTUnwrap(AES.GCM.seal(Data("Verlauf".utf8), using: legacy).combined)

        let resealed = try XCTUnwrap(KeychainService.resealed(old, with: fileKey, legacyKeys: [legacy]))
        let box = try AES.GCM.SealedBox(combined: resealed)
        XCTAssertEqual(try AES.GCM.open(box, using: fileKey), Data("Verlauf".utf8))
        XCTAssertThrowsError(try AES.GCM.open(box, using: legacy))
        XCTAssertNil(KeychainService.resealed(resealed, with: fileKey, legacyKeys: [legacy]))
    }

    func testLeavesAFileNoKnownKeyOpens() throws {
        let other = try XCTUnwrap(AES.GCM.seal(Data("x".utf8), using: SymmetricKey(size: .bits256)).combined)
        XCTAssertNil(KeychainService.resealed(other, with: SymmetricKey(size: .bits256), legacyKeys: [SymmetricKey(size: .bits256)]))
    }

    /// A Keychain that cannot give the key is asked once per session, not at every save
    /// (review of #68: a prompt with every dictation).
    func testAnUnavailableKeychainIsAskedOnce() {
        var cache = KeychainService.FileKeyCache()
        var asked = 0
        for _ in 0..<3 {
            XCTAssertNil(cache.key { asked += 1; return nil })
        }
        XCTAssertEqual(asked, 1)
    }

    /// After a Jamf update the restarted app could not add the key ("no keychain found"):
    /// the Keychain is asked once, and the rest of the session uses the machine key.
    func testAKeychainThatRefusesTheNewKeyIsNotAskedAgainThisSession() {
        var cache = KeychainService.FileKeyCache()
        var reads = 0
        var adds = 0
        for _ in 0..<3 {
            let key = cache.key {
                KeychainService.resolveFileKey(
                    read: { reads += 1; return .missing },
                    add: { _ in adds += 1; return errSecNoDefaultKeychain }
                )
            }
            XCTAssertNil(key)
        }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(adds, 1)
    }

    func testAFoundKeyIsKeptForTheSession() {
        var cache = KeychainService.FileKeyCache()
        let key = SymmetricKey(size: .bits256)
        var asked = 0
        XCTAssertEqual(cache.key { asked += 1; return key }.map(raw), raw(key))
        XCTAssertEqual(cache.key { asked += 1; return nil }.map(raw), raw(key))
        XCTAssertEqual(asked, 1)
    }

    private func raw(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
