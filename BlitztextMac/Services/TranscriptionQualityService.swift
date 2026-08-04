import Foundation

enum TranscriptionQualityService {
    static let minimumRecordingDuration: TimeInterval = 0.3

    private static let trailingLocalArtifactPatterns = [
        // Whisper occasionally emits subtitle-style sound cues after otherwise valid speech.
        #"(?i)(?:^|\s+)[\[\(]\s*(?:(?:anhaltender|langer|lauter|leiser)\s+)?(?:beifall|applaus|musik(?:\s+(?:spielt|setzt\s+ein|verklingt))?|gelächter|lachen|stille|pause|hintergrundgeräusche?|unverständlich)\s*[\]\)]\s*[.!?…]*$"#,
        // Common Whisper outro hallucinations. These are removed only as a trailing phrase.
        #"(?i)(?:^|(?<=[.!?…]))\s*(?:(?:vielen\s+dank|danke)\s+(?:fürs|für\s+das)\s+(?:zuschauen|zusehen|zuhören)|bis\s+zum\s+nächsten\s+mal|auf\s+wiedersehen|tschüss(?:\s+zusammen)?|untertitel\s+(?:von|der)\s+(?:der\s+)?amara(?:\.org)?(?:-community|-gemeinschaft)?|(?:thank\s+you|thanks)\s+for\s+(?:watching|listening)|see\s+you\s+next\s+time|goodbye|bye[\s-]+bye)\s*[.!?…]*$"#
    ]

    private static let trailingLocalArtifactExpressions: [NSRegularExpression] =
        trailingLocalArtifactPatterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }

    static func shouldRejectRecording(duration: TimeInterval) -> Bool {
        duration < minimumRecordingDuration
    }

    static func cleanedTranscript(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanedLocalTranscript(_ text: String) -> String {
        var cleaned = cleanedTranscript(text)

        // Repeat so combinations such as "… Vielen Dank fürs Zuschauen. [Musik]"
        // are removed completely while the actual dictated text remains untouched.
        while !cleaned.isEmpty {
            var removedArtifact = false

            for expression in trailingLocalArtifactExpressions {
                let fullRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                guard expression.firstMatch(in: cleaned, range: fullRange) != nil else {
                    continue
                }

                cleaned = cleanedTranscript(
                    expression.stringByReplacingMatches(
                        in: cleaned,
                        range: fullRange,
                        withTemplate: ""
                    )
                )
                removedArtifact = true
                break
            }

            if !removedArtifact {
                break
            }
        }

        return cleaned
    }

    static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
        let cleaned = cleanedTranscript(text)
        guard !cleaned.isEmpty else { return true }

        let words = cleaned.split { $0.isWhitespace || $0.isNewline }
        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if letters == 0 {
            return true
        }

        if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
            return true
        }

        if recordingDuration < 0.8 && cleaned.count >= 56 {
            return true
        }

        return false
    }
}
