import Foundation

/// A meeting as a Markdown file: title, evaluation and live notes with their sections as
/// headings, then the transcript with the time of every turn as the result page shows it.
/// Plain values only, so it can be checked without the store or the keychain.
enum MeetingMarkdown {
    struct Turn: Equatable {
        let start: TimeInterval
        let name: String
        let text: String
    }

    struct Document: Equatable {
        var title: String
        var overview: String
        var summary: String?
        var liveNotes: String?
        var turns: [Turn]

        var markdown: String {
            var parts = ["# " + title, overview]
            if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                parts += ["## Auswertung", MeetingMarkdown.sectionHeadings(summary)]
            }
            if let notes = liveNotes, MeetingMarkdown.hasNotes(notes) {
                parts += ["## Live-Notizen", MeetingMarkdown.sectionHeadings(notes)]
            }
            if !turns.isEmpty {
                parts.append("## Transkript")
                parts += turns.map {
                    "### [\(MeetingMarkdown.clock($0.start))] \(MeetingMarkdown.escaped($0.name))\n" + MeetingMarkdown.escaped($0.text)
                }
            }
            return parts.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
        }
    }

    /// The section names the summary and the live notes are asked to write, German and
    /// English (`MeetingSummarizer`, `LiveNotesController`).
    static let sectionNames = [
        "Zusammenfassung", "Entscheidungen", "To-dos", "Themen", "Offene Fragen",
        "Summary", "Decisions", "Topics", "Open questions",
    ]

    /// What the notes write into a section that has nothing yet, compared without the
    /// closing full stop and with any dash as "-" (`placeholderKey`).
    private static let placeholders: Set<String> = ["- noch keine", "- keine", "- none yet", "- none"]

    /// "4:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// "42 Min., 2 Personen", the line under the title on the result page.
    static func overview(duration: TimeInterval, people: Int) -> String {
        let minutes = Int((duration / 60).rounded())
        let length = minutes < 1 ? "unter 1 Min." : "\(minutes) Min."
        return "\(length), " + (people == 1 ? "1 Person" : "\(people) Personen")
    }

    /// Turns a line that holds only a section name into a level-3 heading. Small models
    /// sometimes write it bold, with a colon or as a heading already; any other line stays.
    static func sectionHeadings(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            guard let name = sectionName(in: line) else {
                lines.append(line)
                continue
            }
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append("### " + name)
        }
        return lines.joined(separator: "\n")
    }

    /// False when the notes have no point beyond "- Noch keine", e.g. a meeting that ended
    /// before the first update.
    static func hasNotes(_ notes: String) -> Bool {
        notes.components(separatedBy: .newlines).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && sectionName(in: trimmed) == nil && !placeholders.contains(placeholderKey(trimmed))
        }
    }

    /// "- Noch keine." with an en dash and "- noch keine" both become "- noch keine".
    private static func placeholderKey(_ line: String) -> String {
        var key = line.lowercased()
        if let first = key.first, "\u{2013}\u{2014}*\u{2022}".contains(first) {
            key = "-" + key.dropFirst()
        }
        return key.trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespaces))
    }

    /// "Meeting am 27. Okt. 2026, 14-07.md": the title without the characters Finder shows as
    /// a path separator, without control characters and a leading dot (a hidden file), and
    /// short enough for the 255 bytes a file name may have.
    static func fileName(for title: String) -> String {
        let visible = title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var name = String(String.UnicodeScalarView(visible))
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while name.utf8.count > 200 {
            name.removeLast()
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Meeting" : name) + ".md"
    }

    /// Spoken text stays text: what would start a heading, quote, list, rule or code block at
    /// the start of a line, and HTML or code anywhere, gets a backslash. Leading spaces go;
    /// four of them would make a code block.
    static func escaped(_ text: String) -> String {
        text.components(separatedBy: .newlines).map(escapedLine).joined(separator: "\n")
    }

    private static func escapedLine(_ line: String) -> String {
        let inline = line
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: "`", with: "\\`")
        let text = inline.drop { $0 == " " || $0 == "\t" }
        guard let first = text.first else { return "" }
        // "#", ">", "~~~", a rule ("***", "___") and a line of "-" or "=" under the line before,
        // which would make that one a heading.
        let marks = text.filter { $0 != " " && $0 != "\t" }
        let rule = marks.allSatisfy { "-=_*".contains($0) }
            && (marks.contains("-") || marks.contains("=") || marks.count >= 3)
        if "#>".contains(first) || text.hasPrefix("~~~") || rule {
            return "\\" + String(text)
        }
        // "- ", "* ", "+ " start a list item.
        if "-*+".contains(first), text.dropFirst().first.map({ $0 == " " || $0 == "\t" }) ?? true {
            return "\\" + String(text)
        }
        // "1. " or "1) " starts a numbered list, e.g. "1. Quartal".
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = text.dropFirst(digits.count)
            if let mark = rest.first, ".)".contains(mark), rest.dropFirst().first.map({ $0 == " " || $0 == "\t" }) ?? true {
                return String(digits) + "\\" + String(rest)
            }
        }
        return String(text)
    }

    private static func sectionName(in line: String) -> String? {
        var key = line.trimmingCharacters(in: .whitespaces)
        while key.hasPrefix("#") { key.removeFirst() }
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: " *_:"))
        guard !key.isEmpty else { return nil }
        return sectionNames.first { $0.compare(key, options: .caseInsensitive) == .orderedSame }
    }
}
