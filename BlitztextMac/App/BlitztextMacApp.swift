import SwiftUI
import UniformTypeIdentifiers

@main
struct BlitztextMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let menuBarStatusController = MenuBarStatusController()
    let appState = AppState()
    private lazy var recordingIndicator = RecordingIndicatorController(appState: appState)
    /// Files opened before launch finished (e.g. "Open With" on a closed app).
    private var pendingAudioFile: URL?
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let folder = MacSnapshots.folder {
            NSApp.setActivationPolicy(.prohibited)
            MacSnapshots.render(appState: appState, to: folder)
            NSApp.terminate(nil)
            return
        }
        #endif
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            menuBarStatusController.attach(to: button)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: MenuBarView.width, height: 480)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = GlassPopoverHostingController(
            rootView: MenuBarView(appState: appState),
            width: MenuBarView.width
        )

        NSApp.setActivationPolicy(.accessory)

        // Hotkey events
        appState.hotkeyService.onHotkeyEvent = { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        appState.onMenuBarStatusChange = { [weak self] status in
            self?.menuBarStatusController.update(to: status)
            self?.recordingIndicator.update(to: status)
        }
        appState.onRecordingIndicatorSettingChange = { [weak self] in
            self?.recordingIndicator.settingChanged()
        }
        appState.onWhatsNewChange = { [weak self] unseen in
            self?.menuBarStatusController.showsNewBadge = unseen
        }
        menuBarStatusController.showsNewBadge = appState.hasUnseenWhatsNew
        appState.hotkeyService.start()
        appState.appUpdateService.startIfConfigured()

        // Listen for popover dismiss requests (from auto-paste)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissPopover),
            name: .dismissPopover,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showWhatsNew),
            name: .showWhatsNew,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showWhatsNew),
            name: .showPopover,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chooseAudioFile),
            name: .chooseAudioFile,
            object: nil
        )

        didFinishLaunching = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let url = self.pendingAudioFile {
                self.pendingAudioFile = nil
                self.transcribeAudioFile(url)
            } else {
                self.showOnboardingIfNeeded()
            }
        }
    }

    // MARK: - Audio files

    /// Finder "Open With", dragging onto the app icon, or `open -a Blitztext file.ogg`.
    func applicationWillTerminate(_ notification: Notification) {
        appState.restoreAudioOutput()
        // Quitting right after a dictation still gives the previous clipboard back.
        ClipboardPasteService.shared.settleNow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: Self.isAudioFile) else { return }
        guard didFinishLaunching else {
            pendingAudioFile = url
            return
        }
        transcribeAudioFile(url)
    }

    @objc private func chooseAudioFile() {
        // A transient popover would close under the panel anyway; reopen it with the result.
        popover.performClose(nil)
        appState.isPopoverShown = false
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Audiodatei transkribieren"
        panel.message = "Sprachmemo, WhatsApp-Sprachnachricht oder andere Audiodatei w\u{00E4}hlen"
        panel.prompt = "Transkribieren"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribeAudioFile(url)
    }

    private func transcribeAudioFile(_ url: URL) {
        appState.audioFile.transcribe(url, appState: appState)
        appState.page = .audioFile
        showPopover()
    }

    private static func isAudioFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return ["ogg", "opus", "oga", "m4a", "mp3", "wav", "aiff", "caf", "aac"].contains(url.pathExtension.lowercased())
        }
        return type.conforms(to: .audio)
    }

    @objc private func showWhatsNew() {
        guard !popover.isShown else { return }
        appState.prepareForPopoverPresentation()
        showPopover()
    }

    @objc private func handleDismissPopover() {
        appState.isPopoverShown = false
        popover.performClose(nil)
    }

    /// Mode chosen at key down per shortcut, so key up (hold mode) stops the same workflow.
    private var shortcutModes: [WorkflowType: WorkflowType] = [:]

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .down(let shortcut):
            let mode: WorkflowType
            if let previous = shortcutModes[shortcut],
               let active = appState.activeWorkflow,
               active.type == previous,
               active.phase.isActive {
                // Second press in "Drücken" mode stops what the first press started,
                // even though Blitztext itself is frontmost by now.
                mode = previous
            } else {
                mode = appState.modeForShortcut(
                    shortcut,
                    frontmostApp: NSWorkspace.shared.frontmostApplication
                )
            }
            shortcutModes[shortcut] = mode
            handleHotkeyDown(mode)
        case .up(let shortcut):
            handleHotkeyUp(shortcutModes[shortcut] ?? shortcut)
        }
    }

    private func handleHotkeyDown(_ type: WorkflowType) {
        // In toggle mode, any workflow shortcut finishes the current recording.
        // Do this before checking the requested mode: it may not be configured.
        if appState.appSettings.hotkeyMode == .toggle,
           let active = appState.activeWorkflow,
           case .running = active.phase {
            if active.isRecording {
                active.stop()
            }
            // A second stop during transcription would cancel its result.
            return
        }

        guard appState.isWorkflowAvailable(type) else {
            // Missing model or AI setup: say so instead of silently ignoring the shortcut.
            guard !popover.isShown else { return }
            appState.prepareForPopoverPresentation()
            if appState.page != .whatsNew {
                appState.page = .main
            }
            showPopover()
            return
        }

        let mode = appState.appSettings.hotkeyMode

        switch mode {
        case .hold:
            // Hold mode: start recording on key down
            appState.startWorkflow(type, source: .hotkeyBackground)

        case .toggle:
            appState.prepareForPopoverPresentation()
            appState.startWorkflow(type, source: .manual)
            showPopover()
        }
    }

    private func handleHotkeyUp(_ type: WorkflowType) {
        let mode = appState.appSettings.hotkeyMode

        guard mode == .hold else { return }

        // Hold mode: stop recording on key release
        if let active = appState.activeWorkflow,
           active.type == type {
            // Only stop if currently recording (running phase)
            if case .running = active.phase {
                active.stop()
            }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            appState.isPopoverShown = false
        } else {
            appState.prepareForPopoverPresentation()
            showPopover()
        }
    }

    private func showOnboardingIfNeeded() {
        guard appState.shouldShowOnboarding else { return }
        appState.prepareForPopoverPresentation()
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        appState.isPopoverShown = true
        NSApp.activate(ignoringOtherApps: true)

        // Transparent window so the HUD material shows through, as in _Space.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.popover.contentViewController?.view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            appState.isPopoverShown = false
            switch appState.currentPhase {
            case .done, .error:
                appState.resetCurrentWorkflow()
            default:
                // Keep a running file transcription visible for the next opening.
                if appState.page == .audioFile, appState.audioFile.isWorking { break }
                appState.page = .main
            }
        }
    }
}

