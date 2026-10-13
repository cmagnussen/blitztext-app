import XCTest

/// Ported from the checks in cmagnussen/blitztext-app PR #21.
final class TranscriptParagraphServiceTests: XCTestCase {
    private let sentences = [
        "Heute schreiben wir einen Brief.",
        "Dieser Brief enthält wichtige Informationen.",
        "Wir schicken ihn morgen weiter.",
        "Die Antwort erwarten wir nächste Woche.",
        "Danach planen wir die nächsten Schritte.",
    ]

    private var firstFour: String { sentences.prefix(4).joined(separator: " ") }
    private var input: String { sentences.joined(separator: " ") }
    private var expected: String { firstFour + "\n\n" + sentences[4] }

    private func format(_ text: String) -> String {
        TranscriptParagraphService.format(text, language: "de")
    }

    func testBreaksAfterFourSubstantialSentences() {
        XCTAssertEqual(format(input), expected)
        XCTAssertEqual(format(firstFour), firstFour)
    }

    func testInterjectionsDoNotCount() {
        XCTAssertEqual(format("Ja. OK. Nein. Gut. " + input), "Ja. OK. Nein. Gut. " + expected)
    }

    func testWordCapEndsAtSentenceBoundaryOnly() {
        let longSentence = Array(repeating: "Wort", count: 46).joined(separator: " ") + "."
        XCTAssertEqual(format(longSentence + " Danach folgt mehr Text."), longSentence + "\n\nDanach folgt mehr Text.")
        XCTAssertEqual(format(longSentence), longSentence)
    }

    func testLeavesShortAndEmptyTextAlone() {
        XCTAssertEqual(format("Hallo 👋, das ist ein Test!"), "Hallo 👋, das ist ein Test!")
        XCTAssertEqual(TranscriptParagraphService.format(""), "")
        XCTAssertEqual(TranscriptParagraphService.format("   \n"), "   \n")
    }

    func testKeepsExistingParagraphsAndIsIdempotent() {
        let existing = sentences.prefix(2).joined(separator: " ") + "\r\n \r\n" + sentences.suffix(3).joined(separator: " ")
        XCTAssertEqual(format(existing), existing)
        XCTAssertEqual(format(expected), expected)
    }

    func testGermanAbbreviation() {
        let abbreviated = (["Dr. Müller schreibt heute einen Brief."] + Array(sentences.prefix(3))).joined(separator: " ")
        XCTAssertEqual(format(abbreviated + " " + sentences[4]), abbreviated + "\n\n" + sentences[4])
    }

    func testPreservesWordsAndPunctuation() {
        let large = Array(repeating: input, count: 100).joined(separator: " ")
        XCTAssertEqual(format(large).filter { !$0.isWhitespace }, large.filter { !$0.isWhitespace })
    }
}
