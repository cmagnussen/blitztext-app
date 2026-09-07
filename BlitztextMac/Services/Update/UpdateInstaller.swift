import AppKit
import Foundation

enum UpdateInstallError: LocalizedError {
    case signaturUngueltig
    case zielNichtBeschreibbar
    case entpackenFehlgeschlagen(String)
    case keinBundleImArchiv
    case fremdesBundle
    case nichtNeuer
    case tauschFehlgeschlagen(String)

    var errorDescription: String? {
        switch self {
        case .signaturUngueltig:
            return "Die Signatur des Downloads passt nicht. "
                + "Das Update wurde verworfen und nicht installiert."
        case .zielNichtBeschreibbar:
            return "Der Ordner mit der Blitztext-Installation ist nicht beschreibbar, "
                + "die bisherige Version ist unverändert. Prüfe die Rechte an /Applications."
        case .entpackenFehlgeschlagen(let text):
            return "Das Archiv ließ sich nicht entpacken, die bisherige Version "
                + "ist unverändert. \(text)"
        case .keinBundleImArchiv:
            return "Im Archiv steckt nicht genau eine App. "
                + "Die bisherige Version ist unverändert."
        case .fremdesBundle:
            return "Die App im Archiv gehört nicht zu Blitztext. "
                + "Die bisherige Version ist unverändert."
        case .nichtNeuer:
            return "Die App im Archiv ist nicht neuer als die installierte Version."
        case .tauschFehlgeschlagen(let text):
            return "Der Austausch ist fehlgeschlagen, die bisherige Version "
                + "ist unverändert. \(text)"
        }
    }
}

/// Tauscht das eigene App-Bundle gegen ein geprueftes Update.
///
/// Reihenfolge ist Absicht: Signatur, Entpacken neben dem Ziel, Bundle pruefen,
/// erst dann der atomare Tausch. Bis dahin bleibt die bestehende Installation
/// unangetastet, ein Abbruch kann sie also nicht beschaedigen.
enum UpdateInstaller {
    /// Schritt 1: Signatur pruefen. Schlaegt sie fehl, fliegt die Datei
    /// sofort raus und nichts weiter passiert.
    static func verify(archiv: URL, signatur: Data, publicKeyBase64: String) throws {
        let inhalt = try Data(contentsOf: archiv, options: .mappedIfSafe)
        guard UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: publicKeyBase64
        ) else {
            try? FileManager.default.removeItem(at: archiv)
            throw UpdateInstallError.signaturUngueltig
        }
    }

    /// Schritte 2 bis 5. Setzt eine bestandene Pruefung voraus und beendet
    /// die App im Erfolgsfall, damit sie neu startet.
    static func install(archiv: URL, erwarteteVersion: AppVersion) throws {
        let eigenesBundle = BlitztextInstallLocationService.bundleURL
        let elternordner = eigenesBundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: elternordner.path) else {
            throw UpdateInstallError.zielNichtBeschreibbar
        }

        // 2. Entpacken neben das Ziel-Bundle. Gleiches Volume ist Pflicht,
        //    sonst ist replaceItemAt kein atomarer Rename mehr.
        let arbeitsordner = elternordner
            .appendingPathComponent(".blitztext-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: arbeitsordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: arbeitsordner) }

        try entpacke(archiv, nach: arbeitsordner)

        // 3. Pruefen, was da wirklich entpackt wurde.
        let neuesBundle = try pruefeBundle(in: arbeitsordner, erwarteteVersion: erwarteteVersion)

        // 4. Atomarer Tausch.
        do {
            _ = try FileManager.default.replaceItemAt(eigenesBundle, withItemAt: neuesBundle)
        } catch {
            throw UpdateInstallError.tauschFehlgeschlagen(error.localizedDescription)
        }

        // 5. Neustart.
        starteNeu(bundle: eigenesBundle)
    }

    private static func entpacke(_ archiv: URL, nach ordner: URL) throws {
        let prozess = Process()
        prozess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        prozess.arguments = ["-x", "-k", archiv.path, ordner.path]

        let fehlerkanal = Pipe()
        prozess.standardError = fehlerkanal
        try prozess.run()

        // Erst lesen, dann warten: readDataToEndOfFile blockiert bis das
        // Programm endet, umgekehrt koennte ein voller Puffer blockieren.
        let fehlertext = String(
            data: fehlerkanal.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        prozess.waitUntilExit()

        guard prozess.terminationStatus == 0 else {
            throw UpdateInstallError.entpackenFehlgeschlagen(fehlertext)
        }
    }

    private static func pruefeBundle(in ordner: URL, erwarteteVersion: AppVersion) throws -> URL {
        let inhalte = try FileManager.default.contentsOfDirectory(
            at: ordner,
            includingPropertiesForKeys: nil
        )
        let apps = inhalte.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let neu = apps.first else {
            throw UpdateInstallError.keinBundleImArchiv
        }

        guard let bundle = Bundle(url: neu),
              let identifier = bundle.bundleIdentifier,
              identifier == Bundle.main.bundleIdentifier
        else {
            throw UpdateInstallError.fremdesBundle
        }

        guard let roh = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(string: roh),
              let aktuell = AppVersion.current,
              version > aktuell,
              version == erwarteteVersion
        else {
            throw UpdateInstallError.nichtNeuer
        }
        return neu
    }

    private static func starteNeu(bundle: URL) {
        let prozess = Process()
        prozess.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Der Pfad wird als Argument uebergeben und landet in $0. Wuerde er in den
        // Befehl geschrieben, koennte ein Anfuehrungszeichen oder Backtick im Pfad
        // aus der Quotierung ausbrechen.
        prozess.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$0\"", bundle.path]
        try? prozess.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
