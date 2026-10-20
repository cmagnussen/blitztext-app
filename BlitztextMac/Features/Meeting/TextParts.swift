import Foundation

/// Cuts transcript text for a model that reads a limited number of characters at once:
/// after a whole line ("Name: ...") when possible, otherwise after a word.
enum TextParts {
    /// Where the first part of `text` within `limit` characters ends.
    static func endOfLeadingPart(of text: String, limit: Int) -> String.Index {
        guard text.count > limit else { return text.endIndex }
        let cut = text.index(text.startIndex, offsetBy: limit)
        let head = text[..<cut]
        if let newline = head.lastIndex(of: "\n"), newline > text.startIndex { return text.index(after: newline) }
        if let space = head.lastIndex(of: " "), space > text.startIndex { return text.index(after: space) }
        return cut
    }

    /// Where the last part of `text` within `limit` characters starts.
    static func startOfTrailingPart(of text: String, limit: Int) -> String.Index {
        guard text.count > limit else { return text.startIndex }
        let cut = text.index(text.endIndex, offsetBy: -limit)
        if let newline = text[cut...].firstIndex(of: "\n") { return text.index(after: newline) }
        return cut
    }
}
