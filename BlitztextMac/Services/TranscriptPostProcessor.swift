import Foundation

/// Local cleanup of a raw transcript before it is pasted or handed to a language model.
///
/// Order matters: hesitation sounds go first so they can never be read as part of a term,
/// then the user's fixed replacements, then dictated e-mail addresses are written as
/// addresses, then words that clearly mean one of the user's custom terms get the user's
/// spelling, and finally stutters and stray punctuation are tidied. Everything runs on the device in plain string code and only touches the words
/// it changes; spacing and line breaks elsewhere stay exactly as dictated.

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
    /// Minimum `termSimilarity` for a fuzzy term correction. On that scale the misheard
    /// "Clawd" scores 0.82 against "Claude", while real words a dictionary might not know
    /// stay below 0.67 ("glaube" and "Klause" against "Claude", "Kopie" 0.58 against
    /// "Copper"); 0.74 sits in the middle of that gap. Exact matches (same letters) always
    /// apply.
    var correctionThreshold = 0.74
    /// Returns true when a single word is a correctly spelled dictionary word.
    var isDictionaryWord: (String) -> Bool = { _ in false }

    func process(_ text: String) -> String {
        var result = text
        if removeFillerWords {
            result = Self.removeFillerWords(from: result, language: language)
        }
        // Fixed rules first, so the fuzzy matcher sees the intended spelling.
        result = Self.applyReplacements(replacements, to: result)
        // Addresses before the fuzzy matcher, which then leaves them alone: an address is
        // exact, a similar-sounding term would send the mail somewhere else.
        result = SpokenEmailAddress.format(result)
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

    /// Recognizers split names ("Hub Spot"), spell digits out ("n acht n") and write what
    /// they hear ("Clawd"). Up to three neighbouring words are tried as one candidate.
    private static let maxWordsPerCandidate = 3
    /// With fewer letters one changed sound already makes another word ("Jams" vs. "Jamf"),
    /// so shorter words and terms are only corrected when the letters are the same.
    private static let minimumFuzzyLength = 5

    /// Gives every word or group of words that clearly means a custom term the term's
    /// spelling. Candidates are scored with `termSimilarity`; the best ones win, and on a tie
    /// the longer span. A fuzzy match never changes real dictionary words, so "Cloud" stays
    /// "Cloud" next to the term "Claude". Punctuation and whitespace outside the replaced
    /// words stay untouched.
    static func applyCustomTerms(
        to text: String,
        customTerms: [String],
        threshold: Double,
        isDictionaryWord: (String) -> Bool = { _ in false }
    ) -> String {
        let matcher = TermMatcher(terms: customTerms)
        guard !matcher.isEmpty else { return text }
        let tokens = tokenize(text)
        // E-mail addresses get no key, so no term ever replaces one.
        let keys = tokens.map { text[$0.core].contains("@") ? [] : matchKey(text[$0.core]) }

        var candidates: [TermCandidate] = []
        for first in tokens.indices where !keys[first].isEmpty {
            var key: [UInt32] = []
            for last in first..<min(first + maxWordsPerCandidate, tokens.count) {
                if last > first {
                    // Punctuation or a line break between two words keeps them apart.
                    let previous = tokens[last - 1], current = tokens[last]
                    guard !previous.hasTrailingPunctuation, !current.hasLeadingPunctuation,
                          !current.followsLineBreak, !keys[last].isEmpty else { break }
                }
                key += keys[last]
                guard let match = matcher.bestMatch(for: key, words: last - first + 1, minimumScore: threshold),
                      match.isExact || match.score >= threshold else { continue }
                candidates.append(TermCandidate(first: first, last: last, match: match))
            }
        }
        guard !candidates.isEmpty else { return text }

        candidates.sort { lhs, rhs in
            if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount > rhs.wordCount }
            return lhs.first < rhs.first
        }

        var claimed = [Bool](repeating: false, count: tokens.count)
        var knownWords: [String: Bool] = [:]
        func isKnown(_ word: String) -> Bool {
            if let known = knownWords[word] { return known }
            let known = isDictionaryWord(word)
            knownWords[word] = known
            return known
        }
        var edits: [(range: Range<String.Index>, term: String)] = []
        for candidate in candidates {
            let span = candidate.first...candidate.last
            guard !span.contains(where: { claimed[$0] }) else { continue }
            // Every candidate taken here claims its words, even when it changes nothing (the
            // term is already right, or the words are real ones), so no weaker candidate
            // around it can swallow them ("Hab Spot an" after "Hab Spot" was kept).
            for index in span { claimed[index] = true }
            // Fuzzy matches only change unknown words. Several words count as known when
            // written as one they are a word ("Black Box") or when each of them is ("über
            // den"); same letters as the term ("Hub Spot") still join, being exact.
            if !candidate.match.isExact {
                let words = tokens[span].map { String(text[$0.core]) }
                if isKnown(dictionaryForm(of: words)) || words.allSatisfy(isKnown) { continue }
            }
            let range = tokens[candidate.first].core.lowerBound..<tokens[candidate.last].core.upperBound
            let term = matcher.terms[candidate.match.term]
            if text[range] != term {
                edits.append((range, term))
            }
        }
        guard !edits.isEmpty else { return text }

        edits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var result = ""
        var position = text.startIndex
        for edit in edits {
            result += text[position..<edit.range.lowerBound]
            result += edit.term
            position = edit.range.upperBound
        }
        result += text[position...]
        return result
    }

    /// How surely `candidate` (one or more words) means `term`, from 0 to 1.
    ///
    /// 1 means the same letters once case, umlaut spelling (ä/ae, ß/ss), spaces and
    /// punctuation are ignored; digits in the term may also be spoken in German or English
    /// ("n acht n", "n eight n" for "n8n"). Otherwise the score is the geometric mean of
    /// two similarities, each `1 - edits / longer length`:
    /// - spelling: Damerau-Levenshtein distance of the letters,
    /// - sound: the same distance of the phonetic codes (`soundCode`).
    /// The geometric mean needs both to agree: "Kobber" sounds like "Copper" (sound 1.0) but
    /// half its letters differ (spelling 0.5), so it scores 0.71 instead of an average of 0.75.
    ///
    /// The score is 0 when fuzzy matching makes no sense: fewer than five letters, digits,
    /// a different first sound (recognizers rarely miss it), the term plus an ending
    /// ("Magnussens" is already right) or only the start of the term ("Magnus" is a name of
    /// its own; one missing letter as in "Claud" is still allowed). Several words must also
    /// start with the term's first letter: a split term keeps it, a word placed in front
    /// ("in Hubspott") does not, even when that word starts with the same sound.
    static func termSimilarity(_ candidate: String, _ term: String) -> Double {
        let words = candidate.split(whereSeparator: \.isWhitespace).count
        return TermMatcher(terms: [term]).bestMatch(for: matchKey(candidate[...]), words: words, minimumScore: 0)?.score ?? 0
    }

    /// Similarity of the plain letters, 1 for "Müller" and "MUELLER".
    static func spellingSimilarity(_ lhs: String, _ rhs: String) -> Double {
        similarity(matchKey(lhs[...]), matchKey(rhs[...]))
    }

    /// Similarity of the phonetic codes, 1 for "Kopper" and "Copper".
    static func soundSimilarity(_ lhs: String, _ rhs: String) -> Double {
        similarity(soundCode(matchKey(lhs[...])), soundCode(matchKey(rhs[...])))
    }

    private static func similarity(_ lhs: [UInt32], _ rhs: [UInt32]) -> Double {
        let length = max(lhs.count, rhs.count)
        guard length > 0 else { return 1 }
        return 1 - Double(editDistance(lhs, rhs)) / Double(length)
    }

    private static let germanDigitNames = ["null", "eins", "zwei", "drei", "vier", "fuenf", "sechs", "sieben", "acht", "neun"]
    private static let englishDigitNames = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    /// The custom terms prepared once per call: every spelling a term may be dictated in,
    /// a lookup for exact matches and the fuzzy spellings grouped by their first sound.
    private struct TermMatcher {
        struct Spelling {
            let term: Int
            let key: [UInt32]
            let code: [UInt32]
        }

        struct Match {
            let term: Int
            let score: Double
            let isExact: Bool
        }

        private(set) var terms: [String] = []
        private var exact: [[UInt32]: Int] = [:]
        private var fuzzyByFirstSound: [UInt32: [Spelling]] = [:]

        var isEmpty: Bool { terms.isEmpty }

        init(terms rawTerms: [String]) {
            for raw in rawTerms {
                let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = matchKey(term[...])
                guard !key.isEmpty, !terms.contains(term) else { continue }
                let index = terms.count
                terms.append(term)
                for spelling in Self.spokenForms(of: key) {
                    if exact[spelling] == nil { exact[spelling] = index }
                    guard allowsFuzzyMatch(spelling) else { continue }
                    let code = soundCode(spelling)
                    guard let firstSound = code.first else { continue }
                    fuzzyByFirstSound[firstSound, default: []]
                        .append(Spelling(term: index, key: spelling, code: code))
                }
            }
        }

        /// The key itself plus, when it contains digits, the digits spelled out in German
        /// and in English.
        private static func spokenForms(of key: [UInt32]) -> [[UInt32]] {
            guard key.contains(where: isASCIIDigit) else { return [key] }
            let spelled = [germanDigitNames, englishDigitNames].map { names in
                key.flatMap { value -> [UInt32] in
                    isASCIIDigit(value) ? names[Int(value) - 48].unicodeScalars.map(\.value) : [value]
                }
            }
            return [key] + spelled
        }

        /// The best term for a candidate key made of `words` words. Fuzzy scores below
        /// `minimumScore` may be cut short and come back as nil, so pass 0 to always get the
        /// true score.
        func bestMatch(for key: [UInt32], words: Int, minimumScore: Double) -> Match? {
            guard !key.isEmpty else { return nil }
            if let term = exact[key] { return Match(term: term, score: 1, isExact: true) }
            guard allowsFuzzyMatch(key) else { return nil }
            let code = soundCode(key)
            guard let firstSound = code.first, let spellings = fuzzyByFirstSound[firstSound] else { return nil }

            var best: (match: Match, length: Int)?
            for spelling in spellings where words == 1 || spelling.key.first == key.first {
                let score = fuzzyScore(key, code, spelling.key, spelling.code, minimumScore: minimumScore)
                guard score > 0 else { continue }
                // Closest first; on a tie the longer term, then the one listed first.
                if let current = best,
                   score < current.match.score || (score == current.match.score && spelling.key.count <= current.length) {
                    continue
                }
                best = (Match(term: spelling.term, score: score, isExact: false), spelling.key.count)
            }
            return best?.match
        }
    }

    private struct TermCandidate {
        let first: Int
        let last: Int
        let match: TermMatcher.Match

        var wordCount: Int { last - first + 1 }
    }

    private static func isASCIIDigit(_ value: UInt32) -> Bool {
        (48...57).contains(value)
    }

    /// Digits are never fuzzy: "Web2" is not a misheard "Web3".
    private static func allowsFuzzyMatch(_ key: [UInt32]) -> Bool {
        key.count >= minimumFuzzyLength && !key.contains(where: isASCIIDigit)
    }

    /// See `termSimilarity`. Returns 0 as soon as the score cannot reach `minimumScore`.
    private static func fuzzyScore(
        _ candidate: [UInt32], _ candidateCode: [UInt32],
        _ term: [UInt32], _ termCode: [UInt32],
        minimumScore: Double
    ) -> Double {
        guard let firstSound = candidateCode.first, firstSound == termCode.first else { return 0 }

        // score = sqrt(spelling * sound), so each part must reach minimumScore² on its own.
        // Cheap bounds come first: this runs for every candidate and term.
        let needed = max(minimumScore, 0) * max(minimumScore, 0)
        let length = max(candidate.count, term.count)
        guard abs(candidate.count - term.count) <= allowedEdits(length, needed) else { return 0 }

        let codeLength = max(candidateCode.count, termCode.count)
        let soundLimit = allowedEdits(codeLength, needed)
        let soundEdits = editDistance(candidateCode, termCode, limit: soundLimit)
        guard soundEdits <= soundLimit, soundEdits < codeLength else { return 0 }
        let sound = 1 - Double(soundEdits) / Double(codeLength)

        let spellingLimit = allowedEdits(length, needed / sound)
        let spellingEdits = editDistance(candidate, term, limit: spellingLimit)
        guard spellingEdits <= spellingLimit, spellingEdits < length else { return 0 }
        let spelling = 1 - Double(spellingEdits) / Double(length)

        if candidate.count > term.count, candidate.starts(with: term) { return 0 }
        if term.count - candidate.count > 1, term.starts(with: candidate) { return 0 }
        return (spelling * sound).squareRoot()
    }

    /// Most edits a string of `length` may have and still reach `similarity`.
    private static func allowedEdits(_ length: Int, _ similarity: Double) -> Int {
        max(Int(((1 - similarity) * Double(length) + 1e-9).rounded(.down)), 0)
    }

    /// Several words written as one the way a dictionary expects ("Black Box" -> "Blackbox").
    private static func dictionaryForm(of words: [String]) -> String {
        guard let first = words.first else { return "" }
        return first + words.dropFirst().map { $0.lowercased() }.joined()
    }

    // MARK: - Spelling and Sound

    /// Letters and digits only, lowercased, umlauts spelled out (ä -> ae, ß -> ss) and other
    /// accents dropped, so "Müller", "MUELLER" and "Mül-ler" compare equal.
    private static func matchKey(_ text: Substring) -> [UInt32] {
        var key: [UInt32] = []
        key.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9": key.append(scalar.value)
            case "A"..."Z": key.append(scalar.value + 32)
            case "ä", "Ä": key += [97, 101]
            case "ö", "Ö": key += [111, 101]
            case "ü", "Ü": key += [117, 101]
            case "ß", "ẞ": key += [115, 115]
            case "\u{308}" where [97, 111, 117].contains(key.last):
                key.append(101) // a decomposed umlaut, "u" followed by a combining diaeresis
            default:
                guard !scalar.isASCII, scalar.properties.isAlphabetic else { continue }
                let folded = String(scalar).lowercased().folding(options: .diacriticInsensitive, locale: nil)
                key += folded.unicodeScalars.filter(\.properties.isAlphabetic).map(\.value)
            }
        }
        return key
    }

    /// Cologne phonetics: a sound code built for German names, so "Meier" and "Mayr" or
    /// "Kopper" and "Copper" get the same code.
    static func colognePhonetics(_ word: String) -> String {
        cologneCode(matchKey(word[...])).map(String.init).joined()
    }

    /// The code the matcher compares: Cologne phonetics, except that a "w" after a vowel and
    /// before a consonant or the end is read as part of the vowel. That is how English names
    /// ("Shaw", "Brown") and recognizer spellings like "Clawd" sound, and northern German
    /// names too ("Pankow"). Plain Cologne codes would hear an extra "v" there.
    private static func soundCode(_ key: [UInt32]) -> [UInt32] {
        let isVowel = { (letter: UInt32?) in letter.map(LetterSet.vowels.contains) ?? false }
        var letters: [UInt32] = []
        letters.reserveCapacity(key.count)
        for (index, letter) in key.enumerated() {
            let next = index + 1 < key.count ? key[index + 1] : nil
            if letter == 119, isVowel(letters.last), !isVowel(next) { continue } // w
            letters.append(letter)
        }
        return cologneCode(letters)
    }

    /// Letters map to digits by sound (vowels 0, b/p 1, d/t 2, f/v/w 3, g/k/q 4, l 5, m/n 6,
    /// r 7, s/z 8; c, d, t, p and x depend on their neighbours, h is silent). Repeated digits
    /// count once and vowels only at the start. Letters outside a-z and digits are skipped.
    /// Umlauts arrive spelled out (ä -> ae), which only departs from the published rules for
    /// a "c" right before an umlaut.
    private static func cologneCode(_ key: [UInt32]) -> [UInt32] {
        let letters = key.filter { (97...122).contains($0) }
        var code: [UInt32] = []
        var lastDigit: UInt32?
        func emit(_ digit: UInt32) {
            defer { lastDigit = digit }
            guard digit != lastDigit, digit != 0 || code.isEmpty else { return }
            code.append(digit)
        }

        for index in letters.indices {
            // 0 stands for "no letter" and is in none of the sets.
            let previous = index > 0 ? letters[index - 1] : 0
            let next = index + 1 < letters.count ? letters[index + 1] : 0

            switch Unicode.Scalar(UInt8(letters[index])) {
            case "a", "e", "i", "j", "o", "u", "y": emit(0)
            case "b": emit(1)
            case "p": emit(next == 104 ? 3 : 1) // h
            case "d", "t": emit(LetterSet.csz.contains(next) ? 8 : 2)
            case "f", "v", "w": emit(3)
            case "g", "k", "q": emit(4)
            case "c":
                let hard = index == 0
                    ? LetterSet.ahkloqrux.contains(next)
                    : !LetterSet.sz.contains(previous) && LetterSet.ahkoqux.contains(next)
                emit(hard ? 4 : 8)
            case "x":
                if !LetterSet.ckq.contains(previous) { emit(4) }
                emit(8)
            case "l": emit(5)
            case "m", "n": emit(6)
            case "r": emit(7)
            case "s", "z": emit(8)
            default: continue // h
            }
        }
        return code
    }

    /// The neighbour sets of the Cologne rules as bit masks over a-z, cheap to test.
    private struct LetterSet {
        let mask: UInt32

        init(_ letters: String) {
            mask = letters.unicodeScalars.reduce(0) { $0 | 1 << ($1.value - 97) }
        }

        func contains(_ letter: UInt32) -> Bool {
            (97...122).contains(letter) && mask >> (letter - 97) & 1 == 1
        }

        static let vowels = LetterSet("aeiouy")
        static let csz = LetterSet("csz")
        static let sz = LetterSet("sz")
        static let ckq = LetterSet("ckq")
        static let ahkoqux = LetterSet("ahkoqux")
        static let ahkloqrux = LetterSet("ahkloqrux")
    }

    /// Optimal string alignment distance (Damerau-Levenshtein): insertions, deletions,
    /// substitutions and swaps of two neighbouring characters cost 1 each.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        editDistance(lhs.unicodeScalars.map(\.value), rhs.unicodeScalars.map(\.value))
    }

    /// Stops early and returns `limit + 1` once the distance is certain to exceed `limit`.
    private static func editDistance(_ lhs: [UInt32], _ rhs: [UInt32], limit: Int = .max) -> Int {
        if lhs.isEmpty || rhs.isEmpty { return max(lhs.count, rhs.count) }
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }

        // Three rows of the table in one buffer: two rows up (for swaps), previous, current.
        // It runs for every candidate and term, so the buffer lives on the stack.
        let width = rhs.count + 1
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 3 * width) { rows in
            lhs.withUnsafeBufferPointer { a in
                rhs.withUnsafeBufferPointer { b in
                    var twoRowsUp = 0, previous = width, current = 2 * width
                    for j in 0..<width { rows[previous + j] = j }
                    for i in 1...a.count {
                        rows[current] = i
                        var rowMinimum = i
                        for j in 1..<width {
                            let substitution = rows[previous + j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                            var value = min(rows[previous + j] + 1, rows[current + j - 1] + 1, substitution)
                            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                                value = min(value, rows[twoRowsUp + j - 2] + 1)
                            }
                            rows[current + j] = value
                            rowMinimum = min(rowMinimum, value)
                        }
                        if rowMinimum > limit { return limit + 1 }
                        (twoRowsUp, previous, current) = (previous, current, twoRowsUp)
                    }
                    return rows[previous + b.count]
                }
            }
        }
    }

    // MARK: - Filler Words

    /// Hesitation sounds that are no word in any language, removed whatever the language.
    /// They also cover German, whose remaining candidates are all real words: "um" (um 10 Uhr),
    /// "eh" (das ist eh egal), "mhm" and "mh" (yes), "ah", "oh", "na" and "hä" (they carry
    /// meaning). "ähem" is left out too, people write it on purpose.
    private static let fillerSounds: Set<String> = ["äh", "ähm", "äm", "öh", "öhm", "ehm", "uhm", "hm"]

    /// Sounds that are fillers in one language but words elsewhere: "um" is a German
    /// preposition, "uh" an interjection in some languages. English "er" stays everywhere,
    /// it is a German pronoun and "ER" a hospital ward; "eh" stays as in "nice, eh?".
    private static let fillerWordsByLanguage: [String: Set<String>] = [
        "en": ["uh", "um", "erm"],
    ]

    /// Removes whole-word hesitation sounds, ignoring case and stretched letters ("Ähhm",
    /// "HMMM"), together with a comma right after them. `normalize` tidies the rest.
    static func removeFillerWords(from text: String, language: String) -> String {
        let languageCode = String(language.lowercased().prefix(while: \.isLetter))
        let fillers = fillerSounds.union(fillerWordsByLanguage[languageCode] ?? [])

        var result = ""
        var position = text.startIndex
        var removedAny = false
        for token in tokenize(text) where token.hasCore {
            let word = text[token.core]
            guard word.allSatisfy(\.isLetter), fillers.contains(withoutRepeatedLetters(word.lowercased())) else { continue }
            var end = token.core.upperBound
            if end < text.endIndex, text[end] == "," { end = text.index(after: end) }
            result += text[position..<token.core.lowerBound]
            position = end
            removedAny = true
        }
        guard removedAny else { return text }
        result += text[position...]
        return result
    }

    private static func withoutRepeatedLetters(_ word: String) -> String {
        var result = ""
        for character in word where character != result.last {
            result.append(character)
        }
        return result
    }

    // MARK: - Normalization

    /// "ich ich ich ich glaube" -> "ich glaube": three or more equal words in a row (case and
    /// punctuation ignored) are a stutter. The first one stays with its case, the last one
    /// hands over its punctuation. Two in a row are valid German ("das das"), and a sentence
    /// end in between means deliberate repetition ("Nein. Nein. Nein.").
    static func collapseStutters(_ text: String) -> String {
        let tokens = tokenize(text)
        let words = tokens.map { text[$0.core].filter(\.isLetter).lowercased() }

        var result = ""
        var position = text.startIndex
        var collapsedAny = false
        var first = 0
        while first < tokens.count {
            var last = first
            while !words[first].isEmpty, last + 1 < tokens.count, words[last + 1] == words[first],
                  !endsSentence(tokens[last], in: text) {
                last += 1
            }
            if last - first >= 2 {
                result += text[position..<tokens[first].core.upperBound]
                position = tokens[last].core.upperBound
                collapsedAny = true
            }
            first = last + 1
        }
        guard collapsedAny else { return text }
        result += text[position...]
        return result
    }

    private static func endsSentence(_ token: Token, in text: String) -> Bool {
        let trailing = text[token.core.upperBound..<token.range.upperBound]
        // An ellipsis is a pause inside the sentence, which is where stutters happen.
        if trailing.hasSuffix("...") || trailing.hasSuffix("…") { return false }
        return trailing.contains { ".!?".contains($0) }
    }

    static func normalize(_ text: String, capitalizeFirstLetterLike original: String) -> String {
        var result = collapseStutters(text)
        // Remove orphaned punctuation left behind by filler removal (", , ok" -> ", ok").
        result = result.replacingOccurrences(of: "[ \\t]+([,.])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",{2,}", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "^[,. \\t]+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // An e-mail address at the start stays lowercase.
        let firstWord = result.prefix(while: { !$0.isWhitespace })
        let originalFirstLetter = original.first(where: \.isLetter)
        if let originalFirstLetter, originalFirstLetter.isUppercase, !firstWord.contains("@"),
           let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }

    // MARK: - Tokens

    /// Text between whitespace, with the word inside it (`core`, first to last letter or
    /// digit) kept apart from the punctuation around it, so edits never move a comma,
    /// period or bracket.
    private struct Token {
        let range: Range<String.Index>
        /// Empty when the token has no letter or digit, like a lone dash.
        let core: Range<String.Index>
        let followsLineBreak: Bool

        var hasCore: Bool { !core.isEmpty }
        var hasLeadingPunctuation: Bool { core.lowerBound > range.lowerBound }
        var hasTrailingPunctuation: Bool { core.upperBound < range.upperBound }
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        var sawLineBreak = false
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                sawLineBreak = sawLineBreak || character.isNewline
                index = text.index(after: index)
                continue
            }
            let start = index
            var coreStart: String.Index?
            var coreEnd = start
            while index < text.endIndex, !text[index].isWhitespace {
                if text[index].isLetter || text[index].isNumber {
                    if coreStart == nil { coreStart = index }
                    coreEnd = text.index(after: index)
                }
                index = text.index(after: index)
            }
            let core = coreStart.map { $0..<coreEnd } ?? start..<start
            tokens.append(Token(range: start..<index, core: core, followsLineBreak: sawLineBreak))
            sawLineBreak = false
        }
        return tokens
    }
}
