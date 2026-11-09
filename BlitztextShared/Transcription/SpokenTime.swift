import Foundation

/// Writes spoken German times as times: speech recognition puts down what was said, so
/// "sechzehn Uhr fünfundvierzig bis siebzehn Uhr fünf" came out as "16 Uhr 45 bis 17 Uhr 5"
/// (feedback on Mac 1.16.4). Becomes "16:45 bis 17:05 Uhr". Plain string code, only German,
/// and only an hour 0 to 23 with "Uhr" and minutes 0 to 59 right after it; "um 10 Uhr" and
/// "um 10 Uhr 3 Personen" stay as they are. Foundation only, so the Mac tests compile it.
enum SpokenTime {
    static func format(_ text: String, language: String) -> String {
        guard language.lowercased().hasPrefix("de") else { return text }
        var result = text
        // "16 Uhr 45" -> "16:45 Uhr". The minutes must end the clause or be followed by a
        // lower-case word: a capitalised word after them is a noun the number counts.
        let time = try! NSRegularExpression(pattern: #"(?<![\d:.,])\b([01]?\d|2[0-3]) Uhr (\d{1,2})\b(?![\d:.,]\d)(?=$|[^\s\p{L}\d]|\s+\p{Ll})"#)
        for match in time.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result),
                  let hourRange = Range(match.range(at: 1), in: result),
                  let minuteRange = Range(match.range(at: 2), in: result),
                  let hour = Int(result[hourRange]), let minute = Int(result[minuteRange]),
                  minute < 60
            else { continue }
            result.replaceSubrange(whole, with: String(format: "%d:%02d Uhr", hour, minute))
        }
        // "16:45 Uhr bis 17:05 Uhr" -> "16:45 bis 17:05 Uhr".
        result = result.replacingOccurrences(
            of: #"\b(\d{1,2}:\d{2}) Uhr (bis) (\d{1,2}:\d{2}) Uhr\b"#,
            with: "$1 $2 $3 Uhr",
            options: .regularExpression
        )
        return result
    }
}
