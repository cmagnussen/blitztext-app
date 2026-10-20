import Foundation

/// A transcribed word with its position in the recording.
struct TimedWord: Sendable, Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    /// Joins SentencePiece tokens into words: a token starting with a space or "▁" begins a new word.
    static func words(from tokens: [(text: String, start: TimeInterval, end: TimeInterval)]) -> [TimedWord] {
        var words: [TimedWord] = []
        for token in tokens {
            let piece = token.text.replacingOccurrences(of: "\u{2581}", with: " ")
            let startsWord = piece.hasPrefix(" ") || words.isEmpty
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if startsWord {
                words.append(TimedWord(text: trimmed, start: token.start, end: token.end))
            } else if let last = words.popLast() {
                words.append(TimedWord(text: last.text + trimmed, start: last.start, end: token.end))
            }
        }
        return words
    }
}

/// A stretch of the recording in which one speaker talks.
struct SpeakerTurn: Sendable, Equatable {
    let speaker: Int
    let start: TimeInterval
    let end: TimeInterval
}

/// Assigns the words of one transcript to speaker turns by time.
///
/// Transcribing the whole meeting at once keeps the language stable; transcribing
/// short turns one by one made Parakeet misdetect German as English.
enum SpeakerAlignment {
    struct Paragraph: Equatable {
        let speaker: Int
        let start: TimeInterval
        let text: String
    }

    /// Without speaker turns, paragraphs break at pauses longer than this.
    static let paragraphPause: TimeInterval = 1.5

    /// - Parameter breaks: Where someone on another track starts talking, e.g. the microphone
    ///   in an online meeting. A paragraph spanning such a moment is split there, so a
    ///   one-on-one call reads as a conversation and not as one block per person.
    static func paragraphs(words: [TimedWord], turns: [SpeakerTurn], breaks: [TimeInterval] = []) -> [Paragraph] {
        var paragraphs: [Paragraph] = []
        var previousStart: TimeInterval = -.infinity
        var previousEnd: TimeInterval = 0
        let breaks = breaks.sorted()
        var nextBreak = 0

        for word in words {
            let speaker = turns.isEmpty ? 1 : speakerID(at: (word.start + word.end) / 2, in: turns)
            let pauseBreak = turns.isEmpty && word.start - previousEnd > paragraphPause
            var otherTrackBreak = false
            while nextBreak < breaks.count, breaks[nextBreak] <= word.start {
                otherTrackBreak = otherTrackBreak || breaks[nextBreak] > previousStart
                nextBreak += 1
            }
            if let last = paragraphs.last, last.speaker == speaker, !pauseBreak, !otherTrackBreak {
                paragraphs[paragraphs.count - 1] = Paragraph(speaker: speaker, start: last.start, text: last.text + " " + word.text)
            } else {
                paragraphs.append(Paragraph(speaker: speaker, start: word.start, text: word.text))
            }
            previousStart = word.start
            previousEnd = word.end
        }
        return paragraphs
    }

    /// The turn containing `time`, otherwise the closest one.
    private static func speakerID(at time: TimeInterval, in turns: [SpeakerTurn]) -> Int {
        if let turn = turns.first(where: { $0.start <= time && time <= $0.end }) {
            return turn.speaker
        }
        let closest = turns.min { distance(time, $0) < distance(time, $1) }
        return closest?.speaker ?? 1
    }

    private static func distance(_ time: TimeInterval, _ turn: SpeakerTurn) -> TimeInterval {
        time < turn.start ? turn.start - time : time - turn.end
    }
}
