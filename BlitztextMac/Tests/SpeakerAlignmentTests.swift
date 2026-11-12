import XCTest

final class SpeakerAlignmentTests: XCTestCase {
    func testJoinsTokensIntoWords() {
        let tokens: [(text: String, start: TimeInterval, end: TimeInterval)] = [
            ("\u{2581}Guten", 0.0, 0.3), ("\u{2581}Mor", 0.3, 0.5), ("gen", 0.5, 0.7), (" zusammen", 0.8, 1.2),
        ]
        XCTAssertEqual(TimedWord.words(from: tokens), [
            TimedWord(text: "Guten", start: 0.0, end: 0.3),
            TimedWord(text: "Morgen", start: 0.3, end: 0.7),
            TimedWord(text: "zusammen", start: 0.8, end: 1.2),
        ])
    }

    /// Parakeet sends the word marker before a number as a token of its own (public issue #70).
    func testAMarkerOfItsOwnBeginsAWord() {
        let tokens: [(text: String, start: TimeInterval, end: TimeInterval)] = [
            ("\u{2581}nach", 0.0, 0.3), ("\u{2581}", 0.3, 0.3), ("10", 0.4, 0.6), ("%", 0.6, 0.7),
            (" um", 1.0, 1.2), (" ", 1.2, 1.2), ("1", 1.3, 1.4), ("0", 1.4, 1.5), ("", 1.5, 1.5), ("\u{2581}Uhr", 1.6, 1.9),
        ]
        XCTAssertEqual(TimedWord.words(from: tokens), [
            TimedWord(text: "nach", start: 0.0, end: 0.3),
            TimedWord(text: "10%", start: 0.4, end: 0.7),
            TimedWord(text: "um", start: 1.0, end: 1.2),
            TimedWord(text: "10", start: 1.3, end: 1.5),
            TimedWord(text: "Uhr", start: 1.6, end: 1.9),
        ])
    }

    func testAssignsWordsToTheTurnTheyFallIn() {
        let words = [
            TimedWord(text: "Hallo", start: 0.0, end: 0.4),
            TimedWord(text: "zusammen.", start: 0.5, end: 0.9),
            TimedWord(text: "Hi!", start: 2.0, end: 2.3),
            TimedWord(text: "Weiter.", start: 3.1, end: 3.5),
        ]
        let turns = [
            SpeakerTurn(speaker: 1, start: 0.0, end: 1.0),
            SpeakerTurn(speaker: 2, start: 1.8, end: 2.6),
            SpeakerTurn(speaker: 1, start: 3.0, end: 4.0),
        ]
        XCTAssertEqual(SpeakerAlignment.paragraphs(words: words, turns: turns), [
            .init(speaker: 1, start: 0.0, text: "Hallo zusammen."),
            .init(speaker: 2, start: 2.0, text: "Hi!"),
            .init(speaker: 1, start: 3.1, text: "Weiter."),
        ])
    }

    func testSplitsWhereSomeoneOnTheOtherTrackTalks() {
        // A one-on-one call: the system track holds one person, the microphone answers in between.
        let words = [
            TimedWord(text: "Kannst", start: 0.0, end: 0.3),
            TimedWord(text: "du?", start: 0.4, end: 0.7),
            TimedWord(text: "Danke.", start: 3.0, end: 3.4),
        ]
        let turns = [SpeakerTurn(speaker: 1, start: 0.0, end: 4.0)]
        XCTAssertEqual(SpeakerAlignment.paragraphs(words: words, turns: turns, breaks: [1.2]), [
            .init(speaker: 1, start: 0.0, text: "Kannst du?"),
            .init(speaker: 1, start: 3.0, text: "Danke."),
        ])
        XCTAssertEqual(SpeakerAlignment.paragraphs(words: words, turns: turns).count, 1)
    }

    func testWordBetweenTurnsGoesToTheClosestOne() {
        let words = [TimedWord(text: "Ja", start: 1.2, end: 1.3)]
        let turns = [SpeakerTurn(speaker: 1, start: 0, end: 1.0), SpeakerTurn(speaker: 2, start: 1.5, end: 2.0)]
        XCTAssertEqual(SpeakerAlignment.paragraphs(words: words, turns: turns).first?.speaker, 1)
    }

    func testWithoutTurnsLongPausesStartNewParagraphs() {
        let words = [
            TimedWord(text: "Erster", start: 0.0, end: 0.4),
            TimedWord(text: "Satz.", start: 0.5, end: 0.9),
            TimedWord(text: "Zweiter.", start: 3.0, end: 3.4),
        ]
        let paragraphs = SpeakerAlignment.paragraphs(words: words, turns: [])
        XCTAssertEqual(paragraphs.map(\.text), ["Erster Satz.", "Zweiter."])
        XCTAssertEqual(Set(paragraphs.map(\.speaker)), [1])
    }
}
