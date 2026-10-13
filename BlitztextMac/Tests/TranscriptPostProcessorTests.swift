import XCTest

final class TranscriptPostProcessorTests: XCTestCase {
    private let terms = ["Blackboat", "ChargeBee", "Claude", "Copper", "iPhone", "n8n", "Jamf", "Magnussen"]
    private let dictionary: Set<String> = ["cloud", "blackbox", "jam"]

    private func processor(
        correct: Bool = true,
        removeFillers: Bool = true
    ) -> TranscriptPostProcessor {
        TranscriptPostProcessor(
            customTerms: terms,
            correctCustomTerms: correct,
            removeFillerWords: removeFillers,
            language: "de",
            isDictionaryWord: { [dictionary] in dictionary.contains($0.lowercased()) }
        )
    }

    // MARK: Custom terms

    func testMergesMultiWordArtifacts() {
        XCTAssertEqual(processor().process("Wir nutzen Charge B jeden Tag."), "Wir nutzen ChargeBee jeden Tag.")
        XCTAssertEqual(processor().process("Das ist Black Boat."), "Das ist Blackboat.")
        XCTAssertEqual(processor().process("Prüf n 8 n bitte."), "Prüf n8n bitte.")
    }

    func testDoesNotMergeAcrossPunctuation() {
        XCTAssertEqual(processor().process("Wir nutzen Charge B, che ist egal."), "Wir nutzen ChargeBee, che ist egal.")
    }

    func testFixesMisheardSingleWords() {
        XCTAssertEqual(processor().process("Frag mal Clawd."), "Frag mal Claude.")
        XCTAssertEqual(processor().process("Kopper ist offen"), "Copper ist offen")
        XCTAssertEqual(processor().process("Magnusen kommt"), "Magnussen kommt")
    }

    func testKeepsRealDictionaryWords() {
        XCTAssertEqual(processor().process("Das liegt in der Cloud."), "Das liegt in der Cloud.")
        XCTAssertEqual(processor().process("Die Blackbox bleibt."), "Die Blackbox bleibt.")
    }

    func testUsesConfiguredSpelling() {
        XCTAssertEqual(processor().process("Schick das ans iphone."), "Schick das ans iPhone.")
        XCTAssertEqual(processor().process("blackboat rockt"), "Blackboat rockt")
    }

    func testCorrectionCanBeDisabled() {
        XCTAssertEqual(processor(correct: false).process("Frag mal Clawd."), "Frag mal Clawd.")
    }

    func testLeavesTextWithoutMatchesUntouched() {
        let text = "Zeile eins\nZeile zwei"
        XCTAssertEqual(processor().process(text), text)
    }

    func testMatchesSpokenDigitsInTerms() {
        XCTAssertEqual(processor().process("Den Workflow baue ich in n acht n."), "Den Workflow baue ich in n8n.")
        XCTAssertEqual(processor().process("Läuft das in N Acht N?"), "Läuft das in n8n?")
        XCTAssertEqual(processor().process("Ich nehme n eight n dafür."), "Ich nehme n8n dafür.")
    }

    // MARK: Replacements

    func testAppliesReplacements() {
        var processor = processor()
        processor.replacements = [
            TermReplacement(spoken: "en acht en", written: "n8n"),
            TermReplacement(spoken: "Nodemation", written: "n8n"),
        ]
        XCTAssertEqual(processor.process("Das läuft in en acht en."), "Das läuft in n8n.")
        XCTAssertEqual(processor.process("Das läuft in En-Acht-En, oder?"), "Das läuft in n8n, oder?")
        XCTAssertEqual(processor.process("nodemation ist offen"), "n8n ist offen")
    }

    func testReplacementsMatchWholeWordsOnly() {
        var processor = processor()
        processor.replacements = [TermReplacement(spoken: "kai", written: "KI")]
        XCTAssertEqual(processor.process("Kai fragt die kai."), "KI fragt die KI.")
        XCTAssertEqual(processor.process("Kaiser bleibt Kaiser."), "Kaiser bleibt Kaiser.")
    }

    func testReplacementsWorkWithCorrectionDisabled() {
        var processor = processor(correct: false)
        processor.replacements = [TermReplacement(spoken: "en acht en", written: "n8n")]
        XCTAssertEqual(processor.process("in en acht en"), "in n8n")
    }

    // MARK: Filler words

    func testRemovesGermanFillers() {
        XCTAssertEqual(
            processor().process("Äh, ich schreibe dir wegen, ähm, dem Export."),
            "Ich schreibe dir wegen, dem Export."
        )
        XCTAssertEqual(processor().process("Also, äh, um 10 Uhr passt."), "Also, um 10 Uhr passt.")
        XCTAssertEqual(processor().process("Das stimmt hmm."), "Das stimmt.")
        XCTAssertEqual(processor().process("Ähm. Okay."), "Okay.")
    }

    func testKeepsRealWordsThatLookLikeFillers() {
        // "um" is a German preposition and must survive.
        XCTAssertEqual(processor().process("Wir treffen uns um 10 Uhr."), "Wir treffen uns um 10 Uhr.")
        XCTAssertEqual(processor().process("Ähnlich wie ähnlich."), "Ähnlich wie ähnlich.")
    }

    func testFillerRemovalCanBeDisabled() {
        XCTAssertEqual(processor(removeFillers: false).process("Äh, ja."), "Äh, ja.")
    }

    func testCollapsesStutters() {
        XCTAssertEqual(processor().process("ich ich ich ich glaube das"), "ich glaube das")
        XCTAssertEqual(processor().process("das das ist gut"), "das das ist gut")
    }

    func testOnlyFillersResultsInEmptyText() {
        XCTAssertEqual(processor().process("Ähm, äh."), "")
    }

    // MARK: Building blocks

    func testSoundex() {
        XCTAssertEqual(TranscriptPostProcessor.soundex("Robert"), "R163")
        XCTAssertEqual(TranscriptPostProcessor.soundex("Rupert"), "R163")
        XCTAssertEqual(TranscriptPostProcessor.soundex("Ashcraft"), "A261")
        XCTAssertEqual(TranscriptPostProcessor.soundex("Tymczak"), "T522")
        XCTAssertEqual(TranscriptPostProcessor.soundex("Pfister"), "P236")
    }

    func testLevenshtein() {
        XCTAssertEqual(TranscriptPostProcessor.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(TranscriptPostProcessor.levenshtein("", "abc"), 3)
        XCTAssertEqual(TranscriptPostProcessor.levenshtein("same", "same"), 0)
    }
}
