import AppKit
import XCTest

/// Timing rules for restoring the clipboard, with the clock under test control.
final class ClipboardRestoreTrackerTests: XCTestCase {
    private let own = 42
    private let timings = ClipboardRestoreTimings.standard

    private func tracker(pastedAt: TimeInterval = 100) -> ClipboardRestoreTracker {
        ClipboardRestoreTracker(pastedAt: pastedAt, ownChangeCount: own, timings: timings)
    }

    func testDefaultTimingsLeanTowardsWaiting() {
        XCTAssertGreaterThan(timings.quietPeriod, 0)
        XCTAssertGreaterThan(timings.minimumHold, timings.quietPeriod)
        XCTAssertGreaterThan(timings.noReadTimeout, timings.minimumHold)
        XCTAssertGreaterThan(timings.maximumWait, timings.noReadTimeout)
    }

    func testWithoutReadsWaitsForTheTimeout() {
        let tracker = tracker()
        XCTAssertEqual(tracker.decision(at: 100, changeCount: own), .wait(until: 105))
        XCTAssertEqual(tracker.decision(at: 104.99, changeCount: own), .wait(until: 105))
        XCTAssertEqual(tracker.decision(at: 105, changeCount: own), .restore)
    }

    func testRestoresAfterQuietPeriodFollowingARead() {
        var tracker = tracker()
        tracker.recordRead(at: 101.5)
        XCTAssertEqual(tracker.decision(at: 101.6, changeCount: own), .wait(until: 102))
        XCTAssertEqual(tracker.decision(at: 102, changeCount: own), .restore)
    }

    func testFastReadStillWaitsForTheMinimumHold() {
        var tracker = tracker()
        tracker.recordRead(at: 100.02)
        XCTAssertEqual(tracker.decision(at: 100.6, changeCount: own), .wait(until: 101))
        XCTAssertEqual(tracker.decision(at: 101, changeCount: own), .restore)
    }

    func testEveryReadRestartsTheQuietPeriod() {
        var tracker = tracker()
        tracker.recordRead(at: 101.25)
        tracker.recordRead(at: 101.5)
        tracker.recordRead(at: 101.75)
        XCTAssertEqual(tracker.decision(at: 102, changeCount: own), .wait(until: 102.25))
        XCTAssertEqual(tracker.readCount, 3)
        XCTAssertEqual(tracker.firstReadAt, 101.25)
    }

    func testReadsArrivingOutOfOrderKeepTheLatest() {
        var tracker = tracker()
        tracker.recordRead(at: 101.75)
        tracker.recordRead(at: 101.25)
        XCTAssertEqual(tracker.restoreAt, 102.25)
        XCTAssertEqual(tracker.firstReadAt, 101.25)
    }

    func testReadJustBeforeTheTimeoutStillGetsItsQuietPeriod() {
        var tracker = tracker()
        tracker.recordRead(at: 104.875)
        XCTAssertEqual(tracker.decision(at: 105, changeCount: own), .wait(until: 105.375))
        XCTAssertEqual(tracker.decision(at: 105.375, changeCount: own), .restore)
    }

    func testMaximumWaitEndsReadsThatNeverStop() {
        var tracker = tracker()
        var time = 100.3
        while time < 120 {
            tracker.recordRead(at: time)
            time += 0.3
        }
        XCTAssertEqual(tracker.restoreAt, 115)
        XCTAssertEqual(tracker.decision(at: 115, changeCount: own), .restore)
    }

    func testNewerClipboardContentIsLeftAlone() {
        var tracker = tracker()
        XCTAssertEqual(tracker.decision(at: 100.1, changeCount: own + 1), .skip)
        tracker.recordRead(at: 100.05)
        XCTAssertEqual(tracker.decision(at: 110, changeCount: own + 1), .skip)
    }

    func testSettlingRestoresOnlyWhileTheClipboardIsStillOurs() {
        let tracker = tracker()
        XCTAssertEqual(tracker.settledDecision(changeCount: own), .restore)
        XCTAssertEqual(tracker.settledDecision(changeCount: own + 3), .skip)
    }
}

/// The service against a private, uniquely named pasteboard: never the general one.
@MainActor
final class ClipboardPasteServiceTests: XCTestCase {
    private struct Entry: Equatable {
        let type: String
        let data: Data
    }

    private let fast = ClipboardRestoreTimings(
        minimumHold: 0.05,
        quietPeriod: 0.05,
        noReadTimeout: 60,
        maximumWait: 120
    )

