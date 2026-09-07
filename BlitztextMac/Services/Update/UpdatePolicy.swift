import Foundation

/// Entscheidungen rund um Updates, bewusst als reine Funktionen ohne Netz,
/// Dateisystem und Oberflaeche, damit sie vollstaendig testbar sind.
enum UpdatePolicy {
    /// Beim Start und danach hoechstens einmal pro Kalendertag.
    static func shouldRunAutomaticCheck(
        now: Date,
        lastCheck: Date?,
        automaticChecksEnabled: Bool,
        calendar: Calendar
    ) -> Bool {
        guard automaticChecksEnabled else { return false }
        guard let lastCheck else { return true }
        return !calendar.isDate(lastCheck, inSameDayAs: now)
    }

    enum InstallBlock: Equatable {
        case entwicklungsBuild
        case beschaeftigt

        var hinweis: String {
            switch self {
            case .entwicklungsBuild:
                return "Dieser Build läuft nicht aus dem Programme-Ordner. "
                    + "Aktualisiere ihn mit git pull und einem eigenen Build."
            case .beschaeftigt:
                return "Blitztext nimmt gerade auf. Das Update läuft, "
                    + "sobald die Aufnahme fertig ist."
            }
        }
    }

    /// Der Entwicklungs-Build wiegt schwerer: Dort gibt es gar keinen Button,
    /// waehrend die Beschaeftigt-Sperre nur voruebergehend ist.
    static func installBlock(isInApplicationsFolder: Bool, isBusy: Bool) -> InstallBlock? {
        if !isInApplicationsFolder { return .entwicklungsBuild }
        if isBusy { return .beschaeftigt }
        return nil
    }
}
