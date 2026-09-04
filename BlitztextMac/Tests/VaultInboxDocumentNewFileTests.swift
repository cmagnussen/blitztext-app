import XCTest

final class VaultInboxDocumentNewFileTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    private var mitFrontmatter: DictationSettings {
        DictationSettings(
            vaultFolderPath: "/tmp/vault",
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )
    }

    private var ohneFrontmatter: DictationSettings {
        DictationSettings(
            vaultFolderPath: "/tmp/vault",
            writesSecondBrainFrontmatter: false,
            sphere: .beruf
        )
    }

    func testAbschnittIstUhrzeitUndText() {
        let abschnitt = VaultInboxDocument.section(
            text: "Kunde XY nachfassen.",
            at: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )
        XCTAssertEqual(abschnitt, "## 14:07\nKunde XY nachfassen.")
    }

    func testAbschnittEntferntUmschliessendeLeerzeichen() {
        let abschnitt = VaultInboxDocument.section(
            text: "  Kunde XY nachfassen.\n\n",
            at: TestCalendar.date(2026, 9, 4, 9, 42),
            calendar: calendar
        )
        XCTAssertEqual(abschnitt, "## 09:42\nKunde XY nachfassen.")
    }

    func testNeueDateiMitFrontmatterEntsprichtDemFormatAusDerNotiz() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Roher Transkripttext, unverändert.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: mitFrontmatter,
            calendar: calendar
        )

        let erwartet = """
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
        Roher Transkripttext, unverändert.

        """

        XCTAssertEqual(inhalt, erwartet)
    }

    func testNeueDateiUebernimmtDieEingestellteSphaere() {
        var settings = mitFrontmatter
        settings.sphere = .privat
        let inhalt = VaultInboxDocument.newDocument(
            text: "Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings,
            calendar: calendar
        )
        XCTAssertTrue(inhalt.contains("\nsphaere: privat\n"))
        XCTAssertFalse(inhalt.contains("sphaere: beruf"))
    }

    func testNeueDateiOhneFrontmatterBeginntBeiDerUeberschrift() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: ohneFrontmatter,
            calendar: calendar
        )

        let erwartet = """
        # Diktate 04.09.2026

        ## 09:42
        Gedanke.

        """

        XCTAssertEqual(inhalt, erwartet)
        XCTAssertFalse(inhalt.contains("<!-- diktat: offen -->"))
    }

    func testNeueDateiUmZwanzigNachMitternachtTraegtDasDatumDesVortags() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Später Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 0, 20),
            settings: mitFrontmatter,
            calendar: calendar
        )
        XCTAssertTrue(inhalt.contains("erstellt: 2026-09-03"))
        XCTAssertTrue(inhalt.contains("# Diktate 03.09.2026"))
        XCTAssertTrue(inhalt.contains("## 00:20"))
    }
}
