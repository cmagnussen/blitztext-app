import Foundation
import NaturalLanguage

/// How Blitztext writes German. `.swiss` is the spelling of Switzerland and Liechtenstein:
/// "ss" instead of "ß", large numbers with an apostrophe, amounts with a decimal point and
/// quotation marks as «…». `.automatic` follows the region and language set in macOS.
enum GermanVariant: String, Codable, CaseIterable, Identifiable {
    case automatic
    case standard
    case swiss

    var id: String { rawValue }

    /// "Automatisch" names the one of the other two it stands for on this Mac.
    func label(systemIsSwiss: Bool = GermanVariant.systemIsSwiss) -> String {
        switch self {
        case .automatic: return systemIsSwiss ? "Automatisch (Schweiz)" : "Automatisch (Deutsch)"
        case .standard: return "Deutsch"
        case .swiss: return "Deutsch (Schweiz)"
        }
    }

    func isSwiss(systemIsSwiss: Bool = GermanVariant.systemIsSwiss) -> Bool {
        switch self {
        case .automatic: return systemIsSwiss
        case .standard: return false
        case .swiss: return true
        }
    }

    /// Switzerland and Liechtenstein both write German without "ß".
    static let swissRegions: Set<String> = ["CH", "LI"]

    /// macOS is set to Switzerland or Liechtenstein: by the region (Systemeinstellungen >
    /// Allgemein > Sprache & Region), or by the first preferred language, e.g. "Deutsch
    /// (Schweiz)". The keyboard layout does not count; it changes per window, and many
    /// people in Switzerland type on other layouts.
    static var systemIsSwiss: Bool {
        isSwiss(locale: .autoupdatingCurrent, preferredLanguages: Locale.preferredLanguages)
    }

    /// `locale.region` honours a region set apart from the language ("de_DE@rg=chzzzz").
    static func isSwiss(locale: Locale, preferredLanguages: [String]) -> Bool {
        if let region = locale.region?.identifier, swissRegions.contains(region) { return true }
        guard let first = preferredLanguages.first else { return false }
        let language = Locale(identifier: first).language
        switch language.languageCode?.identifier {
        case "gsw": return true
        case "de": return language.region.map { swissRegions.contains($0.identifier) } ?? false
        default: return false
        }
    }

    /// The setting, for the writing modes, which have no access to it.
    nonisolated(unsafe) static var current: GermanVariant = .automatic
}

/// Swiss spelling for text Blitztext writes, after the usage in Switzerland and
/// Liechtenstein and the Schreibweisungen of the Federal Chancellery: "ss" instead of "ß";
/// numbers of five or more digits grouped with an apostrophe (12’500), shorter ones not
/// (1000); amounts with a decimal point (CHF 23.50); quotation marks as «…» and ‹…›.
/// A pure string step: only what it changes is touched, and numbers and quotation marks
/// change only in German text.
enum SwissSpelling {
    /// Added to the instruction of the writing modes and German meeting summaries when Swiss
    /// spelling applies. The amounts are pairs that keep their currency: examples that were
    /// all Franken made small models turn "Euro" into "Franken". Swiss words are kept, not
    /// asked for: a list of them made models swap the speaker's words. `apply` runs on the
    /// answer as well.
    static let modelInstruction = """
    Schweizer Rechtschreibung, wie in der Schweiz und in Liechtenstein. Sie regelt nur, wie deutscher Text geschrieben wird: Die Sprache bleibt, und die Wortwahl des Sprechers auch. Es ist Hochdeutsch, keine Mundart.
    - Immer «ss» statt «ß»: Strasse, gross, heisst.
    - Zahlen ab fünf Stellen mit Apostroph ’ gliedern, vierstellige nicht: 12’500 und 1’250’000, aber 1000.
    - Geldbeträge in jeder Währung mit Dezimalpunkt zwischen Franken und Rappen, Euro und Cent usw. Betrag und Währung bleiben, wie gesprochen: Euro bleibt Euro, Franken bleibt Franken; rechne nichts um. So wird es geschrieben:
      CHF 23,50 → CHF 23.50
      23,50 Franken → 23.50 Franken
      Fr. 20,– → Fr. 20.–
      € 23,40 → € 23.40
      23,40 Euro → 23.40 Euro
      $ 23,50 → $ 23.50
      12.500,50 Franken → 12’500.50 Franken
    - Das Komma bleibt bei Bruchteilen eines Rappens oder Cents (0,13 Rappen), bei Millionen und Milliarden (4,16 Mio. CHF) und bei anderen Dezimalzahlen (3,5 Prozent).
    - Anführungszeichen als «…», innere als ‹…›.
    - Schweizer Wörter sind korrektes Hochdeutsch, zum Beispiel Velo, Trottoir, parkieren, Lavabo, Spital, Billett. Lass sie stehen und ersetze sie nicht durch bundesdeutsche Wörter. Umgekehrt ersetzt du auch keine Wörter durch Schweizer Wörter.
    """

    static func addingRules(to instruction: String, isSwiss: Bool) -> String {
        isSwiss ? instruction + "\n\n" + modelInstruction : instruction
    }

    static func apply(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{00DF}", with: "ss")
            .replacingOccurrences(of: "\u{1E9E}", with: "SS")
        guard !isClearlyNotGerman(result) else { return result }
        result = regroupingNumbers(result)
        result = withDecimalPointInAmounts(result)
        result = groupingPlainAmounts(result)
        result = withGuillemets(result)
        return result
    }

    // MARK: - Language

