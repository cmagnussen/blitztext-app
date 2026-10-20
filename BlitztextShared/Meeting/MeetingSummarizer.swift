import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summary, decisions and to-dos for a meeting transcript.
///
/// The on-device model reads only a few thousand tokens at once, so long meetings are
/// summarized in parts first ("map") and the notes are combined afterwards ("reduce").
@MainActor
enum MeetingSummarizer {
    static let finalInstruction = """
    Du erhältst das Transkript eines Meetings oder Notizen daraus. Wer spricht, ist mit Namen oder als „Person 1“, „Person 2“ markiert. Korrigiert sich jemand beim Sprechen, gilt nur die korrigierte Fassung.
    Schreibe auf Deutsch genau diese drei Abschnitte:

    Zusammenfassung
    Drei bis fünf klare Sätze: worum es ging und was herauskam.

    Entscheidungen
    Spiegelstriche mit „- “. Nur Festlegungen, auf die sich die Runde geeinigt hat, keine Aufgaben. Gab es keine, schreibe „- Keine“.

    To-dos
    Spiegelstriche im Format „- Wer: Was“. „Wer“ ist der Name oder „Person 1“, „Person 2“ wie im Transkript. Sagt jemand „mache ich“ oder „übernehme ich“, ist diese Person zuständig. Nur wenn wirklich niemand genannt ist, schreibe „Offen“. Nennt das Transkript für eine Aufgabe eine Frist, hänge sie in Klammern an, mit den Worten aus dem Transkript. Nennt es keine, lass die Klammer weg. Gab es keine Aufgaben, schreibe „- Keine“.

    Erfinde nichts dazu, vor allem keine Termine, Fristen, Namen oder Zahlen. Keine weiteren Abschnitte, keine Einleitung.
    """

    /// The same for meetings held in another language than German: the summary follows the
    /// meeting, so the names of decisions and tasks stay as they were said.
    static let englishFinalInstruction = """
    You receive the transcript of a meeting or notes taken from it. Speakers are marked by name or as "Person 1", "Person 2". When someone corrects themselves while speaking, only the corrected version counts.
    Write exactly these three sections in English:

    Summary
    Three to five clear sentences: what it was about and what came out of it.

    Decisions
    Bullet points starting with "- ". Only what the group agreed on, no tasks. If there were none, write "- None".

    To-dos
    Bullet points in the format "- Who: What". "Who" is the name or "Person 1", "Person 2" as in the transcript. Whoever says "I'll do it" or "I'll take that" is responsible. Only if really nobody is named, write "Open". If the transcript names a deadline for a task, add it in brackets, in the words of the transcript. If it names none, leave the brackets out. If there were no tasks, write "- None".

    Do not invent anything, above all no dates, deadlines, names or numbers. No other sections, no introduction.
    """

    static let englishPartInstruction = """
    You receive an excerpt from the transcript of a meeting. Speakers are marked. When someone corrects themselves while speaking, only the corrected version counts.
    Note in short bullet points: topics discussed, decisions made and tasks named with the person responsible.
    Keep names, numbers, dates and deadlines that are in the excerpt. Do not invent anything. Only the bullet points, no introduction.
    """

    static let partInstruction = """
    Du erhältst einen Ausschnitt aus dem Transkript eines Meetings. Wer spricht, ist markiert. Korrigiert sich jemand beim Sprechen, gilt nur die korrigierte Fassung.
    Halte in knappen Stichpunkten fest: besprochene Themen, getroffene Entscheidungen und genannte Aufgaben mit der zuständigen Person.
    Behalte Namen, Zahlen, Termine und Fristen, die im Ausschnitt stehen. Erfinde nichts dazu. Nur die Stichpunkte, keine Einleitung.
    """

    /// A model the app brings along instead of the system's, e.g. a downloaded local model.
    struct Backend {
        /// Characters per request.
        let characterLimit: Int
        let complete: (_ instruction: String, _ text: String) async throws -> String
    }

    static func summarize(_ transcript: String, engine: TextRewriter.Engine, backend: Backend? = nil) async throws -> String {
        let local = TextRewriter.runsLocally(engine: engine)
        // Characters per request: what fits the on-device model, generous for providers.
        let limit = backend?.characterLimit ?? (local ? localCharacterLimit : 60_000)
        func rewrite(_ text: String, instruction: String) async throws -> String {
            if let backend { return try await backend.complete(instruction, text) }
            return try await Self.rewrite(text, instruction: instruction, engine: engine)
        }

        let isGerman = isGermanMeeting(transcript)
        var material = transcript
        var round = 0
        while material.count > limit, round < 3 {
            var notes: [String] = []
            for part in chunks(of: material, limit: limit) {
                notes.append(try await rewrite(part, instruction: isGerman ? partInstruction : englishPartInstruction))
            }
            material = notes.joined(separator: "\n\n")
            round += 1
        }
        let summary = try await rewrite(material, instruction: isGerman ? finalInstruction : englishFinalInstruction)
        return InventedDeadlineFilter.filtered(cleaned(summary), transcript: transcript, transcriptIsGerman: isGerman)
    }

    /// Characters the on-device model reads at once. From iOS and macOS 27 it reports its
    /// context (8,192 tokens on macOS 27.0, measured); before, it had 4,096. German takes
    /// about 2.5 characters per token or more, and instruction and answer need room too.
    static var localCharacterLimit: Int {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return max(5_000, (SystemLanguageModel.default.contextSize - 2_000) * 5 / 2)
        }
        #endif
        return 5_000
    }

    /// A summary reads a conversation, not a dictation: no dictation rules (their examples name
    /// weekdays the model copied into to-dos; the self-correction rule is in the instructions
    /// above, without examples), and the same transcript gives the same summary.
    private static func rewrite(_ text: String, instruction: String, engine: TextRewriter.Engine) async throws -> String {
        try await TextRewriter.rewrite(text, instruction: instruction, engine: engine, dictationRules: false, deterministic: true)
    }

    /// German unless the transcript is clearly in another language. Too little text to tell
    /// counts as German, the language of the app.
    static func isGermanMeeting(_ transcript: String) -> Bool {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: transcript) else { return true }
        return language == .german
    }

    /// Small models sometimes echo parts of the instruction or leave placeholder bullets.
    static func cleaned(_ summary: String) -> String {
        let echoes = [
            "Erfinde nichts dazu", "Keine weiteren Abschnitte", "Spiegelstriche im Format", "Drei bis fünf klare Sätze", "lass die Klammer weg",
            "Spiegelstriche mit „- “:",
            "Do not invent anything", "No other sections", "Bullet points in the format", "Three to five clear sentences", "leave the brackets out",
            "Bullet points starting with \"- \":",
        ]
        return summary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !echoes.contains { line.contains($0) } && !["- Offen", "- Offen:", "- Open", "- Open:"].contains(line)
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits at paragraph boundaries (speaker turns) so no turn is cut in half.
    static func chunks(of text: String, limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if !current.isEmpty, current.count + paragraph.count + 2 > limit {
                result.append(current)
                current = ""
            }
            if paragraph.count > limit {
                // A single very long turn: cut at sentence ends.
                var remaining = paragraph[...]
                while remaining.count > limit {
                    let cut = remaining.index(remaining.startIndex, offsetBy: limit)
                    let end = remaining[..<cut].lastIndex(where: { ".!?".contains($0) }).map { remaining.index(after: $0) } ?? cut
                    result.append(String(remaining[..<end]))
                    remaining = remaining[end...]
                }
                current = String(remaining)
            } else {
                current += current.isEmpty ? paragraph : "\n\n" + paragraph
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
