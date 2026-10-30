import XCTest

final class RecordingIndicatorInteractionTests: XCTestCase {
    func testHiddenDictationStaysHiddenThroughProcessingAndCompletion() {
        let id = UUID()
        var state = RecordingIndicatorVisibility()
        state.synchronize(dictation: id, meeting: nil)
        state.hide(.dictation(id))
        for _ in 0..<5 {
            state.synchronize(dictation: id, meeting: nil)
            XCTAssertTrue(state.isHidden(.dictation(id)))
        }
    }

    func testNextDictationIsVisibleEvenInTheSameMode() {
        let previous = UUID(), next = UUID()
        var state = RecordingIndicatorVisibility()
        state.hide(.dictation(previous))
        state.synchronize(dictation: next, meeting: nil)
        XCTAssertFalse(state.isHidden(.dictation(next)))
        XCTAssertFalse(state.isHidden(.dictation(previous)))
    }

    func testHiddenMeetingSurvivesNestedDictationAndPauseUpdates() {
        let meeting = UUID(), dictation = UUID()
        var state = RecordingIndicatorVisibility()
        state.synchronize(dictation: nil, meeting: meeting)
        state.hide(.meeting(meeting))
        state.synchronize(dictation: dictation, meeting: meeting)
        XCTAssertTrue(state.isHidden(.meeting(meeting)))
        XCTAssertFalse(state.isHidden(.dictation(dictation)))
        state.synchronize(dictation: nil, meeting: meeting)
        state.synchronize(dictation: nil, meeting: meeting)
        XCTAssertTrue(state.isHidden(.meeting(meeting)))
    }

    func testHidingDictationDoesNotHideMeeting() {
        let meeting = UUID(), dictation = UUID()
        var state = RecordingIndicatorVisibility()
        state.synchronize(dictation: dictation, meeting: meeting)
        state.hide(.dictation(dictation))
        XCTAssertFalse(state.isHidden(.meeting(meeting)))
        state.synchronize(dictation: nil, meeting: meeting)
        XCTAssertFalse(state.isHidden(.meeting(meeting)))
    }

    func testMeetingEndingDuringDictationDoesNotHideTheNextMeeting() {
        let meeting = UUID(), dictation = UUID(), nextMeeting = UUID()
        var state = RecordingIndicatorVisibility()
        state.synchronize(dictation: dictation, meeting: meeting)
        state.hide(.meeting(meeting))
        state.hide(.dictation(dictation))
        state.synchronize(dictation: dictation, meeting: nil)
        XCTAssertTrue(state.isHidden(.dictation(dictation)))
        XCTAssertFalse(state.isHidden(.meeting(meeting)))
        state.synchronize(dictation: nil, meeting: nextMeeting)
        XCTAssertFalse(state.isHidden(.meeting(nextMeeting)))
    }

    func testIdlePrunesHiddenSessions() {
        let id = UUID()
        var state = RecordingIndicatorVisibility()
        state.hide(.dictation(id))
        state.synchronize(dictation: nil, meeting: nil)
        XCTAssertFalse(state.isHidden(.dictation(id)))
        XCTAssertFalse(state.isHidden(nil))
    }

