import Foundation

/// The summary as the result page shows it: section titles apart from the text so the page
/// can set them bold, bullets with "•", and without a leading "Zusammenfassung", which the
/// card's own title already says. Copied text stays as the model wrote it.
enum SummaryDisplay {
    struct Line: Equatable {
        let text: String
        let isTitle: Bool
    }

    static func lines(_ summary: String) -> [Line] {
        var lines = summary.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let first = lines.first, let title = MeetingSummaryClipboard.sectionTitle(first),
           ["zusammenfassung", "summary"].contains(title.lowercased()) {
            lines = lines.dropFirst().drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return lines.map { line in
            if let title = MeetingSummaryClipboard.sectionTitle(line) {
                return Line(text: title, isTitle: true)
            }
            return Line(text: ListDisplay.bullets(line), isTitle: false)
        }
    }
}
