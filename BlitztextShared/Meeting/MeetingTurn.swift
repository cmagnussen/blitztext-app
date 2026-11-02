import Foundation

/// One part of a meeting transcript and the person who said it.
struct MeetingTurn: Codable, Equatable, Identifiable {
    var id = UUID()
    var speaker: Int
    let start: TimeInterval
    let text: String
}

extension Array where Element == MeetingTurn {
    /// The number for a person nobody was assigned to yet.
    var nextSpeaker: Int {
        (map(\.speaker).max() ?? 0) + 1
    }

    /// Gives one part to another person, when the speaker detection mixed up two voices
    /// (public issue #45). False when there is no such part or it already belongs to them.
    @discardableResult
    mutating func reassign(turn id: UUID, to speaker: Int) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }), self[index].speaker != speaker else { return false }
        self[index].speaker = speaker
        return true
    }
}
