import XCTest

final class VaultInboxDocumentAppendTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    private let bestehendMitFrontmatter = """
    ---
    typ: log
    status: aktiv
    topf: inbox
    sphaere: beruf
    themen: []
    quelle: gespräch
    stichworte: [diktat, schnellerfassung]
    erstellt: 2026-09-04
    aktualisiert: 2026-09-04
    geprüft:
    ---

    <!-- diktat: offen -->

    # Diktate 04.09.2026

    ## 09:42
    Erster Gedanke.

    """

    func testAnhaengenErgaenztDenZweitenAbschnitt() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasSuffix("## 09:42\nErster Gedanke.\n\n## 14:07\nZweiter Gedanke.\n"))
    }

    func testAnhaengenLaesstKopfUndMarkerUnberuehrt() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasPrefix("---\ntyp: log\n"))
        XCTAssertEqual(ergebnis.components(separatedBy: "<!-- diktat: offen -->").count - 1, 1)
        XCTAssertEqual(ergebnis.components(separatedBy: "# Diktate 04.09.2026").count - 1, 1)
        XCTAssertTrue(ergebnis.contains("stichworte: [diktat, schnellerfassung]"))
        XCTAssertTrue(ergebnis.contains("topf: inbox"))
    }

    func testAnhaengenSetztAktualisiertUndLaesstErstelltStehen() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Nachtrag am nächsten Tag.",
            recordedAt: TestCalendar.date(2026, 9, 5, 10, 0),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.contains("erstellt: 2026-09-04"))
        XCTAssertTrue(ergebnis.contains("aktualisiert: 2026-09-05"))
    }

    /// Der wichtigste Test dieses Tasks: eine Zeile im Diktattext, die wie
    /// Frontmatter aussieht, darf nicht angefasst werden.
    func testZeileImTextDieWieFrontmatterAussiehtBleibtUnberuehrt() {
        let bestehend = """
        ---
        typ: log
        aktualisiert: 2026-09-04
        ---

        # Diktate 04.09.2026

        ## 09:42
        aktualisiert: 2020-01-01 hatte im alten Vault noch gestimmt.

        """

        let ergebnis = VaultInboxDocument.appended(
            to: bestehend,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 5, 10, 0),
            calendar: calendar
        )

        // Diese Zeile beginnt mit "aktualisiert:", liegt aber ausserhalb des
        // Frontmatter-Blocks. Sie muss unangetastet bleiben.
        XCTAssertTrue(ergebnis.contains("aktualisiert: 2020-01-01 hatte im alten Vault noch gestimmt."))
        XCTAssertTrue(ergebnis.hasPrefix("---\ntyp: log\naktualisiert: 2026-09-05\n---"))
    }

    func testDateiOhneFrontmatterBekommtKeinesDazu() {
        let bestehend = """
        # Diktate 04.09.2026

        ## 09:42
        Erster Gedanke.

        """

        let ergebnis = VaultInboxDocument.appended(
            to: bestehend,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasPrefix("# Diktate 04.09.2026"))
        XCTAssertFalse(ergebnis.contains("---"))
        XCTAssertTrue(ergebnis.hasSuffix("## 14:07\nZweiter Gedanke.\n"))
    }

    func testMehrfachesAnhaengenErzeugtGenauEineLeerzeileDazwischen() {
        var inhalt = VaultInboxDocument.newDocument(
            text: "Eins.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 0),
            settings: DictationSettings(writesSecondBrainFrontmatter: true),
            calendar: calendar
        )
        inhalt = VaultInboxDocument.appended(
            to: inhalt,
            text: "Zwei.",
            recordedAt: TestCalendar.date(2026, 9, 4, 10, 0),
            calendar: calendar
        )
        inhalt = VaultInboxDocument.appended(
            to: inhalt,
            text: "Drei.",
            recordedAt: TestCalendar.date(2026, 9, 4, 11, 0),
            calendar: calendar
        )

        XCTAssertTrue(inhalt.hasSuffix("## 09:00\nEins.\n\n## 10:00\nZwei.\n\n## 11:00\nDrei.\n"))
        XCTAssertFalse(inhalt.contains("\n\n\n"))
    }

    func testFrontmatterDatumOhneAktualisiertZeileBleibtUnveraendert() {
        let bestehend = "---\ntyp: log\n---\n\n# Diktate 04.09.2026\n"
        let ergebnis = VaultInboxDocument.updatingFrontmatterDate(in: bestehend, to: "2026-09-05")
        XCTAssertEqual(ergebnis, bestehend)
    }

    func testTextOhneFrontmatterBlockBleibtUnveraendert() {
        let bestehend = "# Diktate 04.09.2026\n\n## 09:42\naktualisiert: 2020-01-01\n"
        let ergebnis = VaultInboxDocument.updatingFrontmatterDate(in: bestehend, to: "2026-09-05")
        XCTAssertEqual(ergebnis, bestehend)
    }
}
