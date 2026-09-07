import CryptoKit
import Foundation

/// Prueft die Ed25519-Signatur eines Update-Archivs.
///
/// Ein von der App selbst geladenes Archiv bekommt kein Quarantaene-Flag,
/// deshalb prueft der Gatekeeper es nie. Diese Pruefung ist der einzige
/// Schutz davor, ein fremdes Bundle zu installieren.
enum UpdateSignatureVerifier {
    static func isValid(signature: Data, for payload: Data, publicKeyBase64: String) -> Bool {
        guard let schluesselDaten = Data(base64Encoded: publicKeyBase64),
              let schluessel = try? Curve25519.Signing.PublicKey(
                  rawRepresentation: schluesselDaten
              )
        else { return false }

        return schluessel.isValidSignature(signature, for: payload)
    }

    /// Die .sig-Datei enthaelt die Signatur als Base64-Text, moeglicherweise
    /// mit abschliessendem Zeilenumbruch.
    static func signature(fromFileContents data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
