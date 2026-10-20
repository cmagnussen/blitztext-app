import AVFoundation
import NaturalLanguage
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
        if let file = MacMeetingCheck.file {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacMeetingCheck.run(file)
                NSApp.terminate(nil)
            }
            return
        }
        if let microphone = UserDefaults.standard.string(forKey: "BlitztextLiveNotesCheck") {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacLiveNotesCheck.run(microphone: URL(fileURLWithPath: microphone))
                NSApp.terminate(nil)
            }
            return
        }
        if let id = UserDefaults.standard.string(forKey: "BlitztextLocalModelInstall") {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacLocalModelInstall.run(id)
                NSApp.terminate(nil)
            }
            return
        }
        if let file = MacMeetingCompare.output {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacMeetingCompare.run(file)
                NSApp.terminate(nil)
            }
            return
        }
        if let file = MacSummaryCheck.file {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacSummaryCheck.run(file)
                NSApp.terminate(nil)
            }
            return
        }
        if let file = MacSystemAudioRestartCheck.file {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacSystemAudioRestartCheck.run(file)
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = MacSystemAudioCheck.folder {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacSystemAudioCheck.run(folder)
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = MacLocalLLMCheck.folder {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MacLocalLLMCheck.run(folder)
                NSApp.terminate(nil)
            }
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
        appState.hotkeyService.isWorkflowRunning = { [weak self] in
            guard let active = self?.appState.activeWorkflow, case .running = active.phase else { return false }
            return true
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
        // A meeting being recorded stays readable and can be evaluated after the next launch.
        appState.meeting.finishBeforeQuit()
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
        case .escape:
            // In both modes: a recording stops and is transcribed, a transcription or
            // rewrite still running is cancelled before it pastes.
            if let active = appState.activeWorkflow, case .running = active.phase {
                appState.stopCurrentWorkflow()
            }
        }
    }

    private func handleHotkeyDown(_ type: WorkflowType) {
        // In toggle mode, any workflow shortcut finishes the current recording.
        // Do this before checking the requested mode: it may not be configured.
        if appState.appSettings.hotkeyMode == .toggle,
           let active = appState.activeWorkflow,
           case .running = active.phase {
            if active.isRecording {
                appState.stopCurrentWorkflow()
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
            if appState.appSettings.showsRecordingIndicator {
                // The pill shows the recording, so the menu stays closed and the text goes
                // back to the app in use. Pressing again, Escape or a click on the pill stops.
                appState.startWorkflow(type, source: .hotkeyBackground)
            } else {
                appState.prepareForPopoverPresentation()
                appState.startWorkflow(type, source: .manual)
                showPopover()
            }
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
                appState.stopCurrentWorkflow()
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
/// Runs the meeting evaluation on an audio file and prints the result, without microphone,
/// keychain or stored meetings: `-BlitztextMeetingCheck /path/to/file.m4a`. Uses the installed
/// Parakeet model and downloads the speaker models if they are missing.
@MainActor
enum MacMeetingCheck {
    static var file: URL? {
        UserDefaults.standard.string(forKey: "BlitztextMeetingCheck").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ file: URL) async {
        let store = MeetingStore(persistent: false)
        // Only the on-device model, so no API key is read from the keychain.
        let summarizes = TextRewriter.isLocalAvailable
        let controller = MeetingController(store: store) {
            MeetingController.Settings(
                language: "de",
                postProcessor: TranscriptPostProcessor(
                    customTerms: [], replacements: [], correctCustomTerms: false, removeFillerWords: true,
                    language: "de", isDictionaryWord: DictionaryWordChecker.isKnownWord
                ),
                summarizes: summarizes,
                engine: .automatic
            )
        }
        var audioURL: URL?
        var systemAudioURL: URL?
        defer {
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
            if let systemAudioURL { try? FileManager.default.removeItem(at: systemAudioURL) }
        }
        do {
            let wav = try AudioFileConverter.convertToWAV(file)
            let record = MeetingRecord(
                id: UUID(), createdAt: Date(), title: MeetingRecord.title(startedAt: Date()),
                duration: wav.duration, status: .pending
            )
            try FileManager.default.createDirectory(at: MeetingStore.directoryURL, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: wav.url, to: record.audioURL)
            audioURL = record.audioURL
            // `-BlitztextMeetingSystemTrack /path` evaluates it as an online meeting.
            if let system = UserDefaults.standard.string(forKey: "BlitztextMeetingSystemTrack") {
                try? FileManager.default.removeItem(at: record.systemAudioURL)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: system), to: record.systemAudioURL)
                systemAudioURL = record.systemAudioURL
            }
            store.upsert(record)
            print("Audio: \(Int(wav.duration)) s, summary on device: \(summarizes)")

            let started = Date()
            var lastStep = ""
            controller.process(record.id)
            while true {
                try await Task.sleep(for: .milliseconds(200))
                let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
                switch controller.phase {
                case .processing(let step) where step != lastStep:
                    print("[\(elapsed)] \(step)")
                    lastStep = step
                case .showing(let id):
                    print("[\(elapsed)] fertig")
                    guard let result = store.meeting(id: id) else { return }
                    if let notice = controller.notice { print("Hinweis: \(notice)") }
                    print("\nPersonen: \(result.speakers.count)\n\n" + result.transcriptText)
                    print("\n--- Zusammenfassung ---\n" + (result.summary ?? result.summaryNote ?? "keine"))
                    return
                case .failed(let message, _):
                    print("[\(elapsed)] FEHLER: \(message)")
                    return
                default:
                    continue
                }
            }
        } catch {
            print("FEHLER: \(error.localizedDescription)")
        }
    }
}

/// Online-call capture without the meeting UI: `-BlitztextSystemAudioCheck /folder` records
/// the system sound and the microphone side by side (`-BlitztextSystemAudioSeconds 45`,
/// `-BlitztextVoiceProcessing NO` for the raw microphone) and lists the apps that use
/// audio, then quits. Evaluate the files with `-BlitztextMeetingCheck`.
@MainActor
enum MacSystemAudioCheck {
    static var folder: URL? {
        UserDefaults.standard.string(forKey: "BlitztextSystemAudioCheck").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ folder: URL) async {
        guard #available(macOS 14.2, *) else {
            print("Systemton braucht macOS 14.2 oder neuer.")
            return
        }
        let defaults = UserDefaults.standard
        let seconds = defaults.integer(forKey: "BlitztextSystemAudioSeconds") > 0 ? defaults.integer(forKey: "BlitztextSystemAudioSeconds") : 45
        let voiceProcessing = defaults.object(forKey: "BlitztextVoiceProcessing") == nil || defaults.bool(forKey: "BlitztextVoiceProcessing")

        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            print("FEHLER: kein Mikrofonzugriff.")
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = voiceProcessing ? "vp" : "raw"
        let systemURL = folder.appendingPathComponent("system.caf")
        let micURL = folder.appendingPathComponent("mic-\(suffix).caf")

        printAudioApps("Vorher")
        let system = SystemAudioCapture()
        let microphone = MicrophoneCheckRecorder()
        do {
            // Voice processing rebuilds the audio devices when it starts, so the tap
            // comes second and attaches to the devices as they are then.
            let outputUID = try CoreAudioProperty.defaultOutputUID()
            try microphone.start(writingTo: micURL, voiceProcessing: voiceProcessing)
            try await Task.sleep(for: .seconds(1))
            print("Ausgabegerät vorher \(outputUID), jetzt \((try? CoreAudioProperty.defaultOutputUID()) ?? "?")")
            try system.start(writingTo: systemURL, outputUID: outputUID)
        } catch {
            print("FEHLER: \(error.localizedDescription)")
            system.stop()
            microphone.stop()
            return
        }
        print("Systemton: \(system.format?.description ?? "?")")
        print("Mikrofon (Echo-Unterdrückung \(voiceProcessing ? "an" : "aus")): \(microphone.format?.description ?? "?")")
        print("Aufnahme läuft \(seconds) s ...")

        for elapsed in stride(from: 10, through: seconds, by: 10) {
            try? await Task.sleep(for: .seconds(10))
            print("[\(elapsed) s] Pegel Systemton \(String(format: "%.3f", system.peak)), Mikrofon \(String(format: "%.3f", microphone.peak))")
        }
        try? await Task.sleep(for: .seconds(seconds % 10))
        system.stop()
        microphone.stop()

        printAudioApps("Während der Aufnahme")
        print("Fertig:\n  \(systemURL.path) (Spitze \(String(format: "%.3f", system.peak)))\n  \(micURL.path) (Spitze \(String(format: "%.3f", microphone.peak)))")
        if system.peak == 0 {
            print("HINWEIS: Systemton ist still. Fehlt die Freigabe unter Datenschutz & Sicherheit > Bildschirm- und Systemaudioaufnahme?")
        }
    }

    @available(macOS 14.2, *)
    private static func printAudioApps(_ label: String) {
        let active = AudioProcesses.all().filter { $0.isRunningInput || $0.isRunningOutput }
        print("\(label), Apps mit Audio:")
        for process in active {
            print("  \(process.bundleID)\(process.isRunningInput ? " [Mikrofon]" : "")\(process.isRunningOutput ? " [Ausgabe]" : "")")
        }
    }
}

/// `-BlitztextSystemAudioRestartCheck /path/system.caf` records the Mac's sound for 12 s and
/// stops the device after 4 s, as when headphones are unplugged. The capture should move to
/// the current output and fill the gap, so the file is as long as the recording took.
/// Without the permission the sound is silent, which is enough for the timing.
@MainActor
enum MacSystemAudioRestartCheck {
    static var file: URL? {
        UserDefaults.standard.string(forKey: "BlitztextSystemAudioRestartCheck").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ file: URL) async {
        guard #available(macOS 14.2, *) else {
            print("Systemton braucht macOS 14.2 oder neuer.")
            return
        }
        let capture = SystemAudioCapture()
        capture.onOutputChange = { error in
            print("Ausgabe gewechselt: \(error.map { "FEHLER \($0.localizedDescription)" } ?? "weiter auf \((try? CoreAudioProperty.defaultOutputUID()) ?? "?")")")
        }
        let started = Date()
        do {
            try capture.start(writingTo: file)
        } catch {
            print("FEHLER: \(error.localizedDescription)")
            capture.stop()
            return
        }
        try? await Task.sleep(for: .seconds(4))
        print("Ger\u{00E4}t gestoppt nach \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        capture.simulateOutputLoss()
        try? await Task.sleep(for: .seconds(8))
        capture.stop()
        let elapsed = Date().timeIntervalSince(started)
        guard let recorded = try? AVAudioFile(forReading: file) else {
            print("FEHLER: Datei nicht lesbar.")
            return
        }
        let seconds = Double(recorded.length) / recorded.fileFormat.sampleRate
        print(String(format: "Aufnahme %.2f s, Datei %.2f s, Abweichung %.2f s", elapsed, seconds, elapsed - seconds))
    }
}

/// Compares meeting summaries: `-BlitztextSummaryCheck transcript.txt` summarizes with the
/// on-device model like the app does, or, with `-BlitztextSummaryEndpoint
/// http://localhost:1234/v1 -BlitztextSummaryModel <id>`, with that OpenAI-compatible model:
/// same instructions, temperature 0, no keychain.
@MainActor
enum MacSummaryCheck {
    static var file: URL? {
        UserDefaults.standard.string(forKey: "BlitztextSummaryCheck").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ file: URL) async {
        guard let transcript = try? String(contentsOf: file, encoding: .utf8) else {
            print("FEHLER: Datei nicht lesbar.")
            return
        }
        let defaults = UserDefaults.standard
        let started = Date()
        do {
            let summary: String
            if let endpoint = defaults.string(forKey: "BlitztextSummaryEndpoint"),
               let model = defaults.string(forKey: "BlitztextSummaryModel") {
                print("Modell: \(model)")
                summary = try await summarize(transcript, endpoint: endpoint, model: model)
            } else {
                print("Modell: Apple Intelligence (Kontext \(TextRewriter.isLocalAvailable ? "verf\u{00FC}gbar" : "fehlt"))")
                summary = try await MeetingSummarizer.summarize(transcript, engine: .automatic)
            }
            print(String(format: "Dauer: %.1f s\n", Date().timeIntervalSince(started)) + summary)
        } catch {
            print("FEHLER: \(error.localizedDescription)")
        }
    }

    /// The provider path of `MeetingSummarizer`, with the request sent directly.
    static func summarize(_ transcript: String, endpoint: String, model: String) async throws -> String {
        let isGerman = MeetingSummarizer.isGermanMeeting(transcript)
        var material = transcript
        var round = 0
        while material.count > 60_000, round < 3 {
            var notes: [String] = []
            for part in MeetingSummarizer.chunks(of: material, limit: 60_000) {
                notes.append(try await complete(part, instruction: isGerman ? MeetingSummarizer.partInstruction : MeetingSummarizer.englishPartInstruction, endpoint: endpoint, model: model))
            }
            material = notes.joined(separator: "\n\n")
            round += 1
        }
        let summary = try await complete(material, instruction: isGerman ? MeetingSummarizer.finalInstruction : MeetingSummarizer.englishFinalInstruction, endpoint: endpoint, model: model)
        return InventedDeadlineFilter.filtered(MeetingSummarizer.cleaned(summary), transcript: transcript, transcriptIsGerman: isGerman)
    }

    private static func complete(_ text: String, instruction: String, endpoint: String, model: String) async throws -> String {
        guard let url = URL(string: endpoint + "/chat/completions") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "messages": [["role": "system", "content": instruction], ["role": "user", "content": text]],
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "SummaryCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "?"])
        }
        return content
    }
}

