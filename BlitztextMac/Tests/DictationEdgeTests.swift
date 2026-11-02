import AVFoundation
import XCTest

final class HallucinationFilterTests: XCTestCase {
    func testCreditsAreAlwaysInvented() {
        XCTAssertTrue(HallucinationFilter.isCredit("Untertitel im Auftrag des ZDF, 2021"))
        XCTAssertTrue(HallucinationFilter.isCredit("Untertitel der Amara.org-Community"))
        XCTAssertTrue(HallucinationFilter.isCredit("Thanks for watching!"))
        XCTAssertFalse(HallucinationFilter.isCredit("Vielen Dank."))
        XCTAssertFalse(HallucinationFilter.isCredit("1234"))
    }

    /// Review of #68: a cough or click of 0.15 to 0.3 s passes the speech check, and Whisper
    /// wrote "Thank you." on it again. Said with real speech, the phrase stays.
    func testDoubtfulPhraseOnlyCountsWithHardlyAnySpeech() {
        XCTAssertTrue(HallucinationFilter.isInvented("Thank you.", longestVoicedRun: 0.2))
        XCTAssertTrue(HallucinationFilter.isInvented("Vielen Dank.", longestVoicedRun: 0.25))
        XCTAssertFalse(HallucinationFilter.isInvented("Vielen Dank.", longestVoicedRun: 0.9))
        XCTAssertFalse(HallucinationFilter.isInvented("Danke, bis morgen", longestVoicedRun: 0.2))
        XCTAssertTrue(HallucinationFilter.isInvented("Untertitel im Auftrag des ZDF, 2021", longestVoicedRun: 5))
        XCTAssertFalse(HallucinationFilter.isInvented("", longestVoicedRun: 0))
    }

    func testMeasuresVoicedAudio() {
        let silence = [Float](repeating: 0, count: 16_000)
        let roomNoise = (0..<16_000).map { _ in Float.random(in: -0.003...0.003) }
        let speech = (0..<16_000).map { Float(sin(Double($0) / 8)) * 0.2 }
        XCTAssertEqual(HallucinationFilter.longestVoicedRun(silence), 0)
        XCTAssertEqual(HallucinationFilter.longestVoicedRun(roomNoise), 0)
        XCTAssertGreaterThan(HallucinationFilter.longestVoicedRun(speech), 0.9)
        XCTAssertTrue(HallucinationFilter.hasNoSpeech(longestVoicedRun: HallucinationFilter.longestVoicedRun(roomNoise)))
    }

    func testShortAnswerIsOneRunAndClicksAreNot() {
        // "Ja." said quickly: 0.2 s of speech, one continuous run.
        let speech = Self.tone(seconds: 0.2, total: 1)
        XCTAssertEqual(HallucinationFilter.longestVoicedRun(speech), 0.21, accuracy: 0.031)
        XCTAssertFalse(HallucinationFilter.hasNoSpeech(longestVoicedRun: HallucinationFilter.longestVoicedRun(speech)))

        // Three keyboard clicks: loud, but only one or two frames each, far below a word.
        var clicks = [Float](repeating: 0, count: 16_000)
        for click in [2_000, 6_000, 10_000] {
            for index in click..<(click + 160) { clicks[index] = 0.6 }
        }
        XCTAssertLessThan(HallucinationFilter.longestVoicedRun(clicks), 0.12)
        XCTAssertTrue(HallucinationFilter.hasNoSpeech(longestVoicedRun: HallucinationFilter.longestVoicedRun(clicks)))
    }

    func testPiecesOfAnyLengthMeasureTheSame() {
        var samples = [Float](repeating: 0, count: 8_000) + Self.tone(seconds: 0.4, total: 0.4)
        samples += [Float](repeating: 0, count: 4_800) + Self.tone(seconds: 0.25, total: 1)
        var meter = HallucinationFilter.VoicedRunMeter(sampleRate: 16_000)
        var start = 0
        while start < samples.count {
            let end = min(start + 1_000, samples.count)
            meter.add(samples[start..<end])
            start = end
        }
        XCTAssertEqual(meter.longestRun, HallucinationFilter.longestVoicedRun(samples))
        XCTAssertEqual(meter.longestRun, 0.42, accuracy: 0.031)
    }

    func testReadsTheRunFromAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let silent = folder.appendingPathComponent("silent.wav")
        try Self.writeWAV((0..<32_000).map { _ in Float.random(in: -0.003...0.003) }, to: silent)
        XCTAssertEqual(try XCTUnwrap(HallucinationFilter.longestVoicedRun(in: silent)), 0)

        let spoken = folder.appendingPathComponent("spoken.wav")
        try Self.writeWAV([Float](repeating: 0, count: 16_000) + Self.tone(seconds: 0.3, total: 2), to: spoken)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(HallucinationFilter.longestVoicedRun(in: spoken)), 0.15)

        // Unreadable: unknown, so nothing may be dropped for lack of speech.
        XCTAssertNil(HallucinationFilter.longestVoicedRun(in: folder.appendingPathComponent("missing.wav")))
    }

    private static func tone(seconds: Double, total: Double) -> [Float] {
        (0..<Int(total * 16_000)).map { index -> Float in
            let t = Double(index) / 16_000
            return t < seconds ? Float(sin(t * 2 * .pi * 180)) * 0.08 : 0
        }
    }

    private static func writeWAV(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
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
