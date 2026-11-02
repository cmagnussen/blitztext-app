import Foundation

/// The AI step of a mode failed on a transcript that was already made (rejected key, no
/// network, Apple Intelligence gave up). It carries the word-for-word text, so a dictation
/// can keep it instead of losing what was said. Foundation only, so the Mac tests compile it.
struct AIStepFailed: LocalizedError, Equatable {
    let transcript: String
    let reason: String

    static let keptNotice = "Der wortgenaue Text liegt in der Zwischenablage."

    var errorDescription: String? { reason }

    /// The message once the transcript is on the clipboard.
    var keptMessage: String {
        reason.appendingSentence(Self.keptNotice)
    }

    /// `error` from the AI step on `transcript`, as an `AIStepFailed`. A cancel stays a
    /// cancel: it is no failure to report.
    static func wrapping(_ error: Error, transcript: String) -> Error {
        if error is CancellationError || Task.isCancelled || error is AIStepFailed { return error }
        return AIStepFailed(transcript: transcript, reason: error.localizedDescription)
    }
}

extension String {
    /// "Keine Verbindung" + "Der Text liegt ..." gives "Keine Verbindung. Der Text liegt ...".
    func appendingSentence(_ next: String) -> String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last else { return next }
        return text + (".!?".contains(last) ? " " : ". ") + next
    }
}
