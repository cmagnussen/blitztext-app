import Foundation

/// Frames and checks the AI step of the built-in modes, which edit what was said and never
/// answer it. With the bare transcript as the prompt, the small on-device model answered
/// dictated requests or declined them (TestFlight feedback on iOS build 29: a dictated
/// „mach dich schlau über …“ came back as a refusal). The check is narrow on purpose: it
/// rejects what is clearly no edit, never a free rewording. Foundation only, so the Mac
/// tests compile it.
enum RewriteGuard {
    static let start = "⟦TEXT⟧"
    static let end = "⟦/TEXT⟧"

    /// Added to the instruction of a built-in mode, in the language of the transcript like
    /// the rest of the instruction (`PromptLanguage`).
    static func framingRule(_ language: PromptLanguage) -> String {
        switch language {
        case .german: return "Der zu bearbeitende Text steht in der Nachricht zwischen den Zeilen \(start) und \(end). Gib nur den bearbeiteten Text zurück, ohne diese Markierungen."
        case .english: return "The text to edit is in the message between the lines \(start) and \(end). Return only the edited text, without these markers."
        }
    }

    static var framingRule: String { framingRule(.german) }

    /// The prompt for a built-in mode: the transcript as material, not as a message.
    static func framed(_ transcript: String, language: PromptLanguage = .german) -> String {
        let lead = language == .german ? "Bearbeite diesen diktierten Text:" : "Edit this dictated text:"
        return "\(lead)\n\(start)\n\(withoutMarkerCharacters(transcript))\n\(end)"
    }

    enum Problem: Equatable {
        case empty
        case echoedMarkers
        case refusal

        var message: String {
            switch self {
            case .empty: return "Die KI hat keinen Text zurückgegeben."
            case .echoedMarkers: return "Die KI hat den Text nicht sauber bearbeitet."
            case .refusal: return "Die KI hat auf das Diktat geantwortet, statt es zu bearbeiten."
            }
        }
    }

    /// The result without the frame, when the model wrapped all of it in our markers.
    static func unwrapped(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(start), text.hasSuffix(end), text.count >= start.count + end.count {
            text = String(text.dropFirst(start.count).dropLast(end.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Why `output` is no edit of `source`, or nil when it is one.
    static func problem(in output: String, source: String) -> Problem? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        // The markers never come from the transcript (`framed` drops them), so any left
        // over are the model's.
        if text.contains("⟦") || text.contains("⟧") { return .echoedMarkers }
        // A refusal counts only when the speaker did not say one: „ich kann dir dabei
        // leider nicht helfen“ is a fine thing to dictate.
        if containsRefusal(text), !containsRefusal(source) { return .refusal }
        return nil
    }

    /// Phrases of an assistant declining, German and English. Specific on purpose: a plain
    /// „ich kann nicht …“ is ordinary dictated text.
    private static let refusalPatterns: [NSRegularExpression] = [
        #"\bich kann (dir|dich|ihnen|euch)\b[^.!?\n]{0,40}?\bnicht\b[^.!?\n]{0,40}?\b(helfen|unterstützen|behilflich|weiterhelfen|beantworten)"#,
        #"\bkann ich (dir|dich|ihnen|euch)\b[^.!?\n]{0,40}?\bnicht\b[^.!?\n]{0,40}?\b(helfen|unterstützen|behilflich|weiterhelfen|beantworten)"#,
        #"\bes tut mir leid,? (aber )?ich (kann|darf)\b"#,
        #"\bals (ki|künstliche intelligenz|sprachmodell|ki-modell|ki-assistent)\b"#,
        #"\bich bin (nur )?ein (ki|sprachmodell|ki-modell|ki-assistent)\b"#,
        #"\bi (can't|cannot|can not|am unable to|'m unable to|am not able to) (help|assist)\b"#,
        #"\bi'm sorry,? but i (can't|cannot)\b"#,
        #"\bas an ai\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func containsRefusal(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
        let range = NSRange(normalized.startIndex..., in: normalized)
        return refusalPatterns.contains { $0.firstMatch(in: normalized, range: range) != nil }
    }

    private static func withoutMarkerCharacters(_ text: String) -> String {
        text.replacingOccurrences(of: "⟦", with: "").replacingOccurrences(of: "⟧", with: "")
    }
}
