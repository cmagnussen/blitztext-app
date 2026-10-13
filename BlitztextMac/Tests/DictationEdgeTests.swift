import XCTest

final class HallucinationFilterTests: XCTestCase {
    func testCreditsAreAlwaysInvented() {
        XCTAssertTrue(HallucinationFilter.isInvented("Untertitel im Auftrag des ZDF, 2021", voicedSeconds: 5))
        XCTAssertTrue(HallucinationFilter.isInvented("Untertitel der Amara.org-Community", voicedSeconds: 5))
        XCTAssertTrue(HallucinationFilter.isInvented("Thanks for watching!", voicedSeconds: 5))
    }

    func testPoliteWordsOnlyCountOnSilence() {
        XCTAssertTrue(HallucinationFilter.isInvented("Thank you.", voicedSeconds: 0))
        XCTAssertTrue(HallucinationFilter.isInvented("Vielen Dank.", voicedSeconds: 0.1))
        XCTAssertFalse(HallucinationFilter.isInvented("Vielen Dank.", voicedSeconds: 1.2))
        XCTAssertFalse(HallucinationFilter.isInvented("Vielen Dank für die Zahlen.", voicedSeconds: 0))
        XCTAssertFalse(HallucinationFilter.isInvented("1234", voicedSeconds: 0))
    }

    func testMeasuresVoicedAudio() {
        let silence = [Float](repeating: 0, count: 16_000)
        let roomNoise = (0..<16_000).map { _ in Float.random(in: -0.003...0.003) }
        let speech = (0..<16_000).map { Float(sin(Double($0) / 8)) * 0.2 }
        XCTAssertEqual(HallucinationFilter.voicedSeconds(silence), 0)
        XCTAssertEqual(HallucinationFilter.voicedSeconds(roomNoise), 0)
        XCTAssertGreaterThan(HallucinationFilter.voicedSeconds(speech), 0.9)
    }

    func testRemovesTrailingCredits() {
        XCTAssertEqual(
            HallucinationFilter.removingTrailingCredits("Wir sehen uns morgen. Untertitel im Auftrag des ZDF, 2021."),
            "Wir sehen uns morgen."
        )
        XCTAssertEqual(
            HallucinationFilter.removingTrailingCredits("Bis morgen! Untertitel der Amara.org-Community"),
            "Bis morgen!"
        )
        XCTAssertEqual(HallucinationFilter.removingTrailingCredits("Danke fürs Zuschauen!"), "")
        XCTAssertEqual(
            HallucinationFilter.removingTrailingCredits("Die Untertitel im Auftrag des ZDF sind gut."),
            "Die Untertitel im Auftrag des ZDF sind gut."
        )
    }
}

final class InsertionFitterTests: XCTestCase {
    func testAddsSpaceBetweenWords() {
        XCTAssertEqual(InsertionFitter.fit("Und dann los.", before: "Wir starten", after: ""), " und dann los.")
        XCTAssertEqual(InsertionFitter.fit("Weiter geht's.", before: "Fertig.", after: ""), " Weiter geht's.")
        XCTAssertEqual(InsertionFitter.fit("Hallo", before: "Text ", after: ""), "Hallo")
    }

    func testCapitalizesAtSentenceStart() {
        XCTAssertEqual(InsertionFitter.fit("danke dir.", before: "", after: ""), "Danke dir.")
        XCTAssertEqual(InsertionFitter.fit("danke dir.", before: "Hallo Anna,\n", after: ""), "Danke dir.")
        XCTAssertEqual(InsertionFitter.fit("danke dir.", before: "Gut so! ", after: ""), "Danke dir.")
    }

    func testKeepsNounsAndPolitePronounsMidSentence() {
        XCTAssertEqual(InsertionFitter.fit("Montag passt.", before: "Ich glaube,", after: ""), " Montag passt.")
        XCTAssertEqual(InsertionFitter.fit("Sie kommen.", before: "Ich hoffe,", after: ""), " Sie kommen.")
        XCTAssertEqual(InsertionFitter.fit("I agree.", before: "Honestly,", after: ""), " I agree.")
        XCTAssertEqual(InsertionFitter.fit("API läuft.", before: "Die", after: ""), " API läuft.")
    }

    func testDropsPeriodWhereTheSentenceGoesOn() {
        XCTAssertEqual(InsertionFitter.fit("Das Angebot.", before: "Ich schicke dir ", after: " morgen früh."), "das Angebot")
        XCTAssertEqual(InsertionFitter.fit("Ich komme.", before: "", after: "."), "Ich komme")
        XCTAssertEqual(InsertionFitter.fit("Siehe Liste usw.", before: "", after: " weiter"), "Siehe Liste usw.")
    }

    func testAddsSpaceBeforeFollowingWord() {
        XCTAssertEqual(InsertionFitter.fit("Hallo", before: "", after: "Welt"), "Hallo ")
        XCTAssertEqual(InsertionFitter.fit("Hallo", before: "", after: " Welt"), "Hallo")
    }

    func testRespectsBracketsQuotesAndDashes() {
        XCTAssertEqual(InsertionFitter.fit("Siehe oben", before: "(", after: ")"), "Siehe oben")
        XCTAssertEqual(InsertionFitter.fit("Zitat", before: "Er sagte „", after: ""), "Zitat")
        XCTAssertEqual(InsertionFitter.fit("Zitat", before: "Er sagte \"", after: ""), "Zitat")
        XCTAssertEqual(InsertionFitter.fit("Weiter", before: "\"Ende\"", after: ""), " Weiter")
        XCTAssertEqual(InsertionFitter.fit("Und weiter", before: "gut -", after: ""), " und weiter")
        XCTAssertEqual(InsertionFitter.fit("Mail", before: "E-", after: ""), "Mail")
    }
}

final class WebsiteHostTests: XCTestCase {
    func testNormalizesInput() {
        XCTAssertEqual(WebsiteHost.normalized("https://www.Mail.google.com/mail/u/0"), "mail.google.com")
        XCTAssertEqual(WebsiteHost.normalized(" notion.so "), "notion.so")
        XCTAssertNil(WebsiteHost.normalized("gmail"))
        XCTAssertNil(WebsiteHost.normalized("mail google com"))
    }

    func testMatchesSubdomains() {
        XCTAssertTrue(WebsiteHost.matches("mail.google.com", rule: "google.com"))
        XCTAssertTrue(WebsiteHost.matches("mail.google.com", rule: "mail.google.com"))
        XCTAssertFalse(WebsiteHost.matches("notgoogle.com", rule: "google.com"))
    }
}
