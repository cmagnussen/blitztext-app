import XCTest

final class TextPartsTests: XCTestCase {
    private let text = "Ich: Wir fangen mit den Zahlen an.\nAndere: Die liegen seit gestern vor.\nIch: Gut, dann weiter."

    func testShortTextFitsWhole() {
        XCTAssertEqual(TextParts.endOfLeadingPart(of: text, limit: 1_000), text.endIndex)
        XCTAssertEqual(TextParts.startOfTrailingPart(of: text, limit: 1_000), text.startIndex)
    }

    func testLeadingPartEndsAfterAWholeLine() {
        let end = TextParts.endOfLeadingPart(of: text, limit: 50)
        XCTAssertEqual(String(text[..<end]), "Ich: Wir fangen mit den Zahlen an.\n")
    }

    func testLeadingPartOfOneLongLineEndsAfterAWord() {
        let line = "Andere: Die liegen seit gestern vor und sind vollständig."
        let end = TextParts.endOfLeadingPart(of: line, limit: 20)
        XCTAssertEqual(String(line[..<end]), "Andere: Die liegen ")
    }

    func testTrailingPartStartsAtAWholeLine() {
        let start = TextParts.startOfTrailingPart(of: text, limit: 40)
        XCTAssertEqual(String(text[start...]), "Ich: Gut, dann weiter.")
    }

    func testPartsCoverEverything() {
        var rest = text[...]
        var parts: [String] = []
        while !rest.isEmpty {
            let remaining = String(rest)
            let end = TextParts.endOfLeadingPart(of: remaining, limit: 30)
            parts.append(String(remaining[..<end]))
            rest = rest.dropFirst(remaining.distance(from: remaining.startIndex, to: end))
        }
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 30 })
    }
}
