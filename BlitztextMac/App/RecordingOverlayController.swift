import AppKit
import OSLog
import SwiftUI

private let recordingOverlayLogger = Logger(
    subsystem: "app.blitztext.mac",
    category: "RecordingOverlay"
)

private final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class RecordingOverlayController {
    private let panel: RecordingOverlayPanel
    private let hostingController: NSHostingController<RecordingOverlayView>
    private var hideTask: Task<Void, Never>?
    private var activeSpaceObserver: NSObjectProtocol?
    private var state: RecordingOverlayState = .recording
    private var showsStopButton = false
    private var isPresented = false
    var onStopRecording: (() -> Void)?

    init() {
        let hostingController = NSHostingController(
            rootView: RecordingOverlayView(
                state: .recording,
                showsStopButton: false,
                onStopRecording: {}
            )
        )
        let panel = RecordingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 82, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = hostingController
        self.panel = panel
        self.hostingController = hostingController

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Let AppKit finish the Space transition before reordering the HUD.
                await Task.yield()
                self?.refreshForActiveSpace()
            }
        }
    }

    deinit {
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
    }

    func update(to status: MenuBarStatus, allowsStopping: Bool = false) {
        hideTask?.cancel()

        switch status {
        case .recording:
            state = .recording
            showsStopButton = allowsStopping
            recordingOverlayLogger.info(
                "Showing recording overlay; stop button: \(allowsStopping, privacy: .public)"
            )
            show()
        case .processing:
            state = .processing
            showsStopButton = false
            recordingOverlayLogger.info("Showing processing overlay")
            show()
        case .success:
            recordingOverlayLogger.info("Hiding overlay after success")
            hide()
        case .error:
            state = .error
            showsStopButton = false
            show()
            scheduleHide(after: .seconds(3))
        case .idle:
            hide()
        }
    }

    func showPastePermissionWarning() {
        hideTask?.cancel()
        showsStopButton = false
        state = .pastePermission
        show()
        scheduleHide(after: .seconds(4))
    }

    private func show() {
        isPresented = true
        hostingController.rootView = RecordingOverlayView(
            state: state,
            showsStopButton: showsStopButton,
            onStopRecording: { [weak self] in
                recordingOverlayLogger.info("Stop button pressed")
                self?.onStopRecording?()
            }
        )
        panel.setContentSize(panelSize)
        hostingController.view.frame = NSRect(origin: .zero, size: panelSize)
        panel.ignoresMouseEvents = !showsStopButton
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() {
        isPresented = false
        panel.orderOut(nil)
    }

    private func refreshForActiveSpace() {
        guard isPresented else { return }

        recordingOverlayLogger.info("Refreshing overlay for active Space")
        panel.orderOut(nil)
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func scheduleHide(after duration: Duration) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
    }

    var panelSize: NSSize {
        guard state == .recording else { return state.panelSize }
        return NSSize(width: showsStopButton ? 96 : 68, height: 36)
    }
}

private enum RecordingOverlayState: Equatable {
    case recording
    case processing
    case error
    case pastePermission

    var panelSize: NSSize {
        switch self {
        case .recording:
            return NSSize(width: 68, height: 36)
        case .processing:
            return NSSize(width: 58, height: 34)
        case .error:
            return NSSize(width: 174, height: 38)
        case .pastePermission:
            return NSSize(width: 190, height: 38)
        }
    }

    var errorTitle: String? {
        switch self {
        case .error:
            return "Vorgang fehlgeschlagen"
        case .pastePermission:
            return "Einfügen fehlgeschlagen"
        case .recording, .processing:
            return nil
        }
    }
}

private struct RecordingOverlayView: View {
    let state: RecordingOverlayState
    let showsStopButton: Bool
    let onStopRecording: () -> Void

    private var panelSize: NSSize {
        guard state == .recording else { return state.panelSize }
        return NSSize(width: showsStopButton ? 96 : 68, height: 36)
    }

    var body: some View {
        Group {
            switch state {
            case .recording:
                HStack(spacing: 8) {
                    RecordingWaveform()

                    if showsStopButton {
                        Button {
                            onStopRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))

                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.primary.opacity(0.82))
                                    .frame(width: 7, height: 7)
                            }
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Aufnahme stoppen")
                        .accessibilityLabel("Aufnahme stoppen")
                    }
                }
                .padding(.horizontal, showsStopButton ? 8 : 13)
            case .processing:
                ProcessingIndicator()
            case .error, .pastePermission:
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(state.errorTitle ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(
            width: panelSize.width,
            height: panelSize.height
        )
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
        )
    }
}

private struct RecordingWaveform: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.055)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<9, id: \.self) { index in
                    let distanceFromCenter = abs(Double(index) - 4)
                    let envelope = 1 - distanceFromCenter * 0.075
                    let primaryWave = abs(sin(time * 6.2 + Double(index) * 0.76))
                    let secondaryWave = abs(cos(time * 3.7 - Double(index) * 0.43))

                    Capsule()
                        .fill(Color.primary.opacity(0.82))
                        .frame(
                            width: 2.5,
                            height: 4 + ((primaryWave * 12 + secondaryWave * 3) * envelope)
                        )
                }
            }
            .frame(width: 43, height: 24)
            .accessibilityLabel("Aufnahme läuft")
        }
    }
}

private struct ProcessingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.035)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = Angle.degrees(time.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 2.5)

                Circle()
                    .trim(from: 0.05, to: 0.34)
                    .stroke(
                        Color.secondary.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(rotation)
            }
            .frame(width: 16, height: 16)
            .accessibilityLabel("Wird verarbeitet")
        }
    }
}
