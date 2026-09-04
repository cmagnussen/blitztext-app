import Foundation

/// Sphäre der Tagesdatei. Vorgabe ist beruf, weil der Kanal im Arbeitsalltag
/// benutzt wird. Der Inbox-Sortierer korrigiert das je Abschnitt, wenn der
/// Inhalt privat ist. Blitztext soll das nicht erraten.
enum DictationSphere: String, Codable, CaseIterable, Identifiable {
    case beruf
    case privat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beruf: return "Beruf"
        case .privat: return "Privat"
        }
    }
}

/// Einstellungen des Diktat-Kanals. Der Zielordner ist bewusst leer
/// vorbelegt: ohne gesetzten Ordner ist der Workflow nicht verfügbar.
struct DictationSettings: Codable, Equatable {
    var vaultFolderPath: String = ""
    var writesSecondBrainFrontmatter: Bool = false
    var sphere: DictationSphere = .beruf

    init(
        vaultFolderPath: String = "",
        writesSecondBrainFrontmatter: Bool = false,
        sphere: DictationSphere = .beruf
    ) {
        self.vaultFolderPath = vaultFolderPath
        self.writesSecondBrainFrontmatter = writesSecondBrainFrontmatter
        self.sphere = sphere
    }

    enum CodingKeys: String, CodingKey {
        case vaultFolderPath
        case writesSecondBrainFrontmatter
        case sphere
    }

    /// Jedes Feld über decodeIfPresent, damit eine bestehende settings.json
    /// ohne diesen Abschnitt weiter lädt. Gleiches Muster wie AppSettings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaultFolderPath = try container.decodeIfPresent(String.self, forKey: .vaultFolderPath) ?? ""
        writesSecondBrainFrontmatter = try container.decodeIfPresent(
            Bool.self,
            forKey: .writesSecondBrainFrontmatter
        ) ?? false
        sphere = try container.decodeIfPresent(DictationSphere.self, forKey: .sphere) ?? .beruf
    }
}