#if DEBUG
/// Design reviews: `-BlitztextSnapshotDir /path` renders the popover pages, the settings
/// panes and the recording pill to PNG files, light and dark, and quits. No status item,
/// no hotkeys, nothing is recorded. Not compiled into Release builds.
@MainActor
enum MacSnapshots {
    static var folder: URL? {
        UserDefaults.standard.string(forKey: "BlitztextSnapshotDir").map { URL(fileURLWithPath: $0) }
    }

    static func render(appState: AppState, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // As on a set-up Mac: the unsigned snapshot binary has no Accessibility grant.
        appState.accessibilityPermissionGranted = true
        for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let appearance = NSAppearance(named: name)
            NSApp.appearance = appearance

            for (page, label) in [(PopoverPage.main, "main"), (.onboarding, "onboarding"), (.history, "history")] {
                appState.page = page
                capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-\(label).png"))
            }
            for pane in SettingsPane.allCases {
                SettingsContentView.debugInitialPane = pane
                appState.page = .settings
                capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-popover-settings-\(pane.rawValue).png"))
                let view = SettingsContentView(appState: appState)
                    .frame(width: MenuBarView.width, height: 1400, alignment: .top)
                    .background(BlitztextTheme.page)
                capture(view, appearance: appearance, to: folder.appendingPathComponent("\(mode)-settings-\(pane.rawValue).png"))
            }
            for (status, label) in [(MenuBarStatus.recording(.tapTalk), "recording"), (.processing(.tapTalk), "processing"), (.success(.tapTalk), "success")] {
                let model = RecordingIndicatorModel()
                model.status = status
                let pill = RecordingPill(model: model, appState: appState) {}
                    .frame(width: RecordingPill.panelSize.width, height: RecordingPill.panelSize.height)
                    .padding(20)
                    .background(BlitztextTheme.page)
                capture(pill, appearance: appearance, to: folder.appendingPathComponent("\(mode)-pill-\(label).png"))
            }
        }
        appState.page = .main
    }

    private static func capture<V: View>(_ view: V, appearance: NSAppearance?, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.isReleasedWhenClosed = false
        window.contentView = nil
        window.close()
    }
}
#endif
