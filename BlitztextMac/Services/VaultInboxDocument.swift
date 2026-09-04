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

    // MARK: - Bausteine

    /// Ein Abschnitt ist die Uhrzeit als H2 und darunter der rohe
    /// Transkripttext. Nichts sonst.
    static func section(text: String, at time: Date, calendar: Calendar) -> String {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "## \(clockTime(time, calendar: calendar))\n\(roh)"
    }

    /// Inhalt einer Tagesdatei, die es noch nicht gibt. Legt Frontmatter,
    /// Marker, H1 und den ersten Abschnitt an.
    static func newDocument(
        text: String,
        recordedAt: Date,
        settings: DictationSettings,
        calendar: Calendar
    ) -> String {
        let tag = effectiveDate(for: recordedAt, calendar: calendar)
        var bloecke: [String] = []

        if settings.writesSecondBrainFrontmatter {
            bloecke.append(frontmatter(day: isoDay(tag, calendar: calendar), sphere: settings.sphere))
            bloecke.append("<!-- diktat: offen -->")
        }

        bloecke.append("# Diktate \(headingDay(tag, calendar: calendar))")
        bloecke.append(section(text: text, at: recordedAt, calendar: calendar))

        return bloecke.joined(separator: "\n\n") + "\n"
    }

    /// Hängt einen Abschnitt an eine bestehende Tagesdatei. Berührt sonst
    /// nur das Feld `aktualisiert` im Frontmatter. H1 und Marker bleiben, wie
    /// sie sind.
    static func appended(
        to existing: String,
        text: String,
        recordedAt: Date,
        calendar: Calendar
    ) -> String {
        let tag = effectiveDate(for: recordedAt, calendar: calendar)
        let aktualisiert = updatingFrontmatterDate(
            in: existing,
            to: isoDay(tag, calendar: calendar)
        )

        var rumpf = aktualisiert
        while rumpf.hasSuffix("\n") {
            rumpf.removeLast()
        }

        let abschnitt = section(text: text, at: recordedAt, calendar: calendar)
        return "\(rumpf)\n\n\(abschnitt)\n"
    }

    /// Setzt `aktualisiert` ausschließlich innerhalb des ersten `---` bis
    /// `---` Blocks am Dateianfang. Eine Zeile im Diktattext, die wie
    /// Frontmatter aussieht, wird nicht angefasst. Fehlt der Block oder das
    /// Feld, bleibt der Inhalt unverändert.
    static func updatingFrontmatterDate(in content: String, to isoDay: String) -> String {
        var zeilen = content.components(separatedBy: "\n")
        guard zeilen.first == "---" else { return content }
        guard let ende = zeilen.dropFirst().firstIndex(of: "---") else { return content }
        guard ende > 1 else { return content }

        var geaendert = false
        for index in 1..<ende where zeilen[index].hasPrefix("aktualisiert:") {
            zeilen[index] = "aktualisiert: \(isoDay)"
            geaendert = true
        }

        guard geaendert else { return content }
        return zeilen.joined(separator: "\n")
    }

    /// Feste Werte laut Konzeptnotiz. Die Sphäre ist der einzige Wert, der
    /// variiert.
    private static func frontmatter(day: String, sphere: DictationSphere) -> String {
        """
        ---
        typ: log
        status: aktiv
        topf: inbox
        sphaere: \(sphere.rawValue)
        themen: []
        quelle: gespräch
        stichworte: [diktat, schnellerfassung]
        erstellt: \(day)
        aktualisiert: \(day)
        geprüft:
        ---
        """
    }
}
