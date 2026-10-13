import Foundation

/// Drops text Whisper invents: subtitle credits from its training data ("Untertitel im
/// Auftrag des ZDF, 2021") and polite closings on silence ("Thank you.", "Vielen Dank.").
///
/// The idea of a phrase list comes from Amical (MIT, https://github.com/amicalhq/amical,
/// `pipeline/utils/segment-filter.ts`). Amical keys it to Whisper's no-speech
/// probability, which WhisperKit reports as 0 for these cases, so Blitztext checks how
/// much of the recording is loud enough to be speech instead.
enum HallucinationFilter {
    /// Credits and sign-offs that are never meant as dictation. Normalized, without years.
    static let credits: Set<String> = [
        "untertitel im auftrag des zdf",
        "untertitel im auftrag des zdf für funk",
        "untertitelung im auftrag des zdf",
        "untertitelung des zdf",
        "untertitel des zdf",
        "untertitel der amara org community",
        "untertitel von der amara org community",
        "untertitel von amara org",
        "untertitel von stephanie geiges",
        "copyright wdr",
        "copyright swr",
        "vielen dank fürs zuschauen",
        "vielen dank für s zuschauen",
        "danke fürs zuschauen",
        "danke für s zuschauen",
        "abonniert den kanal",
        "bitte abonnieren",
        "abonniere meinen kanal",
        "subtitles by the amara org community",
        "subtitles by amara org",
        "thanks for watching",
        "thank you for watching",
        "thank you so much for watching",
        "please subscribe",
        "like and subscribe",
        "please like and subscribe",
    ]

    /// Short phrases people do say, so they only count as invented on a silent recording.
    static let doubtfulPhrases: Set<String> = [
        "vielen dank", "danke", "danke schön", "dankeschön", "tschüss", "tschüs",
        "bis zum nächsten mal", "bis bald", "bis dann", "das war s", "ende",
        "thank you", "thanks", "thank you very much", "you", "bye", "bye bye",
        "okay", "ok", "ja", "hmm", "hm", "mhm",
        "musik", "music", "applaus", "applause", "lachen",
        "swr", "wdr", "zdf", "ard",
    ]

    /// Less speech than this and a doubtful phrase counts as invented.
    static let minimumVoicedSeconds = 0.3

    /// True when the whole transcript is a credit, or a doubtful phrase on a recording
    /// with hardly any speech.
    static func isInvented(_ text: String, voicedSeconds: Double) -> Bool {
        let key = phraseKey(text)
        guard !key.isEmpty else { return false }
        if credits.contains(key) { return true }
        return voicedSeconds < minimumVoicedSeconds && doubtfulPhrases.contains(key)
    }

    /// Seconds of audio loud enough to be speech: 30 ms frames above about -40 dBFS.
    static func voicedSeconds(_ samples: [Float], sampleRate: Double = 16_000) -> Double {
        let frameLength = max(1, Int(sampleRate * 0.03))
        var voicedFrames = 0
        var start = 0
        while start + frameLength <= samples.count {
            var sum: Float = 0
            for index in start..<(start + frameLength) {
                sum += samples[index] * samples[index]
            }
            if (sum / Float(frameLength)).squareRoot() > 0.01 {
                voicedFrames += 1
            }
            start += frameLength
        }
        return Double(voicedFrames * frameLength) / sampleRate
    }

    /// Removes credits at the end of a transcript ("... bis morgen. Untertitel im Auftrag
    /// des ZDF, 2021."). Works on any engine's text, so Parakeet output is covered too.
    static func removingTrailingCredits(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let cut = trailingCreditStart(in: result) {
            result = String(result[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Start of the last one to three sentences when together they are a credit.
    private static func trailingCreditStart(in text: String) -> String.Index? {
        guard !text.isEmpty else { return nil }
        let starts = sentenceStarts(in: text)
        for start in starts.suffix(3).reversed() {
            if credits.contains(phraseKey(String(text[start...]))) {
                return start
            }
        }
        return nil
    }

    /// Index 0 and every position after ".", "!", "?" or "…" plus whitespace, or after a
    /// line break. "Amara.org" stays one sentence.
    private static func sentenceStarts(in text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isNewline, next < text.endIndex {
                starts.append(next)
            } else if ".!?…".contains(character), next < text.endIndex, text[next].isWhitespace {
                starts.append(next)
            }
            index = next
        }
        return starts
    }

    /// Lowercased letters and digits, everything else becomes a single space.
    static func normalized(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                result.append(character)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// Like `normalized`, without numbers, so "ZDF, 2021" and "ZDF 2017" match "zdf".
    static func phraseKey(_ text: String) -> String {
        normalized(text)
            .split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }
}
