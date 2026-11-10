import AppKit
import XCTest

final class MeetingSummaryHTMLTests: XCTestCase {
    func testGermanParagraphsAndLists() {
        let text = "Zusammenfassung\nDer Workshop findet online statt.\n\nEntscheidungen\n- Termin bestätigt\n- Budget bleibt\n\nTo-dos\n- Paul: Angebot schicken"
        let html = MeetingSummaryClipboard.html(text)
        XCTAssertTrue(html.contains("<p><strong>Zusammenfassung</strong></p><p>Der Workshop findet online statt.</p>"))
        XCTAssertTrue(html.contains("<p><strong>Entscheidungen</strong></p><ul><li>Termin bestätigt</li><li>Budget bleibt</li></ul>"))
        XCTAssertTrue(html.contains("<p><strong>To-dos</strong></p><ul><li>Paul: Angebot schicken</li></ul>"))
    }

    func testEnglishSummaryAndCRLF() {
        let html = MeetingSummaryClipboard.html("Summary\r\nAll agreed.\r\n\r\nDecisions\r\n- None")
        XCTAssertTrue(html.contains("<p><strong>Summary</strong></p><p>All agreed.</p><p><strong>Decisions</strong></p><ul><li>None</li></ul>"))
        XCTAssertFalse(html.contains("\r"))
    }

