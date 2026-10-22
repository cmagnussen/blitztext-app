import AppKit
import XCTest

final class MeetingSummaryHTMLTests: XCTestCase {
    func testGermanParagraphsAndLists() {
        let text = "Zusammenfassung\nDer Workshop findet online statt.\n\nEntscheidungen\n- Termin bestätigt\n- Budget bleibt\n\nTo-dos\n- Paul: Angebot schicken"
        let html = MeetingSummaryClipboard.html(text)
        XCTAssertTrue(html.contains("<p>Zusammenfassung<br>Der Workshop findet online statt.</p>"))
        XCTAssertTrue(html.contains("<p>Entscheidungen</p><ul><li>Termin bestätigt</li><li>Budget bleibt</li></ul>"))
        XCTAssertTrue(html.contains("<p>To-dos</p><ul><li>Paul: Angebot schicken</li></ul>"))
    }

    func testEnglishSummaryAndCRLF() {
        let html = MeetingSummaryClipboard.html("Summary\r\nAll agreed.\r\n\r\nDecisions\r\n- None")
        XCTAssertTrue(html.contains("<p>Summary<br>All agreed.</p><p>Decisions</p><ul><li>None</li></ul>"))
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

    func testListCanBeFollowedByParagraphWithoutBlankLine() {
        let html = MeetingSummaryClipboard.html("- Eins\nAbsatz\n- Zwei")
        XCTAssertTrue(html.contains("<ul><li>Eins</li></ul><p>Absatz</p><ul><li>Zwei</li></ul>"))
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
}
