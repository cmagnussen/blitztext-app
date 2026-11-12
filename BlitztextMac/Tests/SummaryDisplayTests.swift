import XCTest

final class SummaryDisplayTests: XCTestCase {
    func testLeadingSummaryTitleIsDroppedAndOtherTitlesAreMarked() {
        let lines = SummaryDisplay.lines("Zusammenfassung\nDer Workshop findet online statt.\n\nEntscheidungen\n- Online\n\n**To-dos:**\n- Person 1: Einladung")
        XCTAssertEqual(lines, [
            .init(text: "Der Workshop findet online statt.", isTitle: false),
            .init(text: "", isTitle: false),
            .init(text: "Entscheidungen", isTitle: true),
            .init(text: "\u{2022} Online", isTitle: false),
            .init(text: "", isTitle: false),
            .init(text: "To-dos", isTitle: true),
            .init(text: "\u{2022} Person 1: Einladung", isTitle: false),
        ])
    }

    func testSummaryWithoutTitlesStaysAsItIs() {
        XCTAssertEqual(SummaryDisplay.lines("Kurz und gut."), [.init(text: "Kurz und gut.", isTitle: false)])
    }

    func testSummaryTitleFurtherDownStays() {
        let lines = SummaryDisplay.lines("Entscheidungen\n- Online\n\nZusammenfassung\nText")
        XCTAssertEqual(lines.filter(\.isTitle).map(\.text), ["Entscheidungen", "Zusammenfassung"])
    }
}
