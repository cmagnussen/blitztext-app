import XCTest

/// One part of a meeting goes to another person (public issue #45).
final class MeetingTurnTests: XCTestCase {
    private var turns = [
        MeetingTurn(speaker: 1, start: 0, text: "Die Agenda steht."),
        MeetingTurn(speaker: 2, start: 14, text: "Den Raum buche ich."),
        MeetingTurn(speaker: 1, start: 31, text: "Lieber online."),
    ]

    func testReassignsOnlyThatPart() {
        XCTAssertTrue(turns.reassign(turn: turns[2].id, to: 2))
        XCTAssertEqual(turns.map(\.speaker), [1, 2, 2])
    }

    func testNewPersonGetsTheNextNumber() {
        XCTAssertEqual(turns.nextSpeaker, 3)
        XCTAssertTrue(turns.reassign(turn: turns[0].id, to: turns.nextSpeaker))
        XCTAssertEqual(turns.map(\.speaker), [3, 2, 1])
        XCTAssertEqual([MeetingTurn]().nextSpeaker, 1)
    }

    func testSamePersonOrUnknownPartChangesNothing() {
        XCTAssertFalse(turns.reassign(turn: turns[0].id, to: 1))
        XCTAssertFalse(turns.reassign(turn: UUID(), to: 2))
        XCTAssertEqual(turns.map(\.speaker), [1, 2, 1])
    }

    /// Stored meetings keep decoding: `speaker` became mutable, the JSON stays the same.
    func testStoredTurnsStillDecode() throws {
        let json = #"{"id":"5A1C2B3D-1111-2222-3333-444455556666","speaker":2,"start":14,"text":"Hallo"}"#
        let turn = try JSONDecoder().decode(MeetingTurn.self, from: Data(json.utf8))
        XCTAssertEqual(turn.speaker, 2)
        XCTAssertEqual(turn.text, "Hallo")
    }
}