/// Live notes without a meeting: `-BlitztextLiveNotesCheck mic.wav` (16 kHz 16-bit PCM, read
/// like the growing recording) and optionally `-BlitztextLiveNotesSystem other.caf` (any
/// format, fed through the live buffer like the system sound). One update, then the
/// catch-up.
@MainActor
enum MacLiveNotesCheck {
    static func run(microphone: URL) async {
        print("Live-Notizen verf\u{00FC}gbar: \(LiveNotesController.isAvailable)")
        var buffer: LiveAudioBuffer?
        if let path = UserDefaults.standard.string(forKey: "BlitztextLiveNotesSystem") {
            let systemBuffer = LiveAudioBuffer()
            do {
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                while file.framePosition < file.length {
                    guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800) else { break }
                    try file.read(into: chunk)
                    systemBuffer.append(chunk)
                }
                buffer = systemBuffer
            } catch {
                print("FEHLER Systemspur: \(error.localizedDescription)")
            }
        }
        let live = LiveNotesController(
            microphoneURL: microphone,
            systemBuffer: buffer,
            language: "de",
            postProcessor: TranscriptPostProcessor(removeFillerWords: true, language: "de"),
            ownName: MeetingController.ownName
        )
        let started = Date()
        live.update()
        while live.isUpdating { try? await Task.sleep(for: .milliseconds(200)) }
        print(String(format: "Update nach %.1f s, Modell %@", Date().timeIntervalSince(started), live.modelName ?? "-"))
        if let problem = live.problem { print("PROBLEM: \(problem)") }
        print("--- Transkript ---\n\(live.transcriptForCheck)")
        print("--- Notizen ---\n\(live.notes)")
        let catchUpStart = Date()
        live.catchUpOnLastMinutes()
        while live.isCatchingUp { try? await Task.sleep(for: .milliseconds(200)) }
        print(String(format: "--- Was habe ich verpasst? (%.1f s) ---\n%@", Date().timeIntervalSince(catchUpStart), live.catchUp ?? "-"))
        #if arch(arm64)
        print("MLX-Speicher vor stop: \(LocalLanguageModel.memory().active / 1_000_000) MB")
        #endif
        // The meeting ends while "Was habe ich verpasst?" still runs: the model must go anyway.
        // `-BlitztextLiveNotesRace NO` stops without it.
        if UserDefaults.standard.object(forKey: "BlitztextLiveNotesRace") == nil || UserDefaults.standard.bool(forKey: "BlitztextLiveNotesRace") {
            live.catchUpOnLastMinutes()
        }
        let stopping = Date()
        await live.stop()
        print(String(format: "stop() dauerte %.1f s", Date().timeIntervalSince(stopping)))
        print("Nach stop: fragt noch \(live.isCatchingUp ? "ja" : "nein")")
        #if arch(arm64)
        print("MLX-Speicher nach stop: \(LocalLanguageModel.memory().active / 1_000_000) MB")
        try? await Task.sleep(for: .seconds(5))
        print("MLX-Speicher 5 s sp\u{00E4}ter: \(LocalLanguageModel.memory().active / 1_000_000) MB")
        #endif
    }
}

