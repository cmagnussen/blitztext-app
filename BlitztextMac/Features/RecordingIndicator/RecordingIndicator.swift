import AppKit
import SwiftUI

/// A small pill at the bottom of the screen while Blitztext records or writes, so the
/// recording is visible wherever you type, not only in the menu bar. Lilac bars follow
/// the voice; while recording, a click stops it. During a meeting it shows the running
/// time, and a click opens the meeting page. The panel never takes the focus, so the text
/// still lands in the app you are typing in.
@MainActor
final class RecordingIndicatorController {
    private let appState: AppState
    private let model = RecordingIndicatorModel()
    private var panel: NSPanel?
    private var lastStatus: MenuBarStatus = .idle
    /// Counts show and hide transitions; a fade that finishes late only hides the
    /// panel if no newer transition happened meanwhile.
    private var transition = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func update(to status: MenuBarStatus) {
        lastStatus = status
        guard appState.appSettings.showsRecordingIndicator else {
            hide()
            return
        }
        switch status {
        case .recording:
            model.status = status
            // A new recording picks the screen you work on now.
            show(placing: panel?.isVisible != true || isHiding)
        case .processing:
            model.status = status
            show(placing: panel?.isVisible != true)
        case .success:
            guard panel?.isVisible == true, !isHiding else { return }
            model.status = status
            hide(after: .milliseconds(900))
        case .copied:
            // Longer than "Fertig": it says the text did not go where it was meant to.
            model.status = status
            show(placing: panel?.isVisible != true)
            hide(after: .milliseconds(2_600))
        case .meeting:
            // Back after a dictation in between, or a meeting just started.
            model.status = status
            show(placing: panel?.isVisible != true || isHiding)
        case .idle, .error:
            hide()
        }
    }

    /// The setting changed, possibly mid-recording: apply it right away.
    func settingChanged() {
        update(to: lastStatus)
    }

    private var isHiding = false

    private func show(placing: Bool) {
        transition += 1
        isHiding = false
        let panel = panel ?? makePanel()
        self.panel = panel
        if placing { place(panel) }
        panel.ignoresMouseEvents = !model.status.isRecording && model.status != .meeting
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide(after delay: Duration? = nil) {
        guard let panel, panel.isVisible else { return }
        transition += 1
        let current = transition
        isHiding = true
        panel.ignoresMouseEvents = true
        Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            guard let self, self.transition == current else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.transition == current else { return }
                    self.isHiding = false
                    panel.orderOut(nil)
                }
            }
        }
    }

    /// Bottom centre, above the Dock, of the screen with the pointer: on a Mac with
    /// several displays that is the one you are working on.
    private func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = RecordingPill.panelSize
        let frame = screen.visibleFrame
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.minY + 16, width: size.width, height: size.height),
            display: true
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: RecordingPill.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let appState = appState
        let hosting = FirstClickHostingView(rootView: RecordingPill(
            model: model,
            appState: appState,
            onStop: { appState.stopCurrentWorkflow() },
            onOpenMeeting: { appState.openMeeting() }
        ))
        // The pill has a fixed size; the panel never resizes with its content.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: RecordingPill.panelSize)
        panel.contentView = hosting
        return panel
    }
}

private extension MenuBarStatus {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

@Observable
@MainActor
final class RecordingIndicatorModel {
    var status: MenuBarStatus = .idle
}

/// Takes the first click, so the pill reacts without activating Blitztext.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The pill: night surface with lilac, the same in light and dark mode, so it reads on
/// any window behind it.
struct RecordingPill: View {
    let model: RecordingIndicatorModel
    let appState: AppState
    let onStop: () -> Void
    var onOpenMeeting: () -> Void = {}

    private static let lilac = BlackboatColor.hex(0xBB84DF)
    private static let night = BlackboatColor.hex(0x050722)
    /// The capsule plus room for its shadow.
    static let panelSize = CGSize(width: 180, height: 72)

    var body: some View {
        Group {
            switch model.status {
            case .recording:
                Button(action: onStop) {
                    capsule
                }
                .buttonStyle(.plain)
                .help("Klicken stoppt die Aufnahme")
            case .meeting:
                // Opens the meeting page instead of stopping: ending a meeting by a stray click would hurt.
                Button(action: onOpenMeeting) {
                    capsule
                }
                .buttonStyle(.plain)
                .help("Meeting l\u{00E4}uft. Klicken \u{00F6}ffnet die Meeting-Seite.")
            default:
                capsule
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            content
        }
        .frame(width: 148, height: 40)
        .background {
            Capsule().fill(Self.night.opacity(0.94))
            Capsule().strokeBorder(Self.lilac.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .padding(16)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .recording(let type):
            Image(systemName: type.icon)
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.85))
            VoiceBars(level: appState.activeWorkflow?.audioLevel ?? 0, color: Self.lilac)
            Image(systemName: "stop.fill")
                .font(.ui(7, .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.14)))
        case .processing:
            TypingIndicator(color: .clear, dotColor: Self.lilac, size: 34)
                .frame(width: 30, height: 20)
            Text("Schreibt")
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .success:
            Image(systemName: "checkmark")
                .font(.ui(12, .bold))
                .foregroundStyle(Self.lilac)
            Text("Fertig")
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .copied:
            Image(systemName: "doc.on.clipboard")
                .font(.ui(11, .bold))
                .foregroundStyle(Self.lilac)
            Text("Zwischenablage")
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .meeting:
            MeetingPillContent(meeting: appState.meeting, lilac: Self.lilac)
        case .idle, .error:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch model.status {
        case .recording: return "Aufnahme l\u{00E4}uft. Klicken stoppt sie."
        case .processing: return "Blitztext schreibt"
        case .success: return "Fertig"
        case .copied: return "Nicht eingef\u{00FC}gt, der Text liegt in der Zwischenablage"
        case .meeting: return "Meeting wird aufgenommen. Klicken \u{00F6}ffnet die Meeting-Seite."
        case .idle, .error: return ""
        }
    }
}

/// A running meeting: a pulsing red dot and the recorded time, or "Pausiert".
private struct MeetingPillContent: View {
    let meeting: MeetingController
    let lilac: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if case .recording(let startedAt) = meeting.phase {
            if meeting.pausedAt != nil {
                Image(systemName: "pause.fill")
                    .font(.ui(10, .bold))
                    .foregroundStyle(lilac)
                Text("Pausiert")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let pulse = reduceMotion ? 1 : 0.55 + 0.45 * abs(cos(context.date.timeIntervalSince(startedAt) * .pi / 2))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: .systemRed))
                            .frame(width: 8, height: 8)
                            .opacity(pulse)
                            .animation(.easeInOut(duration: 0.9), value: pulse)
                        Text("Meeting")
                            .font(.ui(12, .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(MeetingView.clock(context.date.timeIntervalSince(startedAt)))
                            .font(.ui(12, .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    // "1:02:34" after an hour still fits the capsule.
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
            }
        }
    }
}

/// Seven bars that rise with the input level and keep a soft motion of their own, so
/// the pill breathes even in a quiet moment.
private struct VoiceBars: View {
    let level: Float
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    let shape = 0.55 + 0.45 * sin(Double(index + 1) / 8 * .pi)
                    let wobble = 0.5 + 0.5 * sin(time * 7 + Double(index) * 0.9)
                    let voice = min(1, Double(level) * 1.6)
                    let height = 4 + 16 * shape * (0.25 * wobble + voice * (0.6 + 0.4 * wobble))
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 22)
        }
    }
}
