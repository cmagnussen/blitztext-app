import XCTest

final class SpokenEmailAddressTests: XCTestCase {
    func testSpokenAtBeforeWrittenDomain() {
        XCTAssertEqual(SpokenEmailAddress.format("Das ist ein Test at outlook.com"), "Das ist ein test@outlook.com")
    }

    func testSpokenDots() {
        XCTAssertEqual(
            SpokenEmailAddress.format("Schreib an max punkt meier at firma punkt de bitte"),
            "Schreib an max.meier@firma.de bitte"
        )
        XCTAssertEqual(SpokenEmailAddress.format("info ät blackboat dot com"), "info@blackboat.com")
    }

    func testWrittenAtSignWithSpaces() {
        XCTAssertEqual(SpokenEmailAddress.format("an paul @ blackboat.com"), "an paul@blackboat.com")
    }

    func testKeepsSentenceEndOutsideTheAddress() {
        XCTAssertEqual(SpokenEmailAddress.format("Danke. test at outlook.com."), "Danke. test@outlook.com.")
    }

    func testRecognizerSpaceAfterTheDot() {
        XCTAssertEqual(SpokenEmailAddress.format("test at outlook. com"), "test@outlook.com")
    }

    func testLeavesOrdinaryAtAlone() {
        let sentences = [
            "Wir treffen uns at home und dann geht's los.",
            "Look at this, it is great.",
            "Die Domain heißt outlook punkt com.",
        ]
        for sentence in sentences {
            XCTAssertEqual(SpokenEmailAddress.format(sentence), sentence)
        }
    }

    func testSentenceEndIsNoDot() {
        let sentences = [
            "Look at this. It is great.",
            "Look at me. No way, I said.",
            "Er war at home. De facto blieb er da.",
        ]
        for sentence in sentences {
            XCTAssertEqual(SpokenEmailAddress.format(sentence), sentence)
        }
        // At the very end a capital top-level domain still counts.
        XCTAssertEqual(SpokenEmailAddress.format("Test at outlook. Com."), "test@outlook.com.")
    }

    func testEnglishAtBeforeAWebsite() {
        let sentences = [
            "Find us at blackboat.com",
            "It is available at apple.com.",
            "More info at blackboat.com",
            "You can reach me at paul at blackboat dot com",
        ]
        for sentence in sentences {
            XCTAssertEqual(SpokenEmailAddress.format(sentence), sentence)
        }
        // A written @ is an address in every language.
        XCTAssertEqual(SpokenEmailAddress.format("Write to paul @ blackboat.com"), "Write to paul@blackboat.com")
    }

    func testPunktAsNoun() {
        XCTAssertEqual(
            SpokenEmailAddress.format("Wichtiger Punkt info at firma punkt de"),
            "Wichtiger Punkt info@firma.de"
        )
        XCTAssertEqual(
            SpokenEmailAddress.format("Der letzte Punkt info at firma punkt de"),
            "Der letzte Punkt info@firma.de"
        )
        XCTAssertEqual(
            SpokenEmailAddress.format("Paul Punkt Stegmann at Blackboat Punkt com"),
            "paul.stegmann@blackboat.com"
        )
    }

    func testOnlyAnAddress() {
        XCTAssertEqual(SpokenEmailAddress.format("Test at outlook.com"), "test@outlook.com")
        XCTAssertEqual(SpokenEmailAddress.format("Paul at blackboat.com"), "paul@blackboat.com")
    }

    func testTwoAddresses() {
        XCTAssertEqual(
            SpokenEmailAddress.format("a at b punkt de und c at d punkt com"),
            "a@b.de und c@d.com"
        )
    }
}
