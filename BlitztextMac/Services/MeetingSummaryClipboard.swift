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

    /// Summaries use paragraphs and "- " bullets, not general Markdown.
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
            if line.isEmpty {
                flushParagraph()
                flushBullets()
            } else if line.hasPrefix("- ") {
                flushParagraph()
                bullets.append(escape(String(line.dropFirst(2))))
            } else {
                flushBullets()
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
