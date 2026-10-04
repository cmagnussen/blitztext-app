import Foundation

@main
enum TranscriptParagraphServiceTests {
    static func expect(_ actual: String, _ expected: String, _ name: String) {
        guard actual == expected else {
            fatalError("\(name): expected \(expected.debugDescription), got \(actual.debugDescription)")
        }
    }

    static func main() {
        let sentences = [
            "Heute schreiben wir einen Brief.",
            "Dieser Brief enthält wichtige Informationen.",
            "Wir schicken ihn morgen weiter.",
            "Die Antwort erwarten wir nächste Woche.",
            "Danach planen wir die nächsten Schritte."
        ]
        let firstFour = sentences.prefix(4).joined(separator: " ")
        let input = sentences.joined(separator: " ")
        let expected = firstFour + "\n\n" + sentences[4]
        expect(TranscriptParagraphService.format(input, language: "de"), expected, "Four substantial sentences")
        expect(TranscriptParagraphService.format(firstFour, language: "de"), firstFour, "No trailing paragraph")
        expect(TranscriptParagraphService.format("Ja. OK. Nein. Gut. " + input, language: "de"),
               "Ja. OK. Nein. Gut. " + expected, "Interjections do not count")

        let longSentence = Array(repeating: "Wort", count: 46).joined(separator: " ") + "."
        expect(TranscriptParagraphService.format(longSentence + " Danach folgt mehr Text.", language: "de"),
               longSentence + "\n\nDanach folgt mehr Text.", "Word cap ends at sentence boundary")
        expect(TranscriptParagraphService.format(longSentence, language: "de"), longSentence, "Never split one sentence")
        expect(TranscriptParagraphService.format("Hallo 👋, das ist ein Test!", language: "de"),
               "Hallo 👋, das ist ein Test!", "Unicode and short text")
        expect(TranscriptParagraphService.format(""), "", "Empty text")
        expect(TranscriptParagraphService.format("   \n"), "   \n", "Whitespace preserved")

        let existing = sentences.prefix(2).joined(separator: " ") + "\r\n \r\n" + sentences.suffix(3).joined(separator: " ")
        expect(TranscriptParagraphService.format(existing, language: "de"), existing, "Existing paragraphs reset counts")
        expect(TranscriptParagraphService.format(expected, language: "de"), expected, "Formatting is idempotent")

        let abbreviation = "Dr. Müller schreibt heute einen Brief."
        let abbreviatedInput = ([abbreviation] + Array(sentences.prefix(3))).joined(separator: " ")
        expect(TranscriptParagraphService.format(abbreviatedInput + " " + sentences[4], language: "de"),
               abbreviatedInput + "\n\n" + sentences[4], "German abbreviation")

        let large = Array(repeating: input, count: 100).joined(separator: " ")
        let start = Date()
        let formatted = TranscriptParagraphService.format(large, language: "de")
        let milliseconds = Date().timeIntervalSince(start) * 1000
        expect(formatted.filter { !$0.isWhitespace }, large.filter { !$0.isWhitespace }, "Words and punctuation preserved")
        print("12 paragraph checks passed; \(large.split(whereSeparator: \.isWhitespace).count)-word formatting: \(String(format: "%.2f", milliseconds)) ms")
    }
}
