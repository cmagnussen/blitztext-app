import XCTest

final class MeetingMarkdownTests: XCTestCase {
    func testClockMatchesTheResultPage() {
        XCTAssertEqual(MeetingMarkdown.clock(0), "0:00")
        XCTAssertEqual(MeetingMarkdown.clock(245), "4:05")
        XCTAssertEqual(MeetingMarkdown.clock(3725), "1:02:05")
        XCTAssertEqual(MeetingMarkdown.clock(-3), "0:00")
    }

    func testOverviewMatchesTheResultPage() {
        XCTAssertEqual(MeetingMarkdown.overview(duration: 2520, people: 2), "42 Min., 2 Personen")
        XCTAssertEqual(MeetingMarkdown.overview(duration: 20, people: 1), "unter 1 Min., 1 Person")
    }

    func testSectionNamesBecomeHeadings() {
        let summary = "Zusammenfassung\nEs ging um den Plan.\n\nEntscheidungen\n- Start am Montag\n\nTo-dos\n- Person 1: Angebot"
        XCTAssertEqual(
            MeetingMarkdown.sectionHeadings(summary),
            "### Zusammenfassung\nEs ging um den Plan.\n\n### Entscheidungen\n- Start am Montag\n\n### To-dos\n- Person 1: Angebot"
        )
    }

    func testSectionNamesWrittenLooselyAreFound() {
        XCTAssertEqual(MeetingMarkdown.sectionHeadings("**Entscheidungen**"), "### Entscheidungen")
        XCTAssertEqual(MeetingMarkdown.sectionHeadings("to-dos:"), "### To-dos")
        XCTAssertEqual(MeetingMarkdown.sectionHeadings("## Open questions"), "### Open questions")
    }

    func testSentencesNamingASectionStayText() {
        let text = "Die Entscheidungen fielen schnell.\n- To-dos verteilt"
        XCTAssertEqual(MeetingMarkdown.sectionHeadings(text), text)
    }

    func testNotesWithOnlyPlaceholdersAreLeftOut() {
        XCTAssertFalse(MeetingMarkdown.hasNotes("Themen\n- Noch keine\n\nTo-dos\n- Noch keine"))
        XCTAssertTrue(MeetingMarkdown.hasNotes("Themen\n- Budget\n\nTo-dos\n- Noch keine"))
        XCTAssertFalse(MeetingMarkdown.hasNotes("Themen\n\u{2013} Noch keine.\n\nTo-dos\n* none yet"))
    }

    func testDocument() {
        let document = MeetingMarkdown.Document(
            title: "Meeting am 27. Okt. 2026, 14:07",
            overview: "42 Min., 2 Personen",
            summary: "Zusammenfassung\nEs ging um den Plan.\n\nTo-dos\n- Person 1: Angebot",
            liveNotes: "Themen\n- Plan\n\nOffene Fragen\n- Budget",
            turns: [
                .init(start: 0, name: "Ich", text: "Hallo zusammen."),
                .init(start: 12, name: "Person 1", text: "Gern."),
            ]
        )
        XCTAssertEqual(document.markdown, """
        # Meeting am 27. Okt. 2026, 14:07

        42 Min., 2 Personen

        ## Auswertung

        ### Zusammenfassung
        Es ging um den Plan.

        ### To-dos
        - Person 1: Angebot

        ## Live-Notizen

        ### Themen
        - Plan

        ### Offene Fragen
        - Budget

        ## Transkript

        ### [0:00] Ich
        Hallo zusammen.

        ### [0:12] Person 1
        Gern.

        """)
    }

    func testDocumentWithoutSummaryOrNotesHasOnlyTheTranscript() {
        let document = MeetingMarkdown.Document(
            title: "Meeting",
            overview: "unter 1 Min., 1 Person",
            summary: nil,
            liveNotes: "Themen\n- Noch keine",
            turns: [.init(start: 3, name: "Ich", text: "Test.")]
        )
        XCTAssertEqual(document.markdown, "# Meeting\n\nunter 1 Min., 1 Person\n\n## Transkript\n\n### [0:03] Ich\nTest.\n")
    }

    func testSpokenHashOrQuoteStaysText() {
        XCTAssertEqual(MeetingMarkdown.escaped("# eins\n> zwei\ndrei"), "\\# eins\n\\> zwei\ndrei")
        XCTAssertEqual(MeetingMarkdown.escaped("   # eingerückt"), "\\# eingerückt")
    }

    func testSpokenListsRulesAndUnderlinesStayText() {
        XCTAssertEqual(MeetingMarkdown.escaped("1. Quartal lief gut"), "1\\. Quartal lief gut")
        XCTAssertEqual(MeetingMarkdown.escaped("3) Punkt"), "3\\) Punkt")
        XCTAssertEqual(MeetingMarkdown.escaped("- minus fünf"), "\\- minus fünf")
        XCTAssertEqual(MeetingMarkdown.escaped("+ plus"), "\\+ plus")
        XCTAssertEqual(MeetingMarkdown.escaped("Titel\n==="), "Titel\n\\===")
        XCTAssertEqual(MeetingMarkdown.escaped("Titel\n--"), "Titel\n\\--")
        XCTAssertEqual(MeetingMarkdown.escaped("* * *"), "\\* * *")
        XCTAssertEqual(MeetingMarkdown.escaped("~~~"), "\\~~~")
    }

    func testOrdinaryTextIsUnchanged() {
        let text = "Um 10 Uhr, minus 5 % und 2024 war gut. -5 Grad, *wirklich*?"
        XCTAssertEqual(MeetingMarkdown.escaped(text), text)
    }

    func testSpokenHTMLAndCodeStayText() {
        XCTAssertEqual(MeetingMarkdown.escaped("a <b>c</b> `d` e\\f"), "a \\<b>c\\</b> \\`d\\` e\\\\f")
    }

    func testNamesInTurnHeadingsAreEscaped() {
        let document = MeetingMarkdown.Document(
            title: "M", overview: "o", summary: nil, liveNotes: nil,
            turns: [.init(start: 0, name: "<Anna>", text: "Hallo.")]
        )
        XCTAssertTrue(document.markdown.contains("### [0:00] \\<Anna>\nHallo."))
    }

    func testFileNameHasNoPathSeparators() {
        XCTAssertEqual(MeetingMarkdown.fileName(for: "Meeting am 27. Okt. 2026, 14:07"), "Meeting am 27. Okt. 2026, 14-07.md")
        XCTAssertEqual(MeetingMarkdown.fileName(for: "Plan/Budget"), "Plan-Budget.md")
        XCTAssertEqual(MeetingMarkdown.fileName(for: "  "), "Meeting.md")
        XCTAssertEqual(MeetingMarkdown.fileName(for: ".hidden"), "hidden.md")
        XCTAssertEqual(MeetingMarkdown.fileName(for: "A\u{0007}B\nC"), "ABC.md")
        let long = MeetingMarkdown.fileName(for: String(repeating: "ä", count: 300))
        XCTAssertLessThanOrEqual(long.utf8.count, 255)
        XCTAssertTrue(long.hasSuffix(".md"))
    }

    func testRenamedMeetingKeepsItsDateInTheFile() {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        var record = MeetingRecord(id: UUID(), createdAt: start, title: MeetingRecord.title(startedAt: start), duration: 2520, status: .done)
        XCTAssertTrue(record.markdown.hasPrefix("# " + record.title + "\n\n42 Min."), "the date title already has the date")

        record.title = "Kick-off"
        XCTAssertTrue(record.markdown.hasPrefix("# Kick-off\n\n" + MeetingRecord.dateText(start) + " \u{00B7} 42 Min."))
    }
}