    func testEscapesMarkupAndKeepsUnicode() {
        let html = MeetingSummaryClipboard.html("Überblick 👋\n<script>alert(1)</script>\n- A & B < C > D\n- <img src=\"https://example.invalid/pixel\">")
        XCTAssertTrue(html.contains("Überblick 👋"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("<li>A &amp; B &lt; C &gt; D</li>"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img"))
    }

    func testOtherDashesAndMarkdownRemainLiteral() {
        let html = MeetingSummaryClipboard.html("Zahlen -5 %\n-Keine\n**Wichtig**\n# Titel")
        XCTAssertTrue(html.contains("<p>Zahlen -5 %<br>-Keine<br>**Wichtig**<br># Titel</p>"))
        XCTAssertFalse(html.contains("<ul>"))
    }

    /// The summary cleanup removes indentation, so a wrapped bullet arrives as a plain line.
    func testWrappedBulletStaysInItsItem() {
        let html = MeetingSummaryClipboard.html("- Ana: Angebot schicken\nnach der Rechtsprüfung\n- Ben: Freigeben")
        XCTAssertTrue(html.contains("<ul><li>Ana: Angebot schicken nach der Rechtsprüfung</li><li>Ben: Freigeben</li></ul>"))
    }

    func testSectionTitleEndsAListWithoutBlankLine() {
        let html = MeetingSummaryClipboard.html("- Eins\nTo-dos\n- Zwei")
        XCTAssertTrue(html.contains("<ul><li>Eins</li></ul><p><strong>To-dos</strong></p><ul><li>Zwei</li></ul>"))
    }

    func testSectionTitlesWithMarkupOrColon() {
        XCTAssertEqual(MeetingSummaryClipboard.sectionTitle("**Entscheidungen**"), "Entscheidungen")
        XCTAssertEqual(MeetingSummaryClipboard.sectionTitle("## To-dos"), "To-dos")
        XCTAssertEqual(MeetingSummaryClipboard.sectionTitle("Summary:"), "Summary")
        XCTAssertNil(MeetingSummaryClipboard.sectionTitle("Entscheidungen fehlen noch"))
    }

    func testEmptyTextProducesNoEmptyParagraphOrList() {
        let html = MeetingSummaryClipboard.html("\n\n")
        XCTAssertFalse(html.contains("<p>"))
        XCTAssertFalse(html.contains("<ul>"))
    }
}

/// Use a private pasteboard: tests never overwrite the user's clipboard.
@MainActor
final class MeetingSummaryPasteboardTests: XCTestCase {
    func testWritesBothRepresentationsToOneItemAndPreservesPlainTextBytes() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous content", forType: .string)
        let text = "Überblick\r\n\r\n- A & B\r\n  Ende  \r\n"

        MeetingSummaryClipboard.copy(text, to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        let item = pasteboard.pasteboardItems?.first
        XCTAssertEqual(item?.string(forType: .string)?.utf8.map { $0 }, Array(text.utf8))
        XCTAssertEqual(item?.string(forType: .html), MeetingSummaryClipboard.html(text))
        XCTAssertEqual(Set(item?.types ?? []), Set([.string, .html]))
    }

    func testTranscriptCopyPutsPlainTextAndTheGivenHTMLIntoOneItem() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous content", forType: .string)
        let parts = [MeetingSummaryClipboard.Part(name: "Ich", time: "0:00", text: "Hallo.")]
        let text = "Meeting\n\nIch: Hallo."
        let html = MeetingSummaryClipboard.transcriptHTML(title: "Meeting", parts: parts)

        MeetingSummaryClipboard.copy(text, html: html, to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        let item = pasteboard.pasteboardItems?.first
        XCTAssertEqual(item?.string(forType: .string), text)
        XCTAssertEqual(item?.string(forType: .html), html)
        XCTAssertEqual(Set(item?.types ?? []), Set([.string, .html]))
    }
}

/// "Transkript kopieren" and "Alles kopieren" keep one paragraph per part in rich text editors.
final class MeetingTranscriptHTMLTests: XCTestCase {
    private let parts = [
        MeetingSummaryClipboard.Part(name: "Ich", time: "0:00", text: "Hallo zusammen."),
        MeetingSummaryClipboard.Part(name: "Person 1", time: "4:05", text: "Gern, zuerst der Termin."),
    ]

    func testOneParagraphPerPartWithNameAndTime() {
        let html = MeetingSummaryClipboard.transcriptHTML(title: "Meeting am 4. Nov. 2026, 14:07", parts: parts)
        XCTAssertTrue(html.contains("<p><strong>Meeting am 4. Nov. 2026, 14:07</strong></p>"))
        XCTAssertTrue(html.contains("<p><strong>Ich</strong> · 0:00<br>Hallo zusammen.</p><p><strong>Person 1</strong> · 4:05<br>Gern, zuerst der Termin.</p>"))
    }

    func testEscapesNamesAndText() {
        let html = MeetingSummaryClipboard.transcriptHTML(title: "A & B", parts: [.init(name: "<b>Anna</b>", time: "0:01", text: "1 < 2 & 3 > 2")])
        XCTAssertTrue(html.contains("<strong>A &amp; B</strong>"))
        XCTAssertTrue(html.contains("<strong>&lt;b&gt;Anna&lt;/b&gt;</strong>"))
        XCTAssertTrue(html.contains("1 &lt; 2 &amp; 3 &gt; 2"))
    }

    func testEverythingHasSummaryThenTranscript() {
        let html = MeetingSummaryClipboard.everythingHTML(title: "Meeting", summary: "Entscheidungen\n- Online", parts: parts)
        let summary = html.range(of: "<p><strong>Entscheidungen</strong></p><ul><li>Online</li></ul>")
        let transcript = html.range(of: "<p><strong>Transkript</strong></p><p><strong>Ich</strong>")
        XCTAssertNotNil(summary)
        XCTAssertNotNil(transcript)
        XCTAssertLessThan(summary!.lowerBound, transcript!.lowerBound)
        XCTAssertEqual(html.components(separatedBy: "<html>").count, 2, "one document, not two")
    }

    func testPlainTextStaysWithoutTimes() {
        var record = MeetingRecord(id: UUID(), createdAt: Date(), title: "Meeting", duration: 60, status: .done)
        record.turns = [MeetingTurn(speaker: 1, start: 0, text: "Hallo."), MeetingTurn(speaker: 2, start: 245, text: "Gern.")]
        XCTAssertEqual(record.transcriptShareText, "Meeting\n\nPerson 1: Hallo.\n\nPerson 2: Gern.")
        XCTAssertFalse(record.shareText.contains("4:05"))
    }

    func testEverythingWithoutSummary() {
        let html = MeetingSummaryClipboard.everythingHTML(title: "Meeting", summary: nil, parts: parts)
        XCTAssertTrue(html.contains("<p><strong>Meeting</strong></p><p><strong>Transkript</strong></p>"))
    }
}
