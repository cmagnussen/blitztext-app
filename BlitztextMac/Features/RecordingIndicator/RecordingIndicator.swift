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
    private var visibility = RecordingIndicatorVisibility()
    private var currentSession: RecordingIndicatorSession?
    // Retain the previous instance until synchronization, so object addresses cannot
    // be reused while a hidden session still refers to it.
    private var dictationWorkflow: (any Workflow)?
    private var dictationID: UUID?
    private static let placementKey = "BlitztextRecordingPillPlacement"
    private var savedPlacement: RecordingIndicatorPlacement.Saved?
    private var screenObserver: NSObjectProtocol?
    /// Counts show and hide transitions; a fade that finishes late only hides the
    /// panel if no newer transition happened meanwhile.
    private var transition = 0

    init(appState: AppState) {
        self.appState = appState
        if let data = UserDefaults.standard.data(forKey: Self.placementKey) {
            savedPlacement = try? JSONDecoder().decode(RecordingIndicatorPlacement.Saved.self, from: data)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.place(panel)
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// A new dictation can start with the same status as the one it replaces; without this
    /// it would inherit that one's "hidden for this dictation".
    func activeWorkflowChanged() {
        update(to: lastStatus)
    }

    func update(to status: MenuBarStatus) {
        lastStatus = status
        synchronizeSession(for: status)
        if visibility.isHidden(currentSession) {
            hideImmediately()
            return
        }
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
        // Processing remains interactive for dragging and the hide context menu.
        // A plain click is still a no-op unless recording or showing a meeting.
        panel.ignoresMouseEvents = false
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
        Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            guard let self, self.transition == current else { return }
            panel.ignoresMouseEvents = true
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

    private func synchronizeSession(for status: MenuBarStatus) {
        if let workflow = appState.activeWorkflow {
            if dictationWorkflow !== workflow {
                dictationID = UUID()
                dictationWorkflow = workflow
            }
        } else {
            dictationWorkflow = nil
            dictationID = nil
        }
        let meetingID = appState.meeting.recordingID
        visibility.synchronize(dictation: dictationID, meeting: meetingID)
        switch status {
        case .recording, .processing, .success, .copied:
            currentSession = dictationID.map(RecordingIndicatorSession.dictation)
        case .meeting:
            currentSession = meetingID.map(RecordingIndicatorSession.meeting)
        case .idle, .error:
            currentSession = nil
        }
    }

    private func hideSession(_ session: RecordingIndicatorSession?) {
        // A menu can outlive its recording; do not hide a newer session by accident.
        guard let session, session == currentSession else { return }
        visibility.hide(session)
        hideImmediately()
    }

    private func hideImmediately() {
        transition += 1
        isHiding = false
        panel?.ignoresMouseEvents = true
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    private func clicked(_ session: RecordingIndicatorSession?) {
        guard let session, session == currentSession else { return }
        switch lastStatus {
        case .recording where appState.activeWorkflow?.isRecording == true:
            appState.stopCurrentWorkflow()
        case .meeting where appState.meeting.isRecording:
            appState.openMeeting()
        default:
            break
        }
    }

    private func pointerScreen() -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// On the screen with the pointer, the one you work on: at the position you dragged the
    /// pill to, otherwise bottom centre above the Dock.
    private func place(_ panel: NSPanel) {
        guard let screen = pointerScreen() else { return }
        let size = RecordingPill.panelSize
        let frame = screen.visibleFrame
        let origin = savedPlacement.map { RecordingIndicatorPlacement.restore($0, size: size, in: frame) }
            ?? RecordingIndicatorPlacement.clamp(
                CGPoint(x: frame.midX - size.width / 2, y: frame.minY + 16), size: size, to: frame
            )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func move(to origin: CGPoint) {
        guard let panel, let screen = pointerScreen() else { return }
        panel.setFrameOrigin(RecordingIndicatorPlacement.clamp(origin, size: panel.frame.size, to: screen.visibleFrame))
    }

    private func rememberPosition() {
        guard let panel else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? pointerScreen() else { return }
        let saved = RecordingIndicatorPlacement.save(origin: panel.frame.origin, size: panel.frame.size, in: screen.visibleFrame)
        savedPlacement = saved
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.placementKey)
        }
    }

    private func resetPosition() {
        savedPlacement = nil
        UserDefaults.standard.removeObject(forKey: Self.placementKey)
        if let panel { place(panel) }
    }

    private func makePanel() -> NSPanel {
        let panel = RecordingPillPanel(
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
        let hosting = RecordingPillInteractionView(rootView: RecordingPill(
            model: model,
            appState: appState,
            onStop: { appState.stopCurrentWorkflow() },
            onOpenMeeting: { appState.openMeeting() }
        ))
        hosting.session = { [weak self] in self?.currentSession }
        hosting.onClick = { [weak self] in self?.clicked($0) }
        hosting.onMove = { [weak self] in self?.move(to: $0) }
        hosting.onDragEnd = { [weak self] in self?.rememberPosition() }
        hosting.onHide = { [weak self] in self?.hideSession($0) }
        hosting.onResetPosition = { [weak self] in self?.resetPosition() }
        hosting.toolTip = "Ziehen verschiebt die Anzeige. Rechtsklick bietet Ausblenden und Position zurücksetzen."
        // The pill has a fixed size; the panel never resizes with its content.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: RecordingPill.panelSize)
        panel.contentView = hosting
        return panel
    }
}

@Observable
@MainActor
final class RecordingIndicatorModel {
    var status: MenuBarStatus = .idle
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
            // No SwiftUI buttons: they still saw the mouse under `RecordingPillInteractionView`
            // and stopped the recording when a drag ended on the pill. Clicks come from that
            // view, which tells them from drags; VoiceOver gets the same actions here.
            switch model.status {
            case .recording:
                capsule
                    .help("Klicken stoppt die Aufnahme. Ziehen verschiebt die Anzeige; Rechtsklick blendet sie für dieses Diktat aus.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, onStop)
            case .meeting:
                // Opens the meeting page instead of stopping: ending a meeting by a stray click would hurt.
                capsule
                    .help("Meeting l\u{00E4}uft. Klicken \u{00F6}ffnet die Meeting-Seite.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, onOpenMeeting)
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
