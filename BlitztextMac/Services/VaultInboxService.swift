import Foundation

enum VaultInboxError: LocalizedError, Equatable {
    case folderNotConfigured
    case folderMissing(String)
    case notWritable(String)
    case existingFileUnreadable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotConfigured:
            return "Kein Ablageordner eingestellt."
        case .folderMissing(let pfad):
            return "Ablageordner nicht gefunden: \(pfad)"
        case .notWritable(let pfad):
            return "Ablageordner ist nicht beschreibbar: \(pfad)"
        case .existingFileUnreadable(let pfad):
            return "Bestehende Tagesdatei ist nicht lesbar: \(pfad)"
        case .writeFailed(let grund):
            return "Schreiben fehlgeschlagen: \(grund)"
        }
    }
}

/// Schreibt Diktate in die Tagesdatei des eingestellten Ordners.
///
/// Ein `actor`, damit zwei Diktate kurz hintereinander nacheinander schreiben
/// und sich nicht überschreiben. Geschrieben wird immer atomar: Inhalt in eine
/// Nachbardatei, dann umbenennen. Nie in die offene Datei hinein.
actor VaultInboxService {
    private let calendar: Calendar
    private let fileManager: FileManager

    init(calendar: Calendar = .current, fileManager: FileManager = .default) {
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// Hängt ein Diktat an die Tagesdatei seines wirksamen Datums an und
    /// liefert die geschriebene Datei zurück.
    func append(text: String, recordedAt: Date, settings: DictationSettings) throws -> URL {
        let ordner = try resolvedFolder(settings.vaultFolderPath)
        let tag = VaultInboxDocument.effectiveDate(for: recordedAt, calendar: calendar)
        let ziel = ordner.appendingPathComponent(
            VaultInboxDocument.fileName(for: tag, calendar: calendar)
        )

        let existiert = fileManager.fileExists(atPath: ziel.path)
        let inhalt: String

        if existiert {
            guard let bestehend = try? String(contentsOf: ziel, encoding: .utf8) else {
                throw VaultInboxError.existingFileUnreadable(ziel.path)
            }
            inhalt = VaultInboxDocument.appended(
                to: bestehend,
                text: text,
                recordedAt: recordedAt,
                calendar: calendar
            )
        } else {
            inhalt = VaultInboxDocument.newDocument(
                text: text,
                recordedAt: recordedAt,
                settings: settings,
                calendar: calendar
            )
        }

        try writeAtomically(inhalt, to: ziel, replacingExisting: existiert, in: ordner)
        return ziel
    }

    /// Der eingestellte Ordner wird nie angelegt. Ein umbenannter oder nicht
    /// eingebundener Vault soll auffallen und nicht heimlich einen leeren
    /// Zwilling bekommen.
    private func resolvedFolder(_ pfad: String) throws -> URL {
        let getrimmt = pfad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getrimmt.isEmpty else { throw VaultInboxError.folderNotConfigured }

        let aufgeloest = (getrimmt as NSString).expandingTildeInPath
        let ordner = URL(fileURLWithPath: aufgeloest, isDirectory: true)

        var istOrdner: ObjCBool = false
        guard fileManager.fileExists(atPath: ordner.path, isDirectory: &istOrdner),
              istOrdner.boolValue else {
            throw VaultInboxError.folderMissing(ordner.path)
        }
        guard fileManager.isWritableFile(atPath: ordner.path) else {
            throw VaultInboxError.notWritable(ordner.path)
        }
        return ordner
    }

    private func writeAtomically(
        _ inhalt: String,
        to ziel: URL,
        replacingExisting: Bool,
        in ordner: URL
    ) throws {
        let temp = ordner.appendingPathComponent(
            ".\(ziel.lastPathComponent).tmp-\(UUID().uuidString)"
        )

        do {
            try inhalt.write(to: temp, atomically: false, encoding: .utf8)
            if replacingExisting {
                _ = try fileManager.replaceItemAt(ziel, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: ziel)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw VaultInboxError.writeFailed(error.localizedDescription)
        }
    }
}
