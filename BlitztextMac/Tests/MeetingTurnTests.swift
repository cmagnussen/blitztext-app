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

    /// Person 3 was renamed to Anna, then her only part went to person 1. "Neue Person" gets
    /// number 3 again and must not be called Anna.
    func testNewPersonDoesNotInheritTheNameOfAPersonWithoutParts() {
        var record = MeetingRecord(
            id: UUID(), createdAt: Date(), title: "Meeting", duration: 60, status: .done,
            turns: turns + [MeetingTurn(speaker: 3, start: 45, text: "Ich schicke das Protokoll.")],
            speakerNames: [1: "Jana", 3: "Anna"]
        )
        XCTAssertTrue(record.reassign(turn: record.turns[3].id, to: 1))
        XCTAssertEqual(record.speakerNames, [1: "Jana"])

        let newPerson = record.turns.nextSpeaker
        XCTAssertEqual(newPerson, 3)
        XCTAssertTrue(record.reassign(turn: record.turns[1].id, to: newPerson))
        XCTAssertEqual(record.name(for: 3), "Person 3")
        XCTAssertEqual(record.name(for: 1), "Jana")
    }

    /// A part that stays where it was changes no name.
    func testUnchangedAssignmentKeepsTheNames() {
        var record = MeetingRecord(
            id: UUID(), createdAt: Date(), title: "Meeting", duration: 60, status: .done,
            turns: turns, speakerNames: [2: "Ben", 5: "Alt"]
        )
        XCTAssertFalse(record.reassign(turn: record.turns[0].id, to: 1))
        XCTAssertEqual(record.speakerNames, [2: "Ben", 5: "Alt"])
    }

    /// Stored meetings keep decoding: `speaker` became mutable, the JSON stays the same.
    func testStoredTurnsStillDecode() throws {
        let json = #"{"id":"5A1C2B3D-1111-2222-3333-444455556666","speaker":2,"start":14,"text":"Hallo"}"#
        let turn = try JSONDecoder().decode(MeetingTurn.self, from: Data(json.utf8))
        XCTAssertEqual(turn.speaker, 2)
        XCTAssertEqual(turn.text, "Hallo")
    }
}

/// A meeting evaluated from an audio file is named after the file.
final class MeetingFileTitleTests: XCTestCase {
    func testTitleIsTheFileName() {
        XCTAssertEqual(MeetingRecord.title(forFile: URL(fileURLWithPath: "/tmp/Interview Müller.m4a")), "Interview Müller")
        XCTAssertEqual(MeetingRecord.title(forFile: URL(fileURLWithPath: "/tmp/2026-11-04 Team.mp3")), "2026-11-04 Team")
    }

    func testNamelessFileGetsTheDateTitle() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        XCTAssertEqual(MeetingRecord.title(forFile: URL(fileURLWithPath: "/tmp/ .m4a"), now: now), MeetingRecord.title(startedAt: now))
    }
}
