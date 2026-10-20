import XCTest

final class ListDisplayTests: XCTestCase {
    func testBulletPointsGetABullet() {
        let summary = "Entscheidungen\n- Der Workshop findet online statt\n\nTo-dos\n- Paul: Angebot schicken"
        XCTAssertEqual(
            ListDisplay.bullets(summary),
            "Entscheidungen\n\u{2022} Der Workshop findet online statt\n\nTo-dos\n\u{2022} Paul: Angebot schicken"
        )
    }

    func testOtherDashesStay() {
        XCTAssertEqual(ListDisplay.bullets("Zahlen -5 % zum Vorjahr\n-Keine"), "Zahlen -5 % zum Vorjahr\n-Keine")
    }
}
