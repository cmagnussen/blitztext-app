import XCTest

/// Feste Zeitzone und fester Kalender, damit die Tests nicht davon abhängen,
/// wo und wann sie laufen.
enum TestCalendar {
    static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        calendar: Calendar = berlin
    ) -> Date {
        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year, month: month, day: day,
            hour: hour, minute: minute
        )
        return calendar.date(from: components)!
    }
}

final class VaultInboxDocumentDateTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    func testTagesgrenzeLiegtBeiVierUhr() {
        XCTAssertEqual(VaultInboxDocument.dayStartHour, 4)
    }

    func testViertelVorVierGehoertZumVortag() {
        let now = TestCalendar.date(2026, 9, 4, 3, 45)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-03")
    }

    func testVierUhrGehoertZumLaufendenTag() {
        let now = TestCalendar.date(2026, 9, 4, 4, 0)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-04")
    }

    func testZwanzigNachMitternachtGehoertZumVortag() {
        let now = TestCalendar.date(2026, 9, 4, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-03")
    }

    func testMonatswechselUmZwanzigNachMitternacht() {
        let now = TestCalendar.date(2026, 10, 1, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-30")
    }

    func testJahreswechselUmZwanzigNachMitternacht() {
        let now = TestCalendar.date(2027, 1, 1, 1, 5)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-12-31")
    }

    /// In der Nacht auf den 2026-03-29 wird in Europe/Berlin vorgestellt, der
    /// 29.03. hat 23 Stunden, und nur ein Schritt über diesen Tag entlarvt eine
    /// naive Rechnung mit 86400 Sekunden.
    func testNachDerFruehjahrsumstellungStimmtDerVortag() {
        let now = TestCalendar.date(2026, 3, 30, 1, 30)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-03-29")
    }

    /// In der Nacht auf den 25.10.2026 wird in Europe/Berlin die Uhr
    /// zurückgestellt, der Tag hat 25 Stunden. Dieser Fall sichert die
    /// Datumsarithmetik über den 25-Stunden-Tag ab, unterscheidet aber für
    /// sich allein nicht zwischen kalendarischer und naiver Rechnung.
    func testHerbstumstellungZwanzigNachMitternachtGehoertZumVortag() {
        let now = TestCalendar.date(2026, 10, 26, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-10-25")
    }

    func testDateinameAusWirksamemDatum() {
        let now = TestCalendar.date(2026, 9, 4, 14, 7)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(
            VaultInboxDocument.fileName(for: wirksam, calendar: calendar),
            "2026-09-04-diktat.md"
        )
    }

    func testUeberschriftsdatumIstDeutschFormatiert() {
        let now = TestCalendar.date(2026, 9, 4, 14, 7)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.headingDay(wirksam, calendar: calendar), "04.09.2026")
    }

    func testUhrzeitIstDieEchteUhrzeitUndNichtDieDesWirksamenTages() {
        let now = TestCalendar.date(2026, 9, 4, 0, 20)
        XCTAssertEqual(VaultInboxDocument.clockTime(now, calendar: calendar), "00:20")
    }

    func testEinstellungenHabenSinnvolleVorgaben() {
        let settings = DictationSettings()
        XCTAssertEqual(settings.vaultFolderPath, "")
        XCTAssertFalse(settings.writesSecondBrainFrontmatter)
        XCTAssertEqual(settings.sphere, .beruf)
    }
}
