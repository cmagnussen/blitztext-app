import Foundation

/// Local cleanup applied to raw transcripts before they are pasted or sent to the LLM.
///
/// Adapted from MIT-licensed code (see THIRD_PARTY_NOTICES.md):
/// - fuzzy correction of custom terms (Levenshtein + Soundex + n-grams, e.g. "Charge B" -> "ChargeBee")
/// - removal of filler words ("äh", "ähm", "uh", ...)
/// - collapsing of stutters ("ich ich ich ich" -> "ich")
///
/// Blitztext additions:
/// - single words that are valid dictionary words (German or English) are only replaced
///   on an exact match, so "Cloud" never turns into "Claude"
/// - fixed replacements ("n acht n" -> "n8n") for terms that do not sound like their spelling
/// - digits in custom terms also match their spoken form ("n8n" matches "n acht n")

/// A fixed rule: whenever `spoken` appears as whole words, write `written` instead.
struct TermReplacement: Codable, Hashable, Identifiable {
    var spoken: String
    var written: String

    var id: String { spoken.lowercased() }
}

struct TranscriptPostProcessor {
    var customTerms: [String] = []
    var replacements: [TermReplacement] = []
    var correctCustomTerms = true
    var removeFillerWords = true
    var language = "de"
    /// Maximum similarity score for a fuzzy match (0 = exact only). Handy's default.
    var correctionThreshold = 0.18
    /// Returns true when a single word is a correctly spelled dictionary word.
    var isDictionaryWord: (String) -> Bool = { _ in false }

    func process(_ text: String) -> String {
        var result = text
        if removeFillerWords {
            result = Self.removeFillerWords(from: result, language: language)
        }
        // Fixed rules first, so the fuzzy matcher sees the intended spelling.
        result = Self.applyReplacements(replacements, to: result)
        if correctCustomTerms {
            result = Self.applyCustomTerms(
                to: result,
                customTerms: customTerms,
                threshold: correctionThreshold,
                isDictionaryWord: isDictionaryWord
            )
        }
        return Self.normalize(result, capitalizeFirstLetterLike: text)
    }

    // MARK: - Replacements