    private func contents(of pasteboard: NSPasteboard) -> [[Entry]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Entry(type: type.rawValue, data: $0) }
            }
        }
    }

    private func put(_ string: String, on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testOffersTheTranscriptWithHistoryMarkers() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)
        let service = ClipboardPasteService(pasteboard: pasteboard)

        var shortcutSent = false
        service.paste("Diktat") {
            shortcutSent = true
            let types = pasteboard.types ?? []
            for marker in ClipboardPasteService.historyMarkers {
                XCTAssertTrue(types.contains(marker), marker.rawValue)
            }
            XCTAssertTrue(types.contains(.string))
            XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        }
        XCTAssertTrue(shortcutSent)

        service.settleNow()
        XCTAssertEqual(pasteboard.string(forType: .string), "Vorher")
        XCTAssertFalse((pasteboard.types ?? []).contains(ClipboardPasteService.historyMarkers[0]))
    }

    func testRestoresEveryItemAndTypeExactly() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let custom = NSPasteboard.PasteboardType("app.blitztext.tests.custom")
        let text = NSPasteboardItem()
        text.setString("Hallo Welt", forType: .string)
        text.setData(Data("{\\rtf1 Hallo Welt}".utf8), forType: .rtf)
        text.setData(Data([0, 1, 2, 255]), forType: custom)
        let image = NSPasteboardItem()
        image.setData(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7, 7]), forType: .png)
        let file = NSPasteboardItem()
        file.setString("file:///tmp/blitztext-test.txt", forType: .fileURL)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([text, image, file]))
        let before = contents(of: pasteboard)
        XCTAssertEqual(before.count, 3)

        let service = ClipboardPasteService(pasteboard: pasteboard)
        service.paste("Diktat") {
            XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        }
        service.settleNow()

        XCTAssertEqual(contents(of: pasteboard), before)
    }

    func testEmptyClipboardComesBackEmpty() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        let service = ClipboardPasteService(pasteboard: pasteboard)
        service.paste("Diktat") {
            XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        }
        service.settleNow()

        XCTAssertTrue((pasteboard.pasteboardItems ?? []).isEmpty)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testNewerClipboardContentWins() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)

        let service = ClipboardPasteService(pasteboard: pasteboard)
        service.paste("Diktat") {}
        put("Neu kopiert", on: pasteboard)
        service.settleNow()

        XCTAssertEqual(pasteboard.string(forType: .string), "Neu kopiert")
    }

    func testNewPasteSettlesTheEarlierOneFirst() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)

        let service = ClipboardPasteService(pasteboard: pasteboard)
        service.paste("Erstes Diktat") {
            XCTAssertEqual(pasteboard.string(forType: .string), "Erstes Diktat")
        }
        service.paste("Zweites Diktat") {
            XCTAssertEqual(pasteboard.string(forType: .string), "Zweites Diktat")
        }
        service.settleNow()

        XCTAssertEqual(pasteboard.string(forType: .string), "Vorher")
    }

    func testKeepsTheTranscriptWhenThePreviousClipboardCannotBeRead() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        // Lists a type but never delivers data, like a clipboard Blitztext may not read.
        let promise = UnfulfilledPromise()
        let item = NSPasteboardItem()
        item.setDataProvider(promise, forTypes: [.string])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let service = ClipboardPasteService(pasteboard: pasteboard)
        service.paste("Diktat") {
            XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        }
        service.settleNow()

        XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        withExtendedLifetime(promise) {}
    }

    func testSettlingWithoutAPasteChangesNothing() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)
        let changeCount = pasteboard.changeCount

        ClipboardPasteService(pasteboard: pasteboard).settleNow()

        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "Vorher")
    }

    func testRestoresSoonAfterTheTargetReads() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)

        // The no-read timeout is a minute, so only the read can end the wait in time.
        let service = ClipboardPasteService(pasteboard: pasteboard, timings: fast)
        var ownChangeCount = 0
        service.paste("Diktat") {
            ownChangeCount = pasteboard.changeCount
            XCTAssertEqual(pasteboard.string(forType: .string), "Diktat")
        }

        let restored = await waitUntil { pasteboard.changeCount != ownChangeCount }
        XCTAssertTrue(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "Vorher")
        service.settleNow()
    }

    func testRestoresAfterTheTimeoutWhenNothingReads() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        put("Vorher", on: pasteboard)

        var timings = fast
        timings.noReadTimeout = 0.2
        let service = ClipboardPasteService(pasteboard: pasteboard, timings: timings)
        var ownChangeCount = 0
        service.paste("Diktat") {
            ownChangeCount = pasteboard.changeCount
        }

        // Only the change count is polled: reading the text would count as a read.
        let restored = await waitUntil { pasteboard.changeCount != ownChangeCount }
        XCTAssertTrue(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "Vorher")
        service.settleNow()
    }
}

/// A promise that never delivers its data.
private final class UnfulfilledPromise: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
}
