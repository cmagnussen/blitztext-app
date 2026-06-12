import AppKit
import ApplicationServices
import SwiftUI

/// Zeigt während Aufnahme und Verarbeitung ein kleines animiertes Overlay
/// an der Text-Cursor-Position der aktiven App, ähnlich der macOS-Diktierfunktion.
/// Aufnahme: pulsierender roter Punkt mit Mikrofon. Verarbeitung: rotierender oranger Ring.
@MainActor
final class CaretActivityOverlayController {
    enum Phase: Equatable {
        case recording
        case processing
    }

    fileprivate static let overlaySize = NSSize(width: 28, height: 28)

    /// Kurzes AX-Timeout, damit eine eingefrorene Ziel-App den Main-Thread
    /// nicht für den Standard-Timeout (~6 s) blockiert.
    private static let axMessagingTimeout: Float = 0.25

    private var panel: NSPanel?
    private let model = CaretOverlayModel()

    func update(to status: MenuBarStatus) {
        switch status {
        case .recording:
            show(.recording)
        case .processing:
            show(.processing)
        case .idle, .success, .error:
            hide()
        }
    }

    private func show(_ phase: Phase) {
        let wasVisible = panel != nil
        model.phase = phase
        guard !wasVisible else { return }

        let panel = makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: CaretOverlayView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: Self.overlaySize)
        panel.contentView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        var origin: NSPoint

        if let caret = caretScreenRect() {
            origin = NSPoint(x: caret.midX - size.width / 2, y: caret.maxY + 4)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x + 14, y: mouse.y + 14)
        }

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: origin.x + size.width / 2, y: origin.y))
        } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }

        panel.setFrameOrigin(origin)
    }

    /// Position des Text-Cursors der fokussierten App in Cocoa-Bildschirmkoordinaten.
    /// Braucht die Bedienungshilfen-Freigabe; nicht jede App liefert Caret-Bounds.
    private func caretScreenRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.axMessagingTimeout)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue as! AXValue,
            &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var topLeftRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &topLeftRect),
              topLeftRect != .zero else {
            return nil
        }

        // AX liefert Koordinaten mit Ursprung oben links; Cocoa erwartet unten links.
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(
            x: topLeftRect.origin.x,
            y: primary.frame.maxY - topLeftRect.origin.y - topLeftRect.height,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }
}

@Observable
private final class CaretOverlayModel {
    var phase: CaretActivityOverlayController.Phase = .recording
}

private struct CaretOverlayView: View {
    let model: CaretOverlayModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .recording:
                RecordingDotView()
            case .processing:
                ProcessingRingView()
            }
        }
        .frame(
            width: CaretActivityOverlayController.overlaySize.width,
            height: CaretActivityOverlayController.overlaySize.height
        )
    }
}

private struct RecordingDotView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
                .frame(width: 24, height: 24)
                .scaleEffect(pulsing ? 1.0 : 0.6)
                .opacity(pulsing ? 0.2 : 0.7)

            Circle()
                .fill(Color.red)
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.0 : 0.88)

            Image(systemName: "mic.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

private struct ProcessingRingView: View {
    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                .frame(width: 18, height: 18)

            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}