    /// Short texts and numbers alone say too little about their language; they count as German.
    private static func isClearlyNotGerman(_ text: String) -> Bool {
        guard text.count >= 24 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .german else { return false }
        return (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.8
    }

    // MARK: - Numbers

    /// The Swiss thousands separator, the typographic apostrophe as macOS writes it.
    static let groupSeparator = "\u{2019}"

    /// "1.250.000", "12 500" with fixed spaces, or "12'500" with the straight apostrophe some
    /// models write. Not a version ("2.100.3"), a number with a leading zero
    /// ("044.668.18.00"), or one that goes on in digits.
    private static let groupedNumber = try! NSRegularExpression(
        pattern: #"(?<![\d.,'’])[1-9]\d{0,2}(?:[.'\x{00A0}\x{202F}]\d{3})+(?![\d'’]|\.\d)"#
    )

    /// Words after which a number is an account, customer or reference number, not an amount.
    private static let identifierBefore = try! NSRegularExpression(
        pattern: #"(?i)\b(?:konto\p{L}*|iban|ahv|nr|\p{L}*nummer|referenz\p{L}*)\b[.:#\s-]{0,4}$"#
    )

    private static let currencyBefore = #"(?<!\p{L})(?:CHF|SFr\.|Fr\.|EUR|Euro|USD|GBP|€|\$|£)\s?"#
    private static let currencyAfter = #"\s?(?:CHF|Fr\.|Franken|EUR|Euro|USD|Dollar|GBP|€|\$|£)(?!\p{L})"#
    private static let integerPart = #"(?:[1-9]\d{0,2}(?:’\d{3})+|\d+)"#

    /// Dots and fixed spaces in numbers become apostrophes from five digits on; a
    /// four-digit number is written without a separator ("1.000" becomes "1000").
    static func regroupingNumbers(_ text: String) -> String {
        replacingMatches(of: groupedNumber, in: text) { match, before in
            guard identifierBefore.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) == nil else {
                return nil
            }
            return grouped(match.filter(\.isNumber))
        }
    }

    /// "CHF 23,50" and "23,50 Franken" become "CHF 23.50" and "23.50 Franken", in any
    /// currency. Fractions of a Rappen or Cent ("0,13 Rappen") and amounts in millions
    /// ("4,16 Mio. CHF") keep their comma, as the Federal Chancellery writes them.
    static func withDecimalPointInAmounts(_ text: String) -> String {
        let before = try! NSRegularExpression(
            pattern: "(\(currencyBefore))(\(integerPart)),(\\d{2}(?!\\d)|–)(?!\\s?(?:Mio|Millionen|Mrd|Milliarden))"
        )
        let after = try! NSRegularExpression(
            pattern: "(?<![\\d.,’])(\(integerPart)),(\\d{2})(?=\(currencyAfter))"
        )
        let pointBefore = before.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2.$3"
        )
        return after.stringByReplacingMatches(
            in: pointBefore, range: NSRange(pointBefore.startIndex..., in: pointBefore), withTemplate: "$1.$2"
        )
    }

    /// An amount of five or more digits written without separators or with plain spaces:
    /// "CHF 12500", "12500 Franken", "1 250 000 Euro". Without a currency a long number is
    /// more often a postcode, a phone or an account number, so it stays.
    static func groupingPlainAmounts(_ text: String) -> String {
        let digits = "(?:[1-9]\\d{0,2}(?: \\d{3})+|\\d{5,})"
        let before = try! NSRegularExpression(pattern: "(?<=\(currencyBefore))\(digits)(?![\\d’'])")
        let after = try! NSRegularExpression(
            pattern: "(?<![\\d.,’'])\(digits)(?=(?:\\.(?:\\d{2}|–))?\(currencyAfter))"
        )
        let groupedBefore = replacingMatches(of: before, in: text) { match, _ in grouped(match.filter(\.isNumber)) }
        return replacingMatches(of: after, in: groupedBefore) { match, _ in grouped(match.filter(\.isNumber)) }
    }

    /// Five or more digits in groups of three from the right; up to four stay together.
    private static func grouped(_ digits: String) -> String {
        guard digits.count > 4 else { return digits }
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return groups.joined(separator: groupSeparator)
    }

    // MARK: - Quotation marks

    private static let quotationRules: [(NSRegularExpression, String)] = [
        // German „…“ and ‚…‘.
        (try! NSRegularExpression(pattern: "\u{201E}([^\u{201E}\u{201C}\u{201D}\\n]*)[\u{201C}\u{201D}]"), "«$1»"),
        (try! NSRegularExpression(pattern: "\u{201A}([^\u{201A}\u{2018}\u{2019}\\n]*)[\u{2018}\u{2019}]"), "‹$1›"),
        // English “…”, which language models like to write.
        (try! NSRegularExpression(pattern: "\u{201C}([^\u{201C}\u{201D}\\n]*)\u{201D}"), "«$1»"),
        // Straight "…" only as a pair around words, so 27" or a lone mark stays.
        (try! NSRegularExpression(
            pattern: #"(^|[\s(\[–—-])"([^"\n]+?)"(?=$|[\s.,;:!?)\]–—-])"#,
            options: .anchorsMatchLines
        ), "$1«$2»"),
    ]

    static func withGuillemets(_ text: String) -> String {
        quotationRules.reduce(text) { result, rule in
            rule.0.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.1
            )
        }
    }

    // MARK: - Helpers

    /// Replaces each match with `transform(match, text before it)`; nil keeps the match.
    private static func replacingMatches(
        of expression: NSRegularExpression,
        in text: String,
        with transform: (String, String) -> String?
    ) -> String {
        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let before = String(result[..<range.lowerBound].suffix(30))
            if let replacement = transform(String(result[range]), before) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
}