    func testPointerJitterIsStillAClick() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: CGPoint(x: 20, y: 30), origin: CGPoint(x: 500, y: 100))
        XCTAssertNil(drag.move(to: CGPoint(x: 22, y: 31)))
        XCTAssertTrue(drag.end())
        XCTAssertFalse(drag.end())
    }

    func testDraggingMovesFromInitialWindowOriginAndNeverClicks() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: CGPoint(x: 20, y: 30), origin: CGPoint(x: 500, y: 100))
        XCTAssertEqual(drag.move(to: CGPoint(x: 30, y: 55)), CGPoint(x: 510, y: 125))
        XCTAssertEqual(drag.move(to: CGPoint(x: 40, y: 65)), CGPoint(x: 520, y: 135))
        XCTAssertFalse(drag.end())
    }

    func testDraggingBackToStartDoesNotStopRecording() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: .zero, origin: CGPoint(x: 500, y: 100))
        XCTAssertNotNil(drag.move(to: CGPoint(x: 4, y: 0)))
        XCTAssertNotNil(drag.move(to: .zero))
        XCTAssertFalse(drag.end())
    }

    func testReleaseMovementWithoutAnIntermediateDragEventDoesNotClick() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: .zero, origin: .zero)
        XCTAssertNotNil(drag.move(to: CGPoint(x: 5, y: 0)))
        XCTAssertFalse(drag.end())
    }

    func testCancelledGestureCannotClickAndNewGestureStartsCleanly() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: .zero, origin: .zero)
        drag.cancel()
        XCTAssertNil(drag.move(to: CGPoint(x: 10, y: 10)))
        XCTAssertFalse(drag.end())
        drag.begin(at: .zero, origin: .zero)
        XCTAssertTrue(drag.end())
    }

    /// Events that queued while the main thread was busy can all see the final live
    /// pointer; their own movement still makes the gesture a drag, never a stop click.
    func testQueuedDragMovementIsNeverAClick() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: CGPoint(x: 100, y: 100), origin: .zero)
        drag.noteMovement(12)
        _ = drag.move(to: CGPoint(x: 100, y: 100))
        XCTAssertTrue(drag.didDrag)
        XCTAssertFalse(drag.end())
    }

    func testSmallEventMovementIsStillAClick() {
        var drag = RecordingIndicatorDrag()
        drag.begin(at: CGPoint(x: 100, y: 100), origin: .zero)
        drag.noteMovement(1)
        drag.noteMovement(1)
        XCTAssertTrue(drag.end())
    }

    func testClampHandlesScreensWithNegativeCoordinates() {
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1000)
        let size = CGSize(width: 180, height: 72)
        let point = RecordingIndicatorPlacement.clamp(CGPoint(x: 500, y: -1000), size: size, to: frame)
        XCTAssertEqual(point, CGPoint(x: -180, y: -200))
        XCTAssertTrue(frame.contains(CGRect(origin: point, size: size)))
    }

    func testSavedPositionAdaptsToResolutionAndVisibleFrameChanges() {
        let size = CGSize(width: 180, height: 72)
        let oldFrame = CGRect(x: 0, y: 25, width: 1920, height: 1000)
        let saved = RecordingIndicatorPlacement.save(
            origin: CGPoint(x: 870, y: 489), size: size, in: oldFrame
        )
        let newFrame = CGRect(x: 0, y: 80, width: 1280, height: 700)
        let restored = RecordingIndicatorPlacement.restore(saved, size: size, in: newFrame)
        XCTAssertEqual(restored, CGPoint(x: 550, y: 394))
        XCTAssertTrue(newFrame.contains(CGRect(origin: restored, size: size)))
    }

    func testRemovedMonitorPositionCanBeRestoredOnAnotherScreen() {
        let size = CGSize(width: 180, height: 72)
        let saved = RecordingIndicatorPlacement.Saved(x: 1, y: 1)
        let fallback = CGRect(x: -1440, y: 0, width: 1440, height: 850)
        let origin = RecordingIndicatorPlacement.restore(saved, size: size, in: fallback)
        XCTAssertEqual(origin, CGPoint(x: -180, y: 778))
        XCTAssertTrue(fallback.contains(CGRect(origin: origin, size: size)))
    }

    func testInvalidRatiosAndVerySmallFramesHaveFiniteOrigins() {
        let size = CGSize(width: 180, height: 72)
        let origin = RecordingIndicatorPlacement.restore(
            .init(x: .nan, y: .infinity), size: size,
            in: CGRect(x: 10, y: 20, width: 100, height: 50)
        )
        XCTAssertEqual(origin, CGPoint(x: 10, y: 20))
    }
}
