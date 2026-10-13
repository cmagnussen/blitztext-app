import Foundation
import NaturalLanguage

/// Formats transcript whitespace without rewriting words or punctuation: long dictation
/// gets a blank line at a sentence end after 45 words or four substantial sentences.
///
/// Contributed by dan-rot to Blitztext (cmagnussen/blitztext-app PR #21, MIT).
enum TranscriptParagraphService {
    private static let paragraphSeparator = try! NSRegularExpression(
        pattern: #"\r?\n[\t ]*\r?\n(?:[\t ]*\r?\n)*"#
    )

    static func format(_ text: String, language: String = "") -> String {
        guard !text.isEmpty else { return text }
        // Keep existing paragraph separators exactly, and restart counting after each one.
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = ""
        var start = text.startIndex
        for match in paragraphSeparator.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            result += formatParagraph(String(text[start..<range.lowerBound]), language: language)
            result += text[range]
            start = range.upperBound
        }
        result += formatParagraph(String(text[start...]), language: language)
        return result
    }

    private static func formatParagraph(_ text: String, language: String) -> String {
        let sentences = NLTokenizer(unit: .sentence)
        let words = NLTokenizer(unit: .word)
        let languageCode = language.lowercased().split(separator: "-").first.map(String.init) ?? ""
        if !languageCode.isEmpty {
            let hint = NLLanguage(rawValue: languageCode)
            sentences.setLanguage(hint)
            words.setLanguage(hint)
        }
        sentences.string = text
        words.string = text
        var ranges: [Range<String.Index>] = []
        sentences.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        guard ranges.count > 1 else { return text }

        var result = ""
        var copyStart = text.startIndex
        var wordCount = 0
        var substantialSentences = 0
        for index in ranges.indices.dropLast() {
            let range = ranges[index]
            var sentenceWords = 0
            words.enumerateTokens(in: range) { token, _ in
                if text[token].unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                    sentenceWords += 1
                }
                return true
            }
            wordCount += sentenceWords
            if sentenceWords >= 4 { substantialSentences += 1 }
            guard wordCount >= 45 || substantialSentences >= 4 else { continue }

            var end = range.upperBound
            while end > range.lowerBound && text[text.index(before: end)].isWhitespace {
                end = text.index(before: end)
            }
            // A tokenizer boundary at a newline alone must not split an unfinished sentence.
            let sentence = text[range.lowerBound..<end]
            let ending = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„«»‹›‘’)]}"))
            guard let last = ending.last, ".!?…。！？".contains(last) else { continue }

            var next = ranges[index + 1].lowerBound
            while next < text.endIndex && text[next].isWhitespace {
                next = text.index(after: next)
            }
            guard next >= end, text[end..<next].allSatisfy(\.isWhitespace) else { continue }
            result += text[copyStart..<end]
            result += "\n\n"
            copyStart = next
            wordCount = 0
            substantialSentences = 0
        }
        result += text[copyStart...]
        return result
    }
}
