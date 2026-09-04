import Foundation

/// Reine Textlogik der Diktat-Tagesdatei: welcher Tag gilt, wie die Datei
/// heißt, wie ihr Kopf und ihre Abschnitte aussehen. Kein Dateisystem, keine
/// Uhr, keine Einstellungen aus der App. Alles hier ist prüfbar, ohne etwas
/// zu schreiben.
enum VaultInboxDocument {
    /// Der Tag wechselt um 04:00. Ein Diktat um 00:20 läuft in die Datei des
    /// Vortags.
    static let dayStartHour = 4

    /// Der Tag, in dessen Datei ein Diktat gehört. Liefert den Tagesbeginn.
    static func effectiveDate(for now: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let hour = calendar.component(.hour, from: now)
        guard hour < dayStartHour else { return startOfDay }
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
    }

    /// "2026-09-04". Für Dateinamen und Frontmatter.
    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "yyyy-MM-dd", calendar: calendar)
    }

    /// "04.09.2026". Für die H1.
    static func headingDay(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "dd.MM.yyyy", calendar: calendar)
    }

    /// "14:07". Die echte Uhrzeit der Aufnahme, nicht die des wirksamen Tages.
    static func clockTime(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "HH:mm", calendar: calendar)
    }

    static func fileName(for effectiveDate: Date, calendar: Calendar) -> String {
        "\(isoDay(effectiveDate, calendar: calendar))-diktat.md"
    }

    /// en_US_POSIX, damit kein Gebietsschema die Ziffern verändert.
    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
