import Foundation

enum TranscriptionQualityService {
    static let minimumRecordingDuration: TimeInterval = 0.3

    static func shouldRejectRecording(duration: TimeInterval) -> Bool {
        duration < minimumRecordingDuration
    }

    static func cleanedTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeSentenceSpacing(trimmed)
    }

    /// Fügt ein fehlendes Leerzeichen nach Satzzeichen ein, wenn direkt ein Grossbuchstabe
    /// folgt (z. B. "Satz eins.Satz zwei" -> "Satz eins. Satz zwei"). Lokale Whisper-Modelle
    /// lassen dieses Leerzeichen beim Zusammenfügen von Segmenten manchmal weg.
    /// Zahlen ("3.14") und Domains ("google.com") bleiben unberührt, da nur vor einem
    /// Grossbuchstaben (inkl. Ä/Ö/Ü) ein Leerzeichen ergänzt wird.
    static func normalizeSentenceSpacing(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([.!?,;:])([A-ZÄÖÜ])") else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1 $2")
    }

    /// Wendet die gelernten Korrektur-Regeln an: ersetzt jedes `from` (ganzes Wort,
    /// Gross-/Kleinschreibung egal) durch das exakte `to`. Reihenfolge wie in der Liste.
    static func applyCorrections(_ text: String, _ corrections: [TextCorrection]) -> String {
        var result = text
        for correction in corrections {
            let from = correction.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }

            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.to)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
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
