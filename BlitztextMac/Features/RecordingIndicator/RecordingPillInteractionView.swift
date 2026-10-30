import AppKit
import SwiftUI

/// Neither dragging nor opening the context menu should make Blitztext the typing target.
final class RecordingPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns mouse gestures above the SwiftUI buttons, whose accessibility actions remain.
/// AppKit mouse tracking separates a click from a drag before any stop action is sent.
final class RecordingPillInteractionView<Content: View>: NSHostingView<Content> {
    var session: () -> RecordingIndicatorSession? = { nil }
    var onClick: (RecordingIndicatorSession?) -> Void = { _ in }
    var onMove: (CGPoint) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    var onHide: (RecordingIndicatorSession?) -> Void = { _ in }
    var onResetPosition: () -> Void = {}

    private var drag = RecordingIndicatorDrag()
    private var pressedSession: RecordingIndicatorSession?
    private var menuSession: RecordingIndicatorSession?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), !isHidden else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        guard let window else { return }
        pressedSession = session()
        drag.begin(at: NSEvent.mouseLocation, origin: window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        drag.noteMovement(hypot(event.deltaX, event.deltaY))
        if let origin = drag.move(to: NSEvent.mouseLocation) { onMove(origin) }
    }

    override func mouseUp(with event: NSEvent) {
        if let origin = drag.move(to: NSEvent.mouseLocation) { onMove(origin) }
        let didDrag = drag.didDrag
        let isClick = drag.end()
        if didDrag { onDragEnd() }
        if isClick { onClick(pressedSession) }
        pressedSession = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        drag.cancel()
        pressedSession = nil
        menuSession = session()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title: String
        if case .meeting? = menuSession {
            title = "Für dieses Meeting ausblenden"
        } else {
            title = "Für dieses Diktat ausblenden"
        }
        let hide = NSMenuItem(title: title, action: #selector(hideSession), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = menuSession != nil
        menu.addItem(hide)
        let reset = NSMenuItem(title: "Position zurücksetzen", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func hideSession() { onHide(menuSession) }
    @objc private func resetPosition() { onResetPosition() }
}
