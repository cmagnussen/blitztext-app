import Foundation
import NaturalLanguage

/// Writes dictated e-mail addresses as addresses: "test at outlook punkt com" or
/// "max punkt meier ät firma.de" become "test@outlook.com" and "max.meier@firma.de".
/// Only text that ends in a known top-level domain is touched, so an "at" in a normal
/// sentence stays as it is.
enum SpokenEmailAddress {
    private static let topLevelDomains = [
        "com", "de", "net", "org", "io", "eu", "at", "ch", "info", "biz", "co", "uk", "fr", "it",
        "es", "nl", "be", "dk", "se", "no", "fi", "pl", "cz", "app", "ai", "dev", "me", "tv", "email",
    ]

    /// Words that make the next "Punkt" the noun at the start of a sentence ("Letzter
    /// Punkt"), so they cannot become the first part of an address. Inside a sentence the
    /// case tells: a lowercase word before a capital "Punkt" ("ein wichtiger Punkt").
    private static let nounMarkers = [
        "der", "den", "dem", "des", "ein", "einen", "einem", "kein", "keinen", "dieser", "diesen",
        "jeder", "jeden", "welcher", "erster", "zweiter", "dritter", "letzter", "nächster",
        "wichtiger", "weiterer", "anderer", "neuer", "offener", "springender", "toter",
    ]

    private static let pattern: NSRegularExpression = {
        // A label: letters, digits and the characters addresses use inside a name.
        let label = #"[\p{L}\p{N}_%+-]+"#
        let spokenDot = #"\s+(?:punkt|dot)\s+"#
        let markers = nounMarkers.joined(separator: "|")
        // Before the "at" a written dot must not have spaces, or a sentence end would join
        // the address. A label followed by a spoken dot must not make it the noun "Punkt".
        let noun = "(?:\(markers))\(spokenDot)|(?-i:\\p{Ll}[\\p{L}\\p{N}_%+-]*\\s+Punkt\\s)"
        let local = "(?:(?!\(noun))\(label)(?:\(spokenDot)|\\.))*\(label)"
        let at = #"\s+(?:at|ät)\s+|\s*@\s*"#
        let tld = topLevelDomains.joined(separator: "|")
        // Recognizers sometimes put a space next to the last dot ("outlook. com"). After
        // such a dot the top-level domain has to be lowercase or end the text, because a
        // capital letter there usually starts the next sentence ("at this. It is").
        let spacedEnd = "(?:\\s\\.\\s?|\\.\\s)(?:(?-i:(?:\(tld)))|(?:\(tld))(?=[.!?]?\\s*$))"
        let domain = "\(label)(?:(?:\(spokenDot)|\\.)\(label))*(?:(?:\(spokenDot)|\\.)(?:\(tld))|\(spacedEnd))"
        let address = "(?<![\\p{L}\\p{N}_%+.@-])(\(local))(\(at))(\(domain))(?![\\p{L}\\p{N}])"
        return try! NSRegularExpression(pattern: address, options: [.caseInsensitive])
    }()

    private static let anyDot = try! NSRegularExpression(pattern: #"\s+(?:punkt|dot)\s+|\s*\.\s*"#, options: [.caseInsensitive])

    static func format(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        // A plain "at" is an ordinary word in English ("find us at blackboat.com"), so it
        // only counts outside English text. The text around the addresses decides; a
        // dictation that is just an address counts as one.
        let english = isEnglish(removing: matches, from: text)

        var result = text
        // Back to front, so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: text),
                  let local = Range(match.range(at: 1), in: text),
                  let at = Range(match.range(at: 2), in: text),
                  let domain = Range(match.range(at: 3), in: text) else { continue }
            if english && text[at].trimmingCharacters(in: .whitespaces).lowercased() == "at" { continue }
            let address = joined(String(text[local])) + "@" + joined(String(text[domain]))
            result.replaceSubrange(whole, with: address.lowercased())
        }
        return result
    }

    /// "max punkt meier" or "outlook . com" without spaces and with written dots.
    private static func joined(_ part: String) -> String {
        let range = NSRange(part.startIndex..., in: part)
        return anyDot.stringByReplacingMatches(in: part, range: range, withTemplate: ".")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func isEnglish(removing matches: [NSTextCheckingResult], from text: String) -> Bool {
        var context = text
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: text) else { continue }
            context.replaceSubrange(whole, with: " ")
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(context)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 10)
        let english = hypotheses[.english] ?? 0
        return english >= 0.2 && english > hypotheses[.german] ?? 0
    }
}
