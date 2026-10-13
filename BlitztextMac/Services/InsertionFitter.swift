import Foundation

/// Fits a dictation into the text around the cursor: a space where words would touch, a
/// capital letter at a sentence start, a lowercase function word mid-sentence and no
/// period where the sentence goes on. Only the edges of the dictation change.
///
/// Idea from Amical (MIT, https://github.com/amicalhq/amical), which leaves this to the
/// language model. Here it is plain rules, so it also works for word-for-word dictation.
enum InsertionFitter {
    static func fit(_ text: String, before: String, after: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return text }

        if startsSentence(before) {
            result = uppercasingFirstLetter(result)
        } else if continuesSentence(before) {
            result = lowercasingFunctionWord(result)
        }

        if needsSpaceBefore(result, before: before) {
            result = " " + result
        }

        if let next = after.first {
            if result.hasSuffix("."), ".,;:!?".contains(next) {
                result.removeLast()
            } else if result.hasSuffix("."), sentenceContinues(after), endsWithWord(result) {
                result.removeLast()
            }
            if next.isLetter || next.isNumber || "„(".contains(next) {
                result += " "
            }
        }
        return result
    }

    // MARK: - Sentence position

    /// Text before the cursor without trailing spaces; line breaks stay.
    private static func trimmedBefore(_ before: String) -> Substring {
        var trimmed = Substring(before)
        while let last = trimmed.last, last == " " || last == "\t" || last == "\u{00A0}" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func startsSentence(_ before: String) -> Bool {
        guard let last = trimmedBefore(before).last else { return true }
        return last.isNewline || ".!?…".contains(last)
    }

    private static func continuesSentence(_ before: String) -> Bool {
        guard let last = trimmedBefore(before).last else { return false }
        return last.isLetter || last.isNumber || ",;-–".contains(last)
    }

    /// The text after the cursor goes on with a lowercase word on the same line.
    private static func sentenceContinues(_ after: String) -> Bool {
        guard let first = after.first(where: { $0 != " " && $0 != "\t" }) else { return false }
        return first.isLetter && first.isLowercase
    }

    /// The last word has at least four letters, so "usw." or "z. B." keep their period.
    private static func endsWithWord(_ text: String) -> Bool {
        let body = text.dropLast()
        let lastWord = body.reversed().prefix { $0.isLetter }
        return lastWord.count >= 4 && body.last?.isLetter == true
    }

    // MARK: - Spacing

    private static func needsSpaceBefore(_ text: String, before: String) -> Bool {
        guard let previous = before.last, !previous.isWhitespace, let first = text.first else { return false }
        if ",.;:!?)]}…".contains(first) { return false }
        if "([{„‚@#_".contains(previous) { return false }
        let beforePrevious = before.dropLast().last
        let previousStandsAlone = beforePrevious == nil || beforePrevious!.isWhitespace || "([{".contains(beforePrevious!)
        // "gut - und" is a dash and wants a space, "E-" or "und/" join the next word.
        if "-/–".contains(previous) {
            return previousStandsAlone
        }
        // A straight or curly quote opens when nothing or a space comes before it.
        if "\"'“‘«»".contains(previous) {
            return !previousStandsAlone
        }
        return true
    }

    // MARK: - Capitalization

    private static func uppercasingFirstLetter(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "Und dann" becomes "und dann" after "Ich gehe heim". Nouns keep their capital,
    /// and so do "Sie", "Ihr" and "I", whose meaning depends on it.
    private static func lowercasingFunctionWord(_ text: String) -> String {
        let word = text.prefix { $0.isLetter }
        guard let first = word.first, first.isUppercase,
              word.dropFirst().allSatisfy(\.isLowercase),
              functionWords.contains(word.lowercased()) else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }

    static let functionWords: Set<String> = [
        // German
        "aber", "als", "also", "am", "an", "auch", "auf", "aus", "außerdem", "bei", "bin", "bis", "bitte",
        "da", "dabei", "dafür", "damit", "danach", "dann", "darum", "das", "dass", "dein", "deine", "dem",
        "den", "denn", "der", "des", "deshalb", "die", "dies", "diese", "diesem", "diesen", "dieser", "dieses",
        "doch", "du", "durch", "eigentlich", "ein", "eine", "einem", "einen", "einer", "eines", "er", "es",
        "etwa", "falls", "für", "gegen", "gerade", "gern", "gerne", "heute", "hier", "ich", "im", "in", "ins",
        "ist", "ja", "jetzt", "kein", "keine", "man", "mein", "meine", "mit", "nach", "natürlich", "nicht",
        "noch", "nun", "nur", "ob", "oder", "ohne", "schon", "sehr", "sind", "so", "sonst", "sowie", "statt",
        "trotzdem", "um", "und", "uns", "unser", "unsere", "unter", "vielleicht", "vom", "von", "vor", "war",
        "was", "weil", "wenn", "wer", "wie", "wir", "wo", "zu", "zum", "zur", "zwar",
        // English
        "a", "about", "after", "also", "and", "are", "as", "at", "be", "because", "but", "by", "for", "from",
        "if", "is", "it", "its", "just", "maybe", "my", "not", "of", "on", "or", "our", "than", "that", "the",
        "then", "there", "these", "they", "this", "those", "to", "we", "what", "when", "where", "which",
        "while", "who", "with", "you", "your",
    ]
}