/// Installs a local model like the settings do and prints the progress:
/// `-BlitztextLocalModelInstall gemma-4-12b-it-4bit`.
@MainActor
enum MacLocalModelInstall {
    static func run(_ id: String) async {
        guard let variant = LocalModelVariant.all.first(where: { $0.id == id }) else {
            print("Unbekannt: \(id). Bekannt: \(LocalModelVariant.all.map(\.id).joined(separator: ", "))")
            return
        }
        let store = LocalModelStore.shared
        print("\(variant.name): \(variant.support()), Ordner \(LocalModelStore.folder(for: variant).path)")
        store.download(variant)
        let started = Date()
        var lastPrint = Date.distantPast
        while true {
            try? await Task.sleep(for: .milliseconds(500))
            switch store.state(of: variant) {
            case .downloading(let fraction):
                if Date().timeIntervalSince(lastPrint) > 5 {
                    print(String(format: "%.0f %%", fraction * 100))
                    lastPrint = Date()
                }
            case .installed:
                print(String(format: "Installiert nach %.0f s", Date().timeIntervalSince(started)))
                return
            case .failed(let message):
                print("FEHLER: \(message)")
                return
            case .notInstalled:
                print("Abgebrochen.")
                return
            }
        }
    }
}

/// Compares summaries of the latest stored meeting without showing its content here:
/// `-BlitztextMeetingCompare /path/file.md` writes the summaries side by side into that
/// file and prints only figures, e.g. dates and numbers a summary names that the transcript
/// does not contain. `-BlitztextSummaryEndpoint` and `-BlitztextSummaryModels a,b` add
/// OpenAI-compatible models. Reads the stored meetings, never changes them.
@MainActor
enum MacMeetingCompare {
    static var output: URL? {
        UserDefaults.standard.string(forKey: "BlitztextMeetingCompare").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ output: URL) async {
        guard let meetings = MeetingStore.readWithoutRepair() else {
            print("FEHLER: Meetings nicht lesbar (Schl\u{00FC}sselbund?). Nichts ver\u{00E4}ndert.")
            return
        }
        guard let record = meetings.filter({ $0.status == .done }).max(by: { $0.createdAt < $1.createdAt }) else {
            print("FEHLER: kein ausgewertetes Meeting.")
            return
        }
        let transcript = record.transcriptText
        let words = transcript.split(whereSeparator: \.isWhitespace).count
        print("Meeting: \(MeetingNotifier.duration(record.duration)), \(record.speakers.count) Personen, \(words) W\u{00F6}rter, \(transcript.count) Zeichen")

        var variants: [(name: String, seconds: Double?, summary: String)] = []
        if let stored = record.summary { variants.append(("Beim Meeting erstellt (Apple Intelligence)", nil, stored)) }
        let started = Date()
        do {
            variants.append(("Apple Intelligence, neu", Date().timeIntervalSince(started), try await MeetingSummarizer.summarize(transcript, engine: .automatic)))
            variants[variants.count - 1].seconds = Date().timeIntervalSince(started)
        } catch {
            print("Apple Intelligence: FEHLER \(error.localizedDescription)")
        }
        #if arch(arm64)
        // The app's own path: the installed local model, as `MeetingController` uses it.
        if let variant = LocalModelStore.shared.preferredInstalled {
            let model = LocalLanguageModel(folder: LocalModelStore.folder(for: variant))
            let modelStart = Date()
            do {
                try await model.load()
                let backend = MeetingSummarizer.Backend(characterLimit: MeetingController.localModelCharacterLimit) { instruction, text in
                    try await model.complete(instruction: instruction, text: text, maxTokens: 1_500)
                }
                let summary = try await MeetingSummarizer.summarize(transcript, engine: .automatic, backend: backend)
                variants.append(("\(variant.name) in Blitztext", Date().timeIntervalSince(modelStart), summary))
            } catch {
                print("\(variant.name): FEHLER \(error.localizedDescription)")
            }
            await model.unload()
        }
        #endif
        let defaults = UserDefaults.standard
        if let endpoint = defaults.string(forKey: "BlitztextSummaryEndpoint") {
            for model in (defaults.string(forKey: "BlitztextSummaryModels") ?? "").split(separator: ",").map(String.init) {
                let modelStart = Date()
                do {
                    let summary = try await MacSummaryCheck.summarize(transcript, endpoint: endpoint, model: model)
                    variants.append((model, Date().timeIntervalSince(modelStart), summary))
                } catch {
                    print("\(model): FEHLER \(error.localizedDescription.prefix(200))")
                }
            }
        }

        var document = "# Vergleich der Zusammenfassungen\n\n\(record.title), \(MeetingNotifier.duration(record.duration)), \(record.speakers.count) Personen\n"
        for variant in variants {
            let figures = Self.figures(variant.summary, transcript: transcript)
            let time = variant.seconds.map { String(format: "%.0f s", $0) } ?? "-"
            print("\(variant.name): \(time), \(figures.decisions) Entscheidungen, \(figures.todos) To-dos, \(figures.words) W\u{00F6}rter, nicht im Transkript: \(figures.unsupported.count) \(figures.unsupported.isEmpty ? "" : "(Art: " + figures.kinds + ")")")
            document += "\n---\n\n## \(variant.name)\n\nDauer \(time), \(figures.decisions) Entscheidungen, \(figures.todos) To-dos. Nicht im Transkript: \(figures.unsupported.isEmpty ? "nichts" : figures.unsupported.joined(separator: ", "))\n\n\(variant.summary)\n"
        }
        document += "\n---\n\n## Transkript\n\n" + transcript + "\n"
        do {
            try document.write(to: output, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            print("Gespeichert: \(output.path)")
        } catch {
            print("FEHLER beim Schreiben: \(error.localizedDescription)")
        }
    }

    /// Bullet counts and what the summary names that the transcript never says: numbers,
    /// weekdays, months and person labels. A rough sign of invented content.
    static func figures(_ summary: String, transcript: String) -> (decisions: Int, todos: Int, words: Int, unsupported: [String], kinds: String) {
        let lines = summary.components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
        var section = ""
        var decisions = 0, todos = 0
        for line in lines {
            if line.lowercased().hasPrefix("entscheidungen") { section = "d"; continue }
            if line.lowercased().hasPrefix("to-dos") { section = "t"; continue }
            guard line.hasPrefix("- "), !line.lowercased().contains("keine") else { continue }
            if section == "d" { decisions += 1 } else if section == "t" { todos += 1 }
        }
        let haystack = transcript.lowercased()
        let digitsInTranscript = Set(transcript.split(whereSeparator: { !$0.isNumber }).map(String.init))
        let calendarWords = ["montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag", "januar", "februar", "m\u{00E4}rz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]
        var unsupported: [String] = []
        var kinds = Set<String>()
        for token in summary.split(whereSeparator: { $0.isWhitespace || ",.;:()\"„“".contains($0) }).map(String.init) {
            let lower = token.lowercased()
            let digits = token.split(whereSeparator: { !$0.isNumber }).map(String.init)
            if !digits.isEmpty, digits.contains(where: { !digitsInTranscript.contains($0) }) {
                unsupported.append(token); kinds.insert("Zahl")
            } else if calendarWords.contains(lower), !haystack.contains(lower) {
                unsupported.append(token); kinds.insert("Datum")
            }
        }
        for match in summary.matches(of: /Person \d+/) where !transcript.contains(String(summary[match.range])) {
            unsupported.append(String(summary[match.range])); kinds.insert("Person")
        }
        return (decisions, todos, summary.split(whereSeparator: \.isWhitespace).count, Array(Set(unsupported)).sorted(), kinds.sorted().joined(separator: ", "))
    }
}

/// Local language model without the meeting UI: `-BlitztextLocalLLMCheck /path/to/model`
/// loads an MLX model folder (e.g. Gemma 4), answers a short instruction on a text
/// (`-BlitztextLocalLLMInput file.txt`, otherwise a built-in example;
/// `-BlitztextLocalLLMInstruction`, `-BlitztextLocalLLMMaxTokens`) at temperature 0, prints
/// load time, speed, memory and the answer, unloads and quits. No keychain, no network.
@MainActor
enum MacLocalLLMCheck {
    static var folder: URL? {
        UserDefaults.standard.string(forKey: "BlitztextLocalLLMCheck").map { URL(fileURLWithPath: $0) }
    }

    static func run(_ folder: URL) async {
        #if arch(arm64)
        let defaults = UserDefaults.standard
        var text = "Person 1: Wir verschieben den Launch der App um eine Woche, weil die Tests auf iOS noch fehlen.\n\nPerson 2: Einverstanden. Ich schreibe heute noch dem Kunden und kläre, ob das für ihn passt."
        if let path = defaults.string(forKey: "BlitztextLocalLLMInput") {
            guard let file = try? String(contentsOfFile: path, encoding: .utf8) else {
                print("FEHLER: Eingabedatei nicht lesbar.")
                return
            }
            text = file
        }
        let instruction = defaults.string(forKey: "BlitztextLocalLLMInstruction") ?? "Fasse in zwei S\u{00E4}tzen zusammen."
        let maxTokens = defaults.integer(forKey: "BlitztextLocalLLMMaxTokens") > 0 ? defaults.integer(forKey: "BlitztextLocalLLMMaxTokens") : 300
        print("Modell: \(folder.path)")
        print("Eingabe: \(text.count) Zeichen, Anweisung: \(instruction)")
        print("Speicher vorher: \(memoryLine())")

        let model = LocalLanguageModel(folder: folder)
        do {
            let started = Date()
            try await model.load()
            print(String(format: "Laden: %.1f s", Date().timeIntervalSince(started)) + ", Speicher: \(memoryLine())")
            print(try await model.compareChatFormats(instruction: instruction, text: text))

            // The first run includes compiling MLX's Metal kernels; the second shows the
            // steady speed and must give the same text at temperature 0.
            let answer = try await timedAnswer("Antwort", model, instruction, text, maxTokens)
            print("Speicher nach der Antwort: \(memoryLine())")
            let again = try await timedAnswer("Zweiter Lauf", model, instruction, text, maxTokens)
            print("Zweiter Lauf gleich: \(again == answer ? "ja" : "NEIN")")

            await model.unload()
            print("Speicher nach unload(): \(memoryLine())")
            // `-BlitztextLocalLLMReload YES` loads and unloads once more, to tell a leak
            // (memory keeps growing) from memory the allocator keeps for reuse.
            if defaults.bool(forKey: "BlitztextLocalLLMReload") {
                _ = try await timedAnswer("Nach Neuladen", model, instruction, text, maxTokens)
                await model.unload()
                print("Speicher nach zweitem unload(): \(memoryLine())")
            }
            print("\n--- Antwort ---\n" + answer)
        } catch {
            print("FEHLER: \(error.localizedDescription)")
        }
        #else
        print("Lokale Sprachmodelle laufen nur auf Apple Silicon.")
        #endif
    }

    #if arch(arm64)
    private static func timedAnswer(
        _ label: String, _ model: LocalLanguageModel, _ instruction: String, _ text: String, _ maxTokens: Int
    ) async throws -> String {
        let started = Date()
        let answer = try await model.complete(instruction: instruction, text: text, maxTokens: maxTokens)
        let seconds = Date().timeIntervalSince(started)
        if let figures = await model.lastStatistics {
            print(String(
                format: "%@: %.1f s gesamt, Prompt %ld Tokens in %.2f s (%.0f Tokens/s), erzeugt %ld Tokens in %.2f s (%.1f Tokens/s)%@",
                label, seconds, figures.promptTokens, figures.promptSeconds, figures.promptTokensPerSecond,
                figures.generatedTokens, figures.generationSeconds, figures.tokensPerSecond,
                figures.stoppedAtTokenLimit ? ", am Token-Limit abgeschnitten" : ""
            ))
        }
        return answer
    }

    private static func memoryLine() -> String {
        let mlx = LocalLanguageModel.memory()
        return "Prozess \(gigabytes(physicalFootprint())), MLX aktiv \(gigabytes(mlx.active)), Puffer \(gigabytes(mlx.cache)), Spitze \(gigabytes(mlx.peak))"
    }

    private static func gigabytes(_ bytes: Int) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    /// What Activity Monitor shows as the app's memory, GPU buffers included.
    private static func physicalFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
    #endif
}

/// Microphone into a file, optionally with Apple's voice processing (echo cancellation).
final class MicrophoneCheckRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var peak: Float = 0
    private(set) var format: AVAudioFormat?

    func start(writingTo url: URL, voiceProcessing: Bool) throws {
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            // Voice processing lowers other audio by default, which would also lower the call.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        self.format = format
        file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if let samples = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) { self.peak = max(self.peak, abs(samples[index])) }
            }
            try? self.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
    }
}

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

            for (page, label) in [(PopoverPage.main, "main"), (.onboarding, "onboarding"), (.history, "history"), (.whatsNew, "whatsnew")] {
                appState.page = page
                capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-\(label).png"))
            }
            // The setup assistant as on a Mac that has nothing set up yet.
            SetupAssistantView.debugShowsFreshMac = true
            appState.page = .onboarding
            capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-onboarding-fresh.png"))
            SetupAssistantView.debugShowsFreshMac = false
            renderMeetingPages(appState: appState, appearance: appearance, mode: mode, to: folder)
            for pane in SettingsPane.allCases {
                SettingsContentView.debugInitialPane = pane
                appState.page = .settings
                capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-popover-settings-\(pane.rawValue).png"))
                let view = SettingsContentView(appState: appState)
                    .frame(width: MenuBarView.width, height: 1400, alignment: .top)
                    .background(BlitztextTheme.page)
                capture(view, appearance: appearance, to: folder.appendingPathComponent("\(mode)-settings-\(pane.rawValue).png"))
            }
            for (status, label) in [(MenuBarStatus.recording(.tapTalk), "recording"), (.processing(.tapTalk), "processing"), (.success(.tapTalk), "success"), (.copied(.tapTalk), "copied")] {
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

    private static func renderMeetingPages(appState: AppState, appearance: NSAppearance?, mode: String, to folder: URL) {
        let meeting = appState.meeting
        if meeting.store.meetings.isEmpty {
            meeting.store.upsert(sampleMeeting)
        }
        let phases: [(MeetingController.Phase, String)] = [
            (.idle, "start"),
            (.recording(startedAt: Date().addingTimeInterval(-754)), "recording"),
            (.processing("Stimmen werden erkannt ..."), "processing"),
            (.showing(sampleMeeting.id), "result"),
        ]
        appState.page = .meeting
        for (phase, label) in phases {
            meeting.preview(phase)
            capture(MenuBarView(appState: appState), appearance: appearance, to: folder.appendingPathComponent("\(mode)-meeting-\(label).png"))
            // The whole result, beyond the popover height.
            if case .showing = phase {
                let full = MeetingView(appState: appState, height: 1100)
                    .frame(width: MenuBarView.width)
                    .background(BlitztextTheme.page)
                capture(full, appearance: appearance, to: folder.appendingPathComponent("\(mode)-meeting-result-full.png"))
            }
        }
        meeting.preview(.idle)
    }

    private static let sampleMeeting = MeetingRecord(
        id: UUID(uuidString: "5A3B1E00-0000-4000-8000-0000000000AC")!,
        createdAt: Date(),
        title: MeetingRecord.title(startedAt: Date()),
        duration: 62,
        status: .done,
        turns: [
            MeetingTurn(speaker: 1, start: 0, text: "Kurzer Stand zum Workshop: Die Agenda steht, mir fehlt nur noch der Raum."),
            MeetingTurn(speaker: 2, start: 14, text: "Den Raum buche ich. Sollen wir online oder im B\u{00FC}ro machen?"),
            MeetingTurn(speaker: 3, start: 31, text: "Lieber online, dann kann das Team aus Hamburg dabei sein."),
            MeetingTurn(speaker: 1, start: 45, text: "Gut, dann online. Ich schicke die Einladung bis Freitag."),
        ],
        speakerNames: [3: "Anna"],
        summary: """
        Zusammenfassung
        Der Workshop findet online statt, damit auch das Team aus Hamburg teilnehmen kann. Die Agenda steht.

        Entscheidungen
        - Der Workshop findet online statt

        To-dos
        - Person 1: Einladung schicken (bis Freitag)
        - Person 2: Raum buchen
        """
    )

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
