import XCTest

final class EchoFilterTests: XCTestCase {
    /// Words from a sentence, one every 0.4 s from `start`.
    private func words(_ sentence: String, from start: TimeInterval) -> [TimedWord] {
        sentence.split(separator: " ").enumerated().map { index, word in
            let time = start + Double(index) * 0.4
            return TimedWord(text: String(word), start: time, end: time + 0.3)
        }
    }

    private func text(_ words: [TimedWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    func testRemovesWhatCameOutOfTheSpeakers() {
        let system = words("Das hier ist mein Live-Kanal und nicht mein Hauptkanal.", from: 10)
        // The microphone heard it 0.3 s later, between two sentences of its own.
        let microphone = words("Das ist jetzt ein Video.", from: 4)
            + words("Das hier ist mein Live-Kanal und nicht mein Hauptkanal.", from: 10.3)
            + words("Jetzt sage ich wieder was.", from: 16)
        XCTAssertEqual(
            text(EchoFilter.removeEcho(from: microphone, heard: system)),
            "Das ist jetzt ein Video. Jetzt sage ich wieder was."
        )
    }

    func testFindsTheShiftBetweenTheTracks() {
        let system = words("Wir sehen uns am Donnerstag im Büro und besprechen den Plan.", from: 5)
        let microphone = words("Wir sehen uns am Donnerstag im Büro und besprechen den Plan.", from: 6.4)
        XCTAssertTrue(EchoFilter.removeEcho(from: microphone, heard: system).isEmpty)
    }

    func testKeepsSingleWordsThatHappenToMatch() {
        let system = words("Ja genau so machen wir das.", from: 20)
        let microphone = words("Ja klar, ich kümmere mich drum heute.", from: 20.2)
        XCTAssertEqual(text(EchoFilter.removeEcho(from: microphone, heard: system)), "Ja klar, ich kümmere mich drum heute.")
    }

    func testSingleLettersDoNotBreakTheEcho() {
        let system = words("I have a rather, I don't know, a bit embarrassing problem.", from: 40)
        let microphone = words("I have a rather, I a a", from: 40.2)
        XCTAssertTrue(EchoFilter.removeEcho(from: microphone, heard: system).isEmpty)
    }

    func testDropsShortScrapsWhileOthersTalk() {
        // As in a real call without headphones: the microphone garbled "a little squad work
        // which" and heard the rest of the sentence cleanly.
        let system = words("And we have again planned a little squad work which comes to the topic of ownership.", from: 10)
        let microphone = words("soul I", from: 10.4)
            + words("a little spot work with", from: 12.1)
            + words("comes to the topic of ownership.", from: 14.1)
        XCTAssertTrue(EchoFilter.removeEcho(from: microphone, heard: system).isEmpty)
    }

    func testKeepsShortRepliesWhileOthersTalkWithHeadphones() {
        // No echo anywhere: the microphone only hears the person at this Mac.
        let system = words("Wer kann sich bis morgen um die Zahlen für den Bericht kümmern?", from: 10)
        let microphone = words("Mach ich.", from: 12) + words("Ja, übernehme ich.", from: 14)
        XCTAssertEqual(text(EchoFilter.removeEcho(from: microphone, heard: system)), "Mach ich. Ja, übernehme ich.")
    }

    func testKeepsShortRepliesWithAMatchingWord() {
        // "ich" happens to be in both tracks at the same moment; one word is no echo.
        let system = words("Das mache ich dann am besten selbst.", from: 10)
        let microphone = words("Danke, ich", from: 10.8)
        XCTAssertEqual(text(EchoFilter.removeEcho(from: microphone, heard: system)), "Danke, ich")
    }

    func testKeepsShortRepliesInAPause() {
        let system = words("Können wir die Zahlen bis Freitag haben?", from: 0)
        let microphone = words("Ja, genau.", from: 6)
        XCTAssertEqual(text(EchoFilter.removeEcho(from: microphone, heard: system)), "Ja, genau.")
    }

    func testKeepsOwnSentencesDuringCrosstalk() {
        let system = words("Dann gehen wir jetzt in die Räume und treffen uns um halb wieder.", from: 10)
        let microphone = words("Ich bereite für Donnerstag eine kleine Demo mit lokalen Modellen vor.", from: 11)
        XCTAssertEqual(
            text(EchoFilter.removeEcho(from: microphone, heard: system)),
            "Ich bereite für Donnerstag eine kleine Demo mit lokalen Modellen vor."
        )
    }

    func testRemovesGarbledWordsInsideTheEcho() {
        let system = words("Ihr habt vielleicht meinen Hauptkanal schon abonniert vielen Dank.", from: 30)
        var microphone = words("Ihr habt vielleicht meinen Hauptkanal schon abonniert vielen Dank.", from: 30.2)
        microphone[4] = TimedWord(text: "Hauptkranich", start: microphone[4].start, end: microphone[4].end)
        XCTAssertTrue(EchoFilter.removeEcho(from: microphone, heard: system).isEmpty)
    }

    func testKeepsEverythingWithoutEcho() {
        let system = words("Können wir die Zahlen bis Freitag haben?", from: 3)
        let microphone = words("Ja, das schaffe ich bis Donnerstag.", from: 7)
        XCTAssertEqual(EchoFilter.removeEcho(from: microphone, heard: system), microphone)
        XCTAssertEqual(EchoFilter.removeEcho(from: microphone, heard: []), microphone)
    }
}
