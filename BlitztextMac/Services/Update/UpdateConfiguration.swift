import Foundation

/// Update-Einstellungen aus dem Bundle. Ein Fork tauscht diese beiden Werte
/// in der Info.plist und muss sonst nichts am Code aendern.
enum UpdateConfiguration {
    static var repository: String? {
        wert(fuer: "BLZUpdateRepository")
    }

    static var publicKey: String? {
        wert(fuer: "BLZUpdatePublicKey")
    }

    /// Fallback fuer jeden Fehlerfall: die Release-Seite im Browser.
    static var releasesPageURL: URL? {
        guard let repository else { return nil }
        return URL(string: "https://github.com/\(repository)/releases/latest")
    }

    private static func wert(fuer schluessel: String) -> String? {
        guard let roh = Bundle.main.object(forInfoDictionaryKey: schluessel) as? String else {
            return nil
        }
        let bereinigt = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        return bereinigt.isEmpty ? nil : bereinigt
    }
}
