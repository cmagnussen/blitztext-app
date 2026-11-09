import XCTest

final class SpokenTimeTests: XCTestCase {
    private func format(_ text: String, _ language: String = "de") -> String {
        SpokenTime.format(text, language: language)
    }

    func testTheFeedbackExample() {
        XCTAssertEqual(format("Der Slot ist von 16 Uhr 45 bis 17 Uhr 5."), "Der Slot ist von 16:45 bis 17:05 Uhr.")
    }

    func testSingleTimes() {
        XCTAssertEqual(format("Wir treffen uns um 9 Uhr 30 im Büro."), "Wir treffen uns um 9:30 Uhr im Büro.")
        XCTAssertEqual(format("Abfahrt 23 Uhr 0"), "Abfahrt 23:00 Uhr")
        XCTAssertEqual(format("um 10 Uhr 30 treffen wir uns"), "um 10:30 Uhr treffen wir uns")
    }

    func testFullHoursAndCountsStay() {
        XCTAssertEqual(format("Wir treffen uns um 10 Uhr."), "Wir treffen uns um 10 Uhr.")
        XCTAssertEqual(format("um 10 Uhr 3 Personen"), "um 10 Uhr 3 Personen")
        XCTAssertEqual(format("um 10 Uhr 5 Minuten später"), "um 10 Uhr 5 Minuten später")
    }

    func testInvalidValuesStay() {
        XCTAssertEqual(format("um 25 Uhr 10"), "um 25 Uhr 10")
        XCTAssertEqual(format("um 10 Uhr 75"), "um 10 Uhr 75")
        XCTAssertEqual(format("Seite 1.10 Uhr 5"), "Seite 1.10 Uhr 5")
    }

    func testRangeWithFullHourKeepsBothUhr() {
        XCTAssertEqual(format("von 16 Uhr bis 17 Uhr 30"), "von 16 Uhr bis 17:30 Uhr")
    }

    func testOnlyGerman() {
        XCTAssertEqual(format("at 16 Uhr 45", "en"), "at 16 Uhr 45")
    }
}