    /// Case-insensitive, whole words only; spaces and hyphens between the spoken words
    /// may vary ("n acht n", "N-acht-N"). Longer rules win over shorter overlapping ones.
    static func applyReplacements(_ replacements: [TermReplacement], to text: String) -> String {
        let rules = replacements
            .map { (spoken: $0.spoken.trimmingCharacters(in: .whitespacesAndNewlines), written: $0.written) }
            .filter { !$0.spoken.isEmpty }
            .sorted { $0.spoken.count > $1.spoken.count }
        guard !rules.isEmpty else { return text }

        var result = text
        for rule in rules {
            let words = rule.spoken
                .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s\\-]+") + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.written)
            )
        }
        return result
    }

    // MARK: - Custom Terms

    private struct TermKey {
        let termIndex: Int
        let key: String
    }

    static func applyCustomTerms(
        to text: String,
        customTerms: [String],
        threshold: Double,
        isDictionaryWord: (String) -> Bool = { _ in false }
    ) -> String {
        let terms = customTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return text }

        let termKeys = terms.enumerated().flatMap { index, term in
            termMatchKeys(for: term, termIndex: index)
        }
        guard !termKeys.isEmpty else { return text }

        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [String] = []
        var index = 0
        var didReplace = false

        while index < words.count {
            var best: (length: Int, term: String, score: Double)?

            // Consider n-grams up to three words and keep the closest match.
            for length in stride(from: 3, through: 1, by: -1) {
                guard index + length <= words.count else { continue }
                let ngramWords = Array(words[index..<(index + length)])

                // Do not consume across a punctuation boundary ("Charge B, che").
                if ngramWords.dropLast().contains(where: { !extractPunctuation($0).suffix.isEmpty }) {
                    continue
                }

                let candidate = ngramWords.map(matchKey).joined()
                guard let match = bestMatch(for: candidate, terms: terms, termKeys: termKeys, threshold: threshold) else {
                    continue
                }

                // Real words only get replaced when they match a term exactly.
                if length == 1, match.score > 0 {
                    let core = extractPunctuation(ngramWords[0]).core
                    if isDictionaryWord(core) {
                        continue
                    }
                }

                if best == nil || match.score < best!.score {
                    best = (length, match.term, match.score)
                }
            }

            if let best {
                let ngramWords = Array(words[index..<(index + best.length)])
                let prefix = extractPunctuation(ngramWords[0]).prefix
                let suffix = extractPunctuation(ngramWords[best.length - 1]).suffix
                // Custom terms are spelled exactly as configured ("iPhone", "n8n").
                result.append(prefix + best.term + suffix)
                didReplace = didReplace || ngramWords.joined(separator: " ") != prefix + best.term + suffix
                index += best.length
            } else {
                result.append(words[index])
                index += 1
            }
        }

        return didReplace ? result.joined(separator: " ") : text
    }

    private static func termMatchKeys(for term: String, termIndex: Int) -> [TermKey] {
        var keys: [TermKey] = []
        let primary = matchKey(term)
        // The fuzzy matcher is limited to ASCII terms (Soundex is ASCII-only).
        if isSupportedFuzzyKey(primary) {
            keys.append(TermKey(termIndex: termIndex, key: primary))
        }
        if term.contains("&") {
            let expanded = matchKey(term.replacingOccurrences(of: "&", with: " and "))
            if isSupportedFuzzyKey(expanded), expanded != primary {
                keys.append(TermKey(termIndex: termIndex, key: expanded))
            }
        }
        // Speech models often write digits as words: "n8n" is transcribed "n acht n".
        if primary.contains(where: \.isNumber) {
            for names in [germanDigitNames, englishDigitNames] {
                let spoken = String(primary.flatMap { character -> [Character] in
                    guard let digit = character.wholeNumberValue else { return [character] }
                    return Array(names[digit])
                })
                if isSupportedFuzzyKey(spoken), spoken != primary,
                   !keys.contains(where: { $0.key == spoken }) {
                    keys.append(TermKey(termIndex: termIndex, key: spoken))
                }
            }
        }
        return keys
    }

    private static func bestMatch(
        for candidate: String,
        terms: [String],
        termKeys: [TermKey],
        threshold: Double
    ) -> (term: String, score: Double)? {
        guard isSupportedFuzzyKey(candidate), candidate.count <= 50 else { return nil }

        var bestTerm: String?
        var bestScore = Double.greatestFiniteMagnitude
        let candidateLength = candidate.count

        for termKey in termKeys {
            let termLength = termKey.key.count
            let lengthDifference = Double(abs(candidateLength - termLength))
            let maxLength = Double(max(candidateLength, termLength))
            // Max 25 % length difference, at least 2 characters.
            guard lengthDifference <= max(maxLength * 0.25, 2) else { continue }

            let distance = levenshtein(candidate, termKey.key)
            let distanceScore = maxLength > 0 ? Double(distance) / maxLength : 1
            let phoneticMatch = supportsSoundex(candidate)
                && supportsSoundex(termKey.key)
                && soundex(candidate) == soundex(termKey.key)
            let score = phoneticMatch ? distanceScore * 0.3 : distanceScore

            if score < threshold, score < bestScore {
                bestTerm = terms[termKey.termIndex]
                bestScore = score
            }
        }

        return bestTerm.map { ($0, bestScore) }
    }

    private static let germanDigitNames = ["null", "eins", "zwei", "drei", "vier", "fuenf", "sechs", "sieben", "acht", "neun"]
    private static let englishDigitNames = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    static func matchKey(_ word: String) -> String {
        String(word.filter { $0.isLetter || $0.isNumber }).lowercased()
    }

    private static func isSupportedFuzzyKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    private static func supportsSoundex(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    static func extractPunctuation(_ word: String) -> (prefix: String, core: String, suffix: String) {
        guard let start = word.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let end = word.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            return (word, "", "")
        }
        return (
            String(word[..<start]),
            String(word[start...end]),
            String(word[word.index(after: end)...])
        )
    }

    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// American Soundex: first letter plus three digits.
    static func soundex(_ word: String) -> String {
        let letters = Array(word.uppercased().filter { $0.isASCII && $0.isLetter })
        guard let first = letters.first else { return "" }

        func code(_ character: Character) -> Character? {
            switch character {
            case "B", "F", "P", "V": return "1"
            case "C", "G", "J", "K", "Q", "S", "X", "Z": return "2"
            case "D", "T": return "3"
            case "L": return "4"
            case "M", "N": return "5"
            case "R": return "6"
            default: return nil
            }
        }

        var result = String(first)
        var lastCode = code(first)
        for character in letters.dropFirst() {
            let current = code(character)
            if let current, current != lastCode {
                result.append(current)
                if result.count == 4 { break }
            }
            // H and W do not separate letters with the same code; vowels do.
            if character != "H", character != "W" {
                lastCode = current
            }
        }
        return result.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    // MARK: - Filler Words

    /// Tokens that are not real words in any supported language.
    static let universalFillerWords = ["uh", "uhm", "umm", "uhh", "uhhh", "ehh", "ehm", "ahm", "hmm", "hm", "mmm"]

    /// Tokens that are only safe to remove when the output language is known.
    static func languageFillerWords(for language: String) -> [String] {
        let base = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? language
        switch base.lowercased() {
        case "de": return ["äh", "ähm", "ähh", "öh", "öhm"]
        case "en": return ["um", "ah", "eh"]
        case "fr": return ["euh"]
        default: return []
        }
    }

    static func removeFillerWords(from text: String, language: String) -> String {
        let fillers = universalFillerWords + languageFillerWords(for: language)
        var result = text
        for filler in fillers {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: filler))(?![\\p{L}\\p{N}]),?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
    }

    // MARK: - Normalization

    /// Collapses 3+ repetitions of the same word into one ("ich ich ich" -> "ich").
    static func collapseStutters(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [String] = []
        var index = 0
        var didCollapse = false
        while index < words.count {
            let word = words[index]
            let lowered = word.lowercased()
            var count = 1
            if lowered.allSatisfy(\.isLetter) {
                while index + count < words.count, words[index + count].lowercased() == lowered {
                    count += 1
                }
            }
            result.append(word)
            if count >= 3 {
                didCollapse = true
                index += count
            } else {
                index += 1
            }
        }
        return didCollapse ? result.joined(separator: " ") : text
    }

    static func normalize(_ text: String, capitalizeFirstLetterLike original: String) -> String {
        var result = collapseStutters(text)
        // Remove orphaned punctuation left behind by filler removal (", , ok" -> ", ok").
        result = result.replacingOccurrences(of: "[ \\t]+([,.])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",{2,}", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "^[,. \\t]+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        let originalFirstLetter = original.first(where: \.isLetter)
        if let originalFirstLetter, originalFirstLetter.isUppercase,
           let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}
