import Foundation

/// A meeting and a dictation running inside it have independent visibility.
enum RecordingIndicatorSession: Hashable {
    case dictation(UUID)
    case meeting(UUID)
}

struct RecordingIndicatorVisibility {
    private var hidden: Set<RecordingIndicatorSession> = []

    mutating func synchronize(dictation: UUID?, meeting: UUID?) {
        var live: Set<RecordingIndicatorSession> = []
        if let dictation { live.insert(.dictation(dictation)) }
        if let meeting { live.insert(.meeting(meeting)) }
        hidden.formIntersection(live)
    }

    mutating func hide(_ session: RecordingIndicatorSession) { hidden.insert(session) }

    func isHidden(_ session: RecordingIndicatorSession?) -> Bool {
        session.map { hidden.contains($0) } ?? false
    }
}

/// Once a gesture crossed the drag threshold, returning to its start is still a drag.
struct RecordingIndicatorDrag {
    private var start: CGPoint?
    private var origin: CGPoint = .zero
    private var movement: CGFloat = 0
    private(set) var didDrag = false
    static let threshold: CGFloat = 4

    mutating func begin(at point: CGPoint, origin: CGPoint) {
        start = point
        self.origin = origin
        movement = 0
        didDrag = false
    }

    /// Movement an event reports itself. A drag that queued up while the main thread was
    /// busy is still a drag, even if the live pointer is back where it started.
    mutating func noteMovement(_ distance: CGFloat) {
        guard start != nil else { return }
        movement += distance
        if movement >= Self.threshold { didDrag = true }
    }

    mutating func move(to point: CGPoint) -> CGPoint? {
        guard let start else { return nil }
        let dx = point.x - start.x, dy = point.y - start.y
        if hypot(dx, dy) >= Self.threshold { didDrag = true }
        guard didDrag else { return nil }
        return CGPoint(x: origin.x + dx, y: origin.y + dy)
    }

    mutating func end() -> Bool {
        let isClick = start != nil && !didDrag
        cancel()
        return isClick
    }

    mutating func cancel() {
        start = nil
        movement = 0
        didDrag = false
    }
}

enum RecordingIndicatorPlacement {
    /// Where the pill sits within a screen's visible frame, 0...1 on each axis. Applied to
    /// the screen with the pointer, so the pill keeps following the screen you work on.
    struct Saved: Codable, Equatable {
        let x: Double
        let y: Double
    }

    static func clamp(_ origin: CGPoint, size: CGSize, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - size.width)),
            y: min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - size.height))
        )
    }

    static func save(origin: CGPoint, size: CGSize, in frame: CGRect) -> Saved {
        let origin = clamp(origin, size: size, to: frame)
        return Saved(
            x: Double((origin.x - frame.minX) / max(1, frame.width - size.width)),
            y: Double((origin.y - frame.minY) / max(1, frame.height - size.height))
        )
    }

    static func restore(_ saved: Saved, size: CGSize, in frame: CGRect) -> CGPoint {
        let x = saved.x.isFinite ? min(max(saved.x, 0), 1) : 0.5
        let y = saved.y.isFinite ? min(max(saved.y, 0), 1) : 0
        return clamp(CGPoint(
            x: frame.minX + CGFloat(x) * max(0, frame.width - size.width),
            y: frame.minY + CGFloat(y) * max(0, frame.height - size.height)
        ), size: size, to: frame)
    }
}
