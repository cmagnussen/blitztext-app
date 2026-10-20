import XCTest

final class TranscriptPostProcessorTests: XCTestCase {
    private let terms = ["Blackboat", "HubSpot", "Claude", "Copper", "iPhone", "n8n", "Jamf", "Magnussen"]
    private let dictionary: Set<String> = ["cloud", "blackbox", "jam"]
    private let threshold = TranscriptPostProcessor().correctionThreshold

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
        XCTAssertEqual(processor().process("Die Kontakte liegen in Hub Spot."), "Die Kontakte liegen in HubSpot.")
        XCTAssertEqual(processor().process("Das ist Black Boat."), "Das ist Blackboat.")
        XCTAssertEqual(processor().process("Prüf n 8 n bitte."), "Prüf n8n bitte.")
    }

    func testDoesNotMergeAcrossPunctuation() {
        XCTAssertEqual(processor().process("Erst Black, dann Boat."), "Erst Black, dann Boat.")
        XCTAssertEqual(processor().process("Das war Black. Boat kommt später."), "Das war Black. Boat kommt später.")
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

    func testKeepsShortAndCommonWords() {
        XCTAssertEqual(processor().process("Ja, das passt."), "Ja, das passt.")
        XCTAssertEqual(processor().process("Wir sehen uns am Montag."), "Wir sehen uns am Montag.")
        XCTAssertEqual(processor().process("Mach bitte eine Kopie davon."), "Mach bitte eine Kopie davon.")
        XCTAssertEqual(processor().process("Der Jam gestern war gut."), "Der Jam gestern war gut.")
        XCTAssertEqual(processor().process("Die Koffer sind gepackt."), "Die Koffer sind gepackt.")
        XCTAssertEqual(processor().process("Ist das Klo da hinten?"), "Ist das Klo da hinten?")
    }

    func testKeepsOtherWordsBuiltOnATerm() {
        // A name of its own, and the term with a genitive ending.
        XCTAssertEqual(processor().process("Ich treffe Magnus morgen."), "Ich treffe Magnus morgen.")
        XCTAssertEqual(processor().process("Magnussens Vorschlag steht."), "Magnussens Vorschlag steht.")
        // The word in front is not swallowed into the term.
        XCTAssertEqual(processor().process("Leg das in Hubspott an."), "Leg das in Hubspott an.")
    }

    func testFuzzyMatchesSkipKnownWords() {
        var processor = processor()
        processor.isDictionaryWord = { ["blackboard", "hab", "spot"].contains($0.lowercased()) }
        // Written as one, "Black Board" is a word; "Hab" and "Spot" are words each.
        XCTAssertEqual(processor.process("Schreib es an das Black Board."), "Schreib es an das Black Board.")
        XCTAssertEqual(processor.process("Leg das in Hab Spot an."), "Leg das in Hab Spot an.")

        processor.isDictionaryWord = { _ in false }
        XCTAssertEqual(processor.process("Schreib es an das Black Board."), "Schreib es an das Blackboat.")
        XCTAssertEqual(processor.process("Leg das in Hab Spot an."), "Leg das in HubSpot an.")
    }

    func testDoesNotJoinAcrossLineBreaks() {
        XCTAssertEqual(processor().process("Das ist Black\nBoat"), "Das ist Black\nBoat")
    }

    func testKeepsWhitespaceAroundCorrections() {
        XCTAssertEqual(processor().process("Zeile eins\nFrag Clawd"), "Zeile eins\nFrag Claude")
        XCTAssertEqual(
            TranscriptPostProcessor.applyCustomTerms(
                to: "Erste Zeile\n\n  Frag  Clawd\tund  Kopper.\n",
                customTerms: terms,
                threshold: threshold
            ),
            "Erste Zeile\n\n  Frag  Claude\tund  Copper.\n"
        )
    }

    func testKeepsPunctuationAroundCorrections() {
        XCTAssertEqual(processor().process("Frag (iphone) und \"Clawd\"!"), "Frag (iPhone) und \"Claude\"!")
    }

    func testEmailAddresses() {
        // A dictation that is only an address stays lowercase.
        XCTAssertEqual(TranscriptPostProcessor().process("Test at outlook.com"), "test@outlook.com")
        // A similar custom term never changes a part of an address.
        let processor = TranscriptPostProcessor(customTerms: ["Meyer", "Firmo"])
        XCTAssertEqual(
            processor.process("Schreib an meier at firma punkt de, danke Meier."),
            "Schreib an meier@firma.de, danke Meyer."
        )
    }

    func testHandlesUmlautsAndSharpS() {
        let processor = TranscriptPostProcessor(
            customTerms: ["Müller", "Strauß"],
            isDictionaryWord: { $0.lowercased() == "straße" }
        )
        XCTAssertEqual(processor.process("Grüße an Frau Müler, bis bald."), "Grüße an Frau Müller, bis bald.")
        XCTAssertEqual(processor.process("Herr MUELLER kommt."), "Herr Müller kommt.")
        XCTAssertEqual(processor.process("Familie Strauss zahlt."), "Familie Strauß zahlt.")
        // Close to the term, but a real word.
        XCTAssertEqual(processor.process("Die Straße bleibt."), "Die Straße bleibt.")
    }

    func testPrefersLongerSpanOnEqualScores() {
        XCTAssertEqual(
            TranscriptPostProcessor.applyCustomTerms(
                to: "Leg es in hub spot ab.",
                customTerms: ["Hub", "HubSpot"],
                threshold: threshold
            ),
            "Leg es in HubSpot ab."
        )
    }

    func testPrefersClosestTerm() {
        XCTAssertEqual(
            TranscriptPostProcessor.applyCustomTerms(
                to: "Frag Clawd.",
                customTerms: ["Claudia", "Claude"],
                threshold: threshold
            ),
            "Frag Claude."
        )
    }

    func testDigitsAreNeverGuessed() {
        XCTAssertEqual(
            TranscriptPostProcessor.applyCustomTerms(to: "Siehe Projekt7.", customTerms: ["Projekt8"], threshold: threshold),
            "Siehe Projekt7."
        )
    }

    func testLongTranscriptWithManyTermsIsFast() {
        let sentence = "Ich habe mit Clawd gestern über den Export in Hub Spot gesprochen, und Kopper ist offen. "
            + "Wir treffen uns um zehn Uhr bei Magnusen im Büro, danach baue ich den Workflow "
            + "in n acht n und schicke dir die Zusammenfassung aufs iphone."
        let corrected = "Ich habe mit Claude gestern über den Export in HubSpot gesprochen, und Copper ist offen. "
            + "Wir treffen uns um zehn Uhr bei Magnussen im Büro, danach baue ich den Workflow "
            + "in n8n und schicke dir die Zusammenfassung aufs iPhone."
        let sentenceWords = sentence.split(separator: " ")
        let text = (0..<2_000).map { sentenceWords[$0 % sentenceWords.count] }.joined(separator: " ")

        // 100 terms: the usual ones plus made-up names.
        let syllables = ["ka", "lo", "mir", "ten", "dra", "vos", "bel", "quin", "sto", "ra", "pex", "ul", "fen"]
        let count = syllables.count
        let madeUp = (0..<(100 - terms.count)).map { index in
            (syllables[index % count] + syllables[(index / count + 5) % count] + syllables[(index * 7 + 3) % count]).capitalized
        }
        let manyTerms = terms + madeUp
        XCTAssertEqual(Set(manyTerms).count, 100)
        // Like the app's dictionary: the regular words are known, the misheard ones are not.
        let misheard: Set<String> = ["clawd", "kopper", "magnusen"]
        let known = Set(sentenceWords.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) })
            .subtracting(misheard)

        var result = ""
        let elapsed = ContinuousClock().measure {
            result = TranscriptPostProcessor.applyCustomTerms(
                to: text,
                customTerms: manyTerms,
                threshold: threshold,
                isDictionaryWord: { known.contains($0.lowercased()) }
            )
        }
        XCTAssertTrue(result.hasPrefix(corrected), String(result.prefix(300)))
        #if DEBUG
        // Unoptimized test build; an optimized build needs about 5 ms on Apple silicon.
        let budget = Duration.seconds(1)
        #else
        let budget = Duration.milliseconds(50)
        #endif
        XCTAssertLessThan(elapsed, budget)
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

    func testRemovesStretchedFillersButKeepsWords() {
        XCTAssertEqual(processor().process("Ähhhm, HMMM, das ist eh egal."), "Das ist eh egal.")
        XCTAssertEqual(processor().process("Mhm, passt."), "Mhm, passt.")
    }

    func testFillerListsDependOnLanguage() {
        var processor = processor()
        processor.language = "en-US"
        XCTAssertEqual(processor.process("Um, we meet at ten, uh, maybe."), "We meet at ten, maybe.")
        processor.language = "de_DE"
        XCTAssertEqual(processor.process("Ähm, um zehn, äh, passt."), "Um zehn, passt.")
        // Other languages only lose sounds that are no word anywhere.
        processor.language = "pt"
        XCTAssertEqual(processor.process("Hmm, uh, um café."), "Uh, um café.")
    }

    func testStuttersKeepFirstWordAndLastPunctuation() {
        XCTAssertEqual(processor().process("Gut. Ich, ich, ich glaube schon."), "Gut. Ich glaube schon.")
        XCTAssertEqual(processor().process("Das war es es es."), "Das war es.")
    }

    func testStuttersKeepDeliberateRepetition() {
        XCTAssertEqual(processor().process("Nein. Nein. Nein."), "Nein. Nein. Nein.")
        XCTAssertEqual(processor().process("Es kostet 10 10 10 Euro."), "Es kostet 10 10 10 Euro.")
        XCTAssertEqual(TranscriptPostProcessor.collapseStutters("das das ist gut"), "das das ist gut")
    }

    // MARK: Building blocks

    func testColognePhoneticsReferenceExamples() {
        XCTAssertEqual(TranscriptPostProcessor.colognePhonetics("Müller-Lüdenscheidt"), "65752682")
        XCTAssertEqual(TranscriptPostProcessor.colognePhonetics("Wikipedia"), "3412")
        XCTAssertEqual(TranscriptPostProcessor.colognePhonetics("Breschnew"), "17863")
    }

    func testColognePhoneticsGroupsSimilarSounds() {
        let code = TranscriptPostProcessor.colognePhonetics
        XCTAssertEqual(code("Kopper"), code("Copper"))
        XCTAssertEqual(code("Meier"), code("Mayr"))
        XCTAssertEqual(code("Philipp"), code("Filip"))
        XCTAssertEqual(code("Müller"), code("Mueller"))
        // C is hard at the start before a, soft before e and after s; x is "ks".
        XCTAssertEqual(code("Carl"), "475")
        XCTAssertEqual(code("Celle"), "85")
        XCTAssertEqual(code("Schmidt"), "862")
        XCTAssertEqual(code("Xaver"), "4837")
    }

    func testEditDistanceCountsNeighbourSwapsOnce() {
        XCTAssertEqual(TranscriptPostProcessor.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(TranscriptPostProcessor.editDistance("ab", "ba"), 1)
        XCTAssertEqual(TranscriptPostProcessor.editDistance("Clawd", "Claude"), 2)
        XCTAssertEqual(TranscriptPostProcessor.editDistance("", "abc"), 3)
        XCTAssertEqual(TranscriptPostProcessor.editDistance("Müller", "Müller"), 0)
        XCTAssertEqual(TranscriptPostProcessor.editDistance("Müller", "Muller"), 1)
    }

    func testSpellingAndSoundSimilarity() {
        XCTAssertEqual(TranscriptPostProcessor.spellingSimilarity("Müller", "MUELLER"), 1)
        XCTAssertEqual(TranscriptPostProcessor.spellingSimilarity("Kopper", "Copper"), 5.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(TranscriptPostProcessor.soundSimilarity("Kopper", "Copper"), 1)
        // "aw" before a consonant is a vowel, as in English.
        XCTAssertEqual(TranscriptPostProcessor.soundSimilarity("Clawd", "Claude"), 1)
        XCTAssertEqual(TranscriptPostProcessor.soundSimilarity("glaube", "Claude"), 2.0 / 3, accuracy: 1e-9)
    }

    func testTermSimilarityScale() {
        let similarity = TranscriptPostProcessor.termSimilarity
        XCTAssertEqual(similarity("Hub Spot", "HubSpot"), 1)
        XCTAssertEqual(similarity("MUELLER", "Müller"), 1)
        XCTAssertEqual(similarity("n acht n", "n8n"), 1)
        XCTAssertEqual(similarity("N eight N", "n8n"), 1)
        XCTAssertEqual(similarity("Jams", "Jamf"), 0, "too short to guess")
        XCTAssertEqual(similarity("Projekt7", "Projekt8"), 0, "digits are never fuzzy")
        XCTAssertEqual(similarity("Magnus", "Magnussen"), 0, "only the start of the term")
        XCTAssertEqual(similarity("Magnussens", "Magnussen"), 0, "the term plus an ending")
        XCTAssertEqual(similarity("Hopper", "Copper"), 0, "another first sound")
        XCTAssertEqual(similarity("in Hubspott", "HubSpot"), 0, "another first letter")
        XCTAssertGreaterThan(similarity("Claud", "Claude"), threshold, "one missing letter is fine")
    }

    func testThresholdLeavesMarginOnBothSides() {
        let misheard = [("Clawd", "Claude"), ("Kopper", "Copper"), ("Magnusen", "Magnussen"), ("Müler", "Müller"), ("Hab Spot", "HubSpot")]
        for (heard, term) in misheard {
            XCTAssertGreaterThanOrEqual(TranscriptPostProcessor.termSimilarity(heard, term), threshold + 0.05, "\(heard) -> \(term)")
        }
        let otherWords = [("glaube", "Claude"), ("Klause", "Claude"), ("Klo da", "Claude"), ("Kopie", "Copper"), ("Koffer", "Copper")]
        for (heard, term) in otherWords {
            XCTAssertLessThanOrEqual(TranscriptPostProcessor.termSimilarity(heard, term), threshold - 0.05, "\(heard) -> \(term)")
        }
    }
}
