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
