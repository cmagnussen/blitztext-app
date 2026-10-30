import AppKit

/// Rich text for explicit summary copying; dictation and transcript copying stay plain.
enum MeetingSummaryClipboard {
    @MainActor
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(html(text), forType: .html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// The section titles the summary instruction asks for (`MeetingSummarizer`).
    private static let sectionTitles: Set<String> = ["zusammenfassung", "entscheidungen", "to-dos", "summary", "decisions"]

    /// "Entscheidungen", also as "**Entscheidungen**", "## Entscheidungen" or "Entscheidungen:",
    /// as the plain title; nil for any other line.
    static func sectionTitle(_ line: String) -> String? {
        let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "*#:").union(.whitespaces))
        return sectionTitles.contains(title.lowercased()) ? title : nil
    }

    /// Summaries use paragraphs and "- " bullets, not general Markdown. Section titles are
    /// bold and start a new block. A line after a bullet continues it: the summary cleanup
    /// removes indentation, so a wrapped bullet arrives as a plain next line.
    static func html(_ text: String) -> String {
        var blocks: [String] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append("<p>" + paragraph.joined(separator: "<br>") + "</p>")
            paragraph.removeAll()
        }

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append("<ul>" + bullets.map { "<li>" + $0 + "</li>" }.joined() + "</ul>")
            bullets.removeAll()
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                flushBullets()
            } else if let title = sectionTitle(trimmed) {
                flushParagraph()
                flushBullets()
                blocks.append("<p><strong>" + escape(title) + "</strong></p>")
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                bullets.append(escape(String(trimmed.dropFirst(2))))
            } else if !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + escape(trimmed)
            } else {
                paragraph.append(escape(line))
            }
        }
        flushParagraph()
        flushBullets()
        return "<html><head><meta charset=\"utf-8\"></head><body style=\"white-space: pre-wrap\">"
            + blocks.joined() + "</body></html>"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
