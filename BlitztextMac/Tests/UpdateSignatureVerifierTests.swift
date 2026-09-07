import XCTest
import CryptoKit

final class UpdateSignatureVerifierTests: XCTestCase {
    private let inhalt = Data("Blitztext 1.6.0".utf8)

    func testGueltigeSignaturWirdAkzeptiert() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertTrue(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: schluessel.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testFalscherSchluesselWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let fremder = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: fremder.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testManipulierterInhaltWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: Data("Blitztext 1.6.1".utf8),
            publicKeyBase64: schluessel.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testUnbrauchbarerSchluesselWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: "kein base64 schluessel"
        ))
    }

    /// Sauberes Base64, aber keine 32 Bytes: Der PublicKey-Init wirft, und die
    /// Pruefung muss das als Ablehnung behandeln statt als Ausnahme.
    func testSchluesselMitFalscherLaengeWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: Data(repeating: 0, count: 31).base64EncodedString()
        ))
    }

    /// Genau der Zustand, in dem dieser Branch ausgeliefert wird: In der
    /// Info.plist steht noch kein Schluessel. Ohne Schluessel wird nichts
    /// installiert.
    func testLeererSchluesselWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: ""
        ))
    }

    func testSignaturdateiWirdAusBase64Gelesen() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)
        let dateiInhalt = Data((signatur.base64EncodedString() + "\n").utf8)

        XCTAssertEqual(UpdateSignatureVerifier.signature(fromFileContents: dateiInhalt), signatur)
    }

    func testUnleserlicheSignaturdateiErgibtNil() {
        XCTAssertNil(UpdateSignatureVerifier.signature(fromFileContents: Data("!!!".utf8)))
    }
}
