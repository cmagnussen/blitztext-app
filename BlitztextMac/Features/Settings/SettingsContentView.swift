import SwiftUI
import AppKit

struct SettingsContentView: View {
    @Bindable var appState: AppState
    @State private var activePane: SettingsPane = Self.initialPane

    #if DEBUG
    /// Pane the snapshot renderer opens; nil in normal use.
    static var debugInitialPane: SettingsPane?
    private static var debugPaneOverride: SettingsPane? { debugInitialPane }
    #else
    private static var debugPaneOverride: SettingsPane? { nil }
    #endif
    private static var initialPane: SettingsPane { debugPaneOverride ?? .general }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedToggle(
                options: SettingsPane.allCases,
                selection: $activePane,
                label: { $0.title }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                CustomizeSettingsView(appState: appState, pane: activePane)
                    .id(activePane)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            appState.refreshAccessibilityPermission()
            activePane = Self.debugPaneOverride ?? defaultPane
        }
    }

    /// Without a speech model nothing works, so the models tab comes first then.
    /// Missing permissions show up at the top of "Allgemein".
    private var defaultPane: SettingsPane {
        appState.isConfigured ? .general : .models
    }
}

enum SettingsPane: Int, CaseIterable, Identifiable {
    case general
    case models
    case workflows
    case dictionary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .models: return "Modelle"
        case .workflows: return "Modi"
        case .dictionary: return "W\u{00F6}rterbuch"
        }
    }
}

// MARK: - Section Label (quiet style)

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(12.5, .semibold))
    }
}

// MARK: - System sections (in "Allgemein")

/// Shown at the top of "Allgemein" only while pasting is not allowed yet.
struct PermissionWarningSection: View {
    @Bindable var appState: AppState
    @State private var isResetting = false
    @State private var resetErrorText: String?

    var body: some View {
        SettingsSection(title: "Berechtigungen") {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(BlitztextTheme.danger)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Direktes Einf\u{00FC}gen ist noch nicht freigegeben.")
                        .font(.ui(11.5, .semibold))
                        .foregroundStyle(.primary)

                    Text("\u{00D6}ffne Bedienungshilfen und aktiviere Blitztext. Steht Blitztext dort schon auf an, hier die Freigabe zur\u{00FC}cksetzen und danach neu erlauben.")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let resetErrorText {
                        Text(resetErrorText)
                            .font(.ui(12))
                            .foregroundStyle(BlitztextTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Three buttons don't fit the popover width, so the reset moves to its own line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    openButton
                    recheckButton
                    resetButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        openButton
                        recheckButton
                    }
                    resetButton
                }
            }
        }
    }

    private var openButton: some View {
        Button("Bedienungshilfen \u{00F6}ffnen") {
            appState.requestAccessibilityPermission()
        }
        .buttonStyle(SubtleButtonStyle())
    }

    private var recheckButton: some View {
        Button("Erneut pr\u{00FC}fen") {
            appState.refreshAccessibilityPermission()
        }
        .buttonStyle(SubtleButtonStyle())
    }

    private var resetButton: some View {
        Button("Freigabe zur\u{00FC}cksetzen") {
            isResetting = true
            resetErrorText = nil
            Task {
                if !(await appState.resetAccessibilityPermission()) {
                    resetErrorText = "Zur\u{00FC}cksetzen hat nicht geklappt. In Bedienungshilfen Blitztext mit \u{201E}\u{2212}\u{201C} entfernen und neu hinzuf\u{00FC}gen."
                }
                isResetting = false
            }
        }
        .buttonStyle(SubtleButtonStyle())
        .disabled(isResetting)
    }
}

/// Shown only when Blitztext runs outside /Applications or a second copy exists.
struct InstallationWarningSection: View {
    @State private var currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
    @State private var installActionErrorText: String?

    static var isNeeded: Bool {
        guard !BlitztextInstallLocationService.isPreviewBuild else { return false }
        return !BlitztextInstallLocationService.currentInstallLocation.isCanonicalInstall
            || !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty
    }

    var body: some View {
        SettingsSection(title: "Installation") {

            Text(installationHeadline)
                .font(.ui(11.5, .semibold))
                .foregroundStyle(.primary)

            Text(installationDetail)
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(BlitztextInstallLocationService.bundleURL.path)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                Text("Auf diesem Mac liegen weitere Blitztext-Kopien. Behalte nur eine, sonst startet die App womöglich doppelt.")
                    .font(.ui(12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    Button("Nach /Applications bewegen") {
                        moveToApplications()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }

                Button("Im Finder zeigen") {
                    revealInFinder(urls: [BlitztextInstallLocationService.bundleURL])
                }
                .buttonStyle(SubtleButtonStyle())

                if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                    Button("Weitere Kopien zeigen") {
                        revealInFinder(urls: BlitztextInstallLocationService.otherInstalledBundleURLs)
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            if let installActionErrorText {
                Text(installActionErrorText)
                    .font(.ui(12))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshInstallState() }
    }

    private var installationHeadline: String {
        switch currentInstallLocation {
        case .applications:
            return "Blitztext liegt am richtigen Ort."
        case .userApplications:
            return "Blitztext liegt noch in ~/Applications."
        case .outsideApplications:
            return "Blitztext liegt noch nicht in /Applications."
        case .unknown:
            return "Der Installationsort konnte nicht sicher erkannt werden."
        }
    }

    private var installationDetail: String {
        switch currentInstallLocation {
        case .applications:
            if BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                return "Für stabile Login-Items und Updates nur diese Kopie weiterverwenden."
            }
            return "Diese Kopie ist korrekt. Zusätzliche Kopien solltest du später entfernen."
        case .userApplications:
            return "Für Team-Rollouts und saubere Updates sollte Blitztext nur aus /Applications laufen."
        case .outsideApplications:
            return "Verschiebe Blitztext einmal nach /Applications, damit Anmeldestart und spätere Updates sauber bleiben."
        case .unknown:
            return "Öffne Blitztext möglichst direkt aus /Applications."
        }
    }

    private func refreshInstallState() {
        currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
        installActionErrorText = nil
    }

    private func moveToApplications() {
        installActionErrorText = nil

        do {
            try BlitztextInstallLocationService.moveToApplicationsAndRelaunch()
        } catch {
            installActionErrorText = error.localizedDescription
        }
    }

    private func revealInFinder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct LaunchAtLoginSection: View {
    @State private var launchAtLoginService = LaunchAtLoginService()

    var body: some View {
        SettingsSection(title: "Beim Anmelden") {

            Toggle("Blitztext automatisch starten", isOn: Binding(
                get: { launchAtLoginService.isEnabled },
                set: { launchAtLoginService.setEnabled($0) }
            ))
            .toggleStyle(.trailingSwitch)

            Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
                .font(.ui(12))
                .foregroundStyle(
                    launchAtLoginService.errorText == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.red)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { launchAtLoginService.refresh() }
    }
}

/// Version, GitHub, release notes, licenses, updates and removal.
struct AboutBlitztextSection: View {
    @Bindable var appState: AppState

    @State private var showCleanupOptions = false
    @State private var deleteLocalDataOnCleanup = true
    @State private var cleanupStatusText: String?
    @State private var cleanupErrorText: String?

    static let repositoryURL = "https://github.com/cmagnussen/blitztext-app"

    var body: some View {
        SettingsSection(title: "\u{00DC}ber Blitztext") {

            HStack(spacing: 10) {
                Text("Version \(appVersion)")
                    .font(.ui(11.5, .semibold))
                Spacer(minLength: 8)
                Button {
                    if let url = URL(string: Self.repositoryURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label {
                        Text("Auf GitHub ansehen")
                    } icon: {
                        Image("GitHubMark")
                            .resizable()
                            .frame(width: 13, height: 13)
                    }
                    .font(.ui(11.5, .medium))
                }
                .buttonStyle(.glassAction)
                .help("Blitztext ist Open Source. Ein Stern auf GitHub hilft.")
            }

            Button("Feedback senden") { sendFeedback() }
                .buttonStyle(SubtleButtonStyle())
                .help("\u{00D6}ffnet eine vorbereitete Mail an \(FeedbackMail.address). Du siehst alles, bevor sie rausgeht.")

            Button("Neuigkeiten in \(WhatsNew.version) anzeigen") {
                appState.showWhatsNewAgain()
            }
            .buttonStyle(SubtleButtonStyle())

            Button("Lizenzen und Hinweise") {
                if let url = Bundle.main.url(forResource: "Licenses", withExtension: "txt") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(SubtleButtonStyle())

            if appState.appUpdateService.isManagedByDeviceManagement {
                Text("Neue Versionen installiert die Ger\u{00E4}teverwaltung dieses Macs automatisch.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.appUpdateService.updatesInApp {
                if !BlitztextInstallLocationService.currentInstallLocation.isCanonicalInstall {
                    Text("Auto-Updates laufen erst sauber, wenn Blitztext aus /Applications gestartet wird.")
                        .font(.ui(12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Nach Updates suchen") {
                        appState.appUpdateService.checkForUpdates()
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Toggle("Automatisch nach Updates suchen", isOn: Binding(
                        get: { appState.appUpdateService.automaticallyChecksForUpdates },
                        set: { appState.appUpdateService.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.trailingSwitch)

                    Toggle("Updates automatisch laden", isOn: Binding(
                        get: { appState.appUpdateService.automaticallyDownloadsUpdates },
                        set: { appState.appUpdateService.automaticallyDownloadsUpdates = $0 }
                    ))
                    .toggleStyle(.trailingSwitch)
                }

                Text(appState.appUpdateService.statusText)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // No update feed in this build: new versions come from the releases page.
                Text("Neue Versionen gibt es auf der Releases-Seite.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Releases-Seite \u{00F6}ffnen") {
                    if let url = URL(string: Self.repositoryURL + "/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SubtleButtonStyle())
            }

            Divider().opacity(0.3)

            if showCleanupOptions {
                Toggle("Einstellungen, API-Keys und Sprachmodelle l\u{00F6}schen", isOn: $deleteLocalDataOnCleanup)
                    .toggleStyle(.trailingSwitch)

                Text("Entfernt auch den Anmeldestart. Danach Blitztext beenden und die App aus /Applications l\u{00F6}schen.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Abbrechen") {
                        showCleanupOptions = false
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Button("Jetzt bereinigen") {
                        runCleanup()
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .foregroundStyle(BlitztextTheme.danger)
                }
            } else {
                Button("Blitztext von diesem Mac entfernen \u{2026}") {
                    showCleanupOptions = true
                }
                .buttonStyle(SubtleButtonStyle())
            }

            if let cleanupStatusText {
                Text(cleanupStatusText)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let cleanupErrorText {
                Text(cleanupErrorText)
                    .font(.ui(12))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A prepared mail in the mail app; without one the address lands on the clipboard.
    private func sendFeedback() {
        let details = [
            "Sprachmodell: \(LocalTranscriptionModel.displayName(for: appState.selectedLocalModelName))",
            "K\u{00FC}rzel: \(appState.appSettings.hotkeyMode == .hold ? "Halten" : "Dr\u{00FC}cken")",
            "KI-Modi: \(appState.appSettings.rewriteEngine.displayName)",
            "Updates: \(appState.appUpdateService.isManagedByDeviceManagement ? "Ger\u{00E4}teverwaltung" : "in der App")",
        ]
        guard let url = FeedbackMail.url(details: details), NSWorkspace.shared.open(url) else {
            appState.copyToClipboard(FeedbackMail.address)
            return
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(version) (\(build))"
    }

    private func runCleanup() {
        cleanupStatusText = nil
        cleanupErrorText = nil

        let report = deleteLocalDataOnCleanup
            ? BlitztextCleanupService.cleanupUserData()
            : BlitztextCleanupService.removeLaunchAtLoginRegistration()

        if deleteLocalDataOnCleanup {
            AIProvider.allCases.forEach(APIKeyStore.delete)
            appState.aiProvider = nil
            appState.aiKeyRevision += 1
        }

        if report.failedItems.isEmpty {
            cleanupStatusText = deleteLocalDataOnCleanup
                ? "Anmeldestart und lokale Daten wurden bereinigt. Jetzt Blitztext beenden und aus /Applications löschen."
                : "Anmeldestart wurde deaktiviert. Jetzt Blitztext beenden und aus /Applications löschen."
            showCleanupOptions = false

            let urlsToReveal = report.knownInstallBundleURLs.isEmpty
                ? [BlitztextInstallLocationService.bundleURL]
                : report.knownInstallBundleURLs
            revealInFinder(urls: urlsToReveal)
            return
        }

        let failureSummary = report.failedItems
            .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
            .joined(separator: "\n")
        cleanupErrorText = "Nicht alles konnte bereinigt werden:\n\(failureSummary)"
    }

    private func revealInFinder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

// MARK: - Settings panes

struct CustomizeSettingsView: View {
    @Bindable var appState: AppState
    var pane: SettingsPane = .general
    @State private var newTerm = ""
    @State private var newSpoken = ""
    @State private var newWritten = ""
    @State private var showsImproverPrompt = false
    @State private var showsDampfPrompt = false

    private var installedLocalModels: [LocalTranscriptionModel] {
        LocalTranscriptionService.installedModels()
    }

    private var localModelOptions: [LocalTranscriptionModel] {
        LocalTranscriptionService.modelOptions(selected: appState.selectedLocalModelName)
    }

    private var installedModelsText: String {
        let count = installedLocalModels.count
        return count == 1 ? "1 lokales Sprachmodell installiert." : "\(count) lokale Sprachmodelle installiert."
    }

    private var aiEngineStatusText: String {
        switch TextRewriter.localAvailability {
        case .available:
            return appState.appSettings.rewriteEngine == .automatic
                ? "Apple Intelligence ist bereit. Umformulieren läuft auf diesem Mac."
                : "Umformulieren läuft über den Modell-Anbieter unten."
        case .unavailable(let reason):
            return appState.isAIProviderReady
                ? "\(reason) Bis dahin übernimmt der Modell-Anbieter unten."
                : "\(reason) Für die KI-Modi unten einen Modell-Anbieter mit API-Key hinterlegen."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            if pane == .general {
            if !appState.accessibilityPermissionGranted {
                PermissionWarningSection(appState: appState)
            }
            if InstallationWarningSection.isNeeded {
                InstallationWarningSection()
            }

            PipelineOverviewSection(appState: appState)

            // MARK: Tastenkuerzel
            SettingsSection(title: "Tastenk\u{00FC}rzel") {

                VStack(spacing: 6) {
                    ForEach(WorkflowType.mainMenuCases) { type in
                        HStack(spacing: 6) {
                            let replaced = appState.appSettings.customHotkey(for: type) != nil
                                && !appState.hotkeyService.failedCustomHotkeys.contains(type)
                            Text(type.hotkeyLabel)
                                .font(.system(size: 10.5, design: .monospaced))
                                .strikethrough(replaced)
                                .foregroundStyle(replaced ? .tertiary : .secondary)
                                .frame(width: 92, alignment: .leading)
                                .help(replaced ? "Ersetzt durch dein eigenes K\u{00FC}rzel" : "Standard-K\u{00FC}rzel, nur auf Apple-Tastaturen")
                            Text(appState.displayName(for: type))
                                .font(.ui(11.5, .medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            HotkeyRecorderButton(appState: appState, type: type)
                        }
                    }
                }

                Text("Eigenes K\u{00FC}rzel rechts festlegen, z.\u{202F}B. \u{2303}\u{2325}D oder F13. Es ersetzt das fn-K\u{00FC}rzel dieses Modus. N\u{00F6}tig f\u{00FC}r externe Tastaturen, dort funktioniert fn nicht. \u{2303}Space und \u{2303}\u{2325}Space belegt macOS f\u{00FC}r die Eingabequelle.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modus")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    SegmentedToggle(
                        options: HotkeyMode.allCases,
                        selection: $appState.appSettings.hotkeyMode,
                        label: { $0.displayName }
                    )
                }
            }

            // MARK: Aufnahme & Einfuegen
            SettingsSection(title: "Aufnahme & Einf\u{00FC}gen") {

                Toggle("Aufnahme unten am Bildschirm zeigen", isOn: $appState.appSettings.showsRecordingIndicator)
                    .toggleStyle(.trailingSwitch)

                Text("Eine kleine lila Anzeige bewegt sich mit deiner Stimme, solange Blitztext aufnimmt und schreibt. Ein Klick darauf stoppt die Aufnahme.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Ton aus w\u{00E4}hrend der Aufnahme", isOn: $appState.appSettings.muteOutputWhileRecording)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Podcast, Musik oder Video sind stumm, solange Blitztext aufnimmt, und danach sofort wieder zu h\u{00F6}ren. Pausieren kann Blitztext sie nicht, weil macOS Apps nicht verr\u{00E4}t, was gerade l\u{00E4}uft.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Zwischenablage danach wiederherstellen", isOn: $appState.appSettings.restoreClipboardAfterPaste)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Was du vorher kopiert hattest, ist nach dem Einf\u{00FC}gen wieder da.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Automatische Abs\u{00E4}tze", isOn: $appState.appSettings.automaticParagraphs)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Lange Diktate und Audiodateien bekommen nach etwa vier S\u{00E4}tzen einen Absatz. W\u{00F6}rter und Satzzeichen bleiben, wie sie sind.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("An den Text am Cursor anpassen", isOn: $appState.appSettings.fitToSurroundingText)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Setzt Leerzeichen und Gro\u{00DF}- und Kleinschreibung passend zum Text davor und danach. Blitztext liest dazu das Textfeld \u{00FC}ber die Bedienungshilfen, Passwortfelder nie.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Verlauf aufbewahren")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    SegmentedToggle(
                        options: HistoryRetention.allCases,
                        selection: $appState.appSettings.historyRetention,
                        label: { $0.displayName }
                    )

                    Text("Nur auf diesem Mac und verschl\u{00FC}sselt. Aus l\u{00F6}scht den Verlauf sofort.")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LaunchAtLoginSection()

            AboutBlitztextSection(appState: appState)
            }

            if pane == .models {
            // MARK: Spracherkennung
            SettingsSection(title: "Spracherkennung") {

                Text("Blitztext transkribiert immer auf diesem Mac. Das Audio verlässt das Gerät nicht.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: appState.selectedLocalModelIsInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.ui(11, .semibold))
                        .foregroundStyle(appState.selectedLocalModelIsInstalled ? BlitztextTheme.accent : .secondary)
                    Text(appState.selectedLocalModelIsInstalled ? installedModelsText : "Das ausgewählte Modell wird beim Installieren lokal gespeichert.")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("Lokales Modell")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(localModelOptions) { model in
                            Text(model.pickerLabel).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let rating = LocalModelRating.rating(for: appState.selectedLocalModelName) {
                    ModelRatingPanel(rating: rating, modelName: appState.selectedLocalModelName)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                            .font(.ui(12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(appState.localModelDownloadButtonTitle) {
                            appState.installSelectedLocalModel()
                        }
                        .controlSize(.small)
                        .disabled(appState.selectedLocalModelIsInstalled)

                        Link("Modellseite", destination: LocalTranscriptionService.modelPageURL(for: appState.selectedLocalModelName))
                            .font(.ui(10.5, .medium))
                    }
                }

                if let errorText = appState.localModelDownloadErrorText {
                    Text(errorText)
                        .font(.ui(12))
                        .foregroundStyle(BlitztextTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: KI-Modi
            SettingsSection(title: "KI-Modi") {

                Picker("", selection: $appState.appSettings.rewriteEngine) {
                    ForEach(TextRewriter.Engine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(aiEngineStatusText)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("KI-Modi sehen den Text am Cursor", isOn: $appState.appSettings.aiSeesFieldContext)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Blitztext+, $%&! und :) bekommen den Text rund um den Cursor als Kontext, etwa die Mail, auf die du antwortest. Mit einem Modell-Anbieter geht dieser Text mit an den Anbieter.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LocalLanguageModelSection()

            MacAIProviderSection(appState: appState)
            }

            if pane == .workflows {
            // MARK: Blitztext+
            SettingsSection(title: appState.displayName(for: .textImprover)) {
                ModeSummary(appState: appState, type: .textImprover)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Schreibstil")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    SegmentedToggle(
                        options: TextImprovementSettings.TextTone.allCases,
                        selection: $appState.textImprovementSettings.tone,
                        label: { $0.displayName }
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Kontext")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    TextField("z.B. \"E-Mails im Bereich Unternehmensberatung\"", text: $appState.textImprovementSettings.context)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(12))
                }

                DisclosureGroup(isExpanded: $showsImproverPrompt) {
                    PromptEditor(
                        text: $appState.textImprovementSettings.systemPrompt,
                        placeholder: "z.B. \"Schreibe pr\u{00E4}gnant und ohne F\u{00FC}llw\u{00F6}rter.\"",
                        height: 64
                    )
                    .padding(.top, 6)
                } label: {
                    Text(appState.textImprovementSettings.systemPrompt.isEmpty ? "Eigene Anweisung" : "Eigene Anweisung (aktiv)")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Blitztext $%&!
            SettingsSection(title: appState.displayName(for: .dampfAblassen)) {
                ModeSummary(appState: appState, type: .dampfAblassen)

                DisclosureGroup(isExpanded: $showsDampfPrompt) {
                    VStack(alignment: .leading, spacing: 6) {
                        PromptEditor(
                            text: $appState.dampfAblassenSettings.systemPrompt,
                            placeholder: "z.B. \"Formuliere den Text sachlich und freundlich um.\"",
                            height: 110
                        )
                        if dampfPromptIsCustom {
                            Button("Standard wiederherstellen") {
                                appState.dampfAblassenSettings.systemPrompt = ModePrompts.dampfAblassenDefault
                            }
                            .buttonStyle(SubtleButtonStyle())
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(dampfPromptIsCustom ? "Anweisung (angepasst)" : "Anweisung (Standard)")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Blitztext :)
            SettingsSection(title: appState.displayName(for: .emojiText)) {
                ModeSummary(appState: appState, type: .emojiText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Emoji-Dichte")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)

                    SegmentedToggle(
                        options: EmojiTextSettings.EmojiDensity.allCases,
                        selection: $appState.emojiTextSettings.emojiDensity,
                        label: { $0.displayName }
                    )
                }
            }

            AppModeRulesSection(appState: appState)
            }

            if pane == .dictionary {
            // MARK: Eigennamen
            SettingsSection(title: "Eigennamen") {

                Text("Namen und Fachbegriffe, die Blitztext genau so schreiben soll. KI-Modi \u{00FC}bernehmen sie unver\u{00E4}ndert.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Term chips
                if !appState.textImprovementSettings.customTerms.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(appState.textImprovementSettings.customTerms, id: \.self) { term in
                            HStack(spacing: 3) {
                                Text(term)
                                    .font(.ui(12))
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        appState.textImprovementSettings.customTerms.removeAll { $0 == term }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.ui(7, .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(SubtleButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
                            )
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Neuer Begriff", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(12))
                        .onSubmit { addTerm() }

                    Button { addTerm() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.ui(16))
                            .foregroundStyle(BlitztextTheme.accent)
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Toggle("Eigennamen automatisch korrigieren", isOn: $appState.appSettings.correctCustomTermsEnabled)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))

                Text("Korrigiert \u{00E4}hnlich klingende Schreibweisen auf deine Eigennamen, z.\u{202F}B. \u{201E}Black Boat\u{201C} zu \u{201E}Blackboat\u{201C}. Echte W\u{00F6}rter bleiben unver\u{00E4}ndert.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: "Ersetzungen") {
                Text("F\u{00FC}r Begriffe, die anders klingen, als sie geschrieben werden. Zum Beispiel wird aus \u{201E}n acht n\u{201C} immer \u{201E}n8n\u{201C}.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(appState.textImprovementSettings.replacements) { rule in
                    HStack(spacing: 6) {
                        Text(rule.spoken)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.ui(8, .semibold))
                            .foregroundStyle(.tertiary)
                        Text(rule.written)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                appState.textImprovementSettings.replacements.removeAll { $0.id == rule.id }
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.ui(7, .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(SubtleButtonStyle())
                        .help("Ersetzung entfernen")
                    }
                    .font(.ui(12))
                }

                HStack(spacing: 6) {
                    TextField("Gesprochen", text: $newSpoken)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(12))
                    Image(systemName: "arrow.right")
                        .font(.ui(9))
                        .foregroundStyle(.tertiary)
                    TextField("Geschrieben", text: $newWritten)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(12))
                        .onSubmit { addReplacement() }
                    Button { addReplacement() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.ui(16))
                            .foregroundStyle(BlitztextTheme.accent)
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(!canAddReplacement)
                }
            }

            SettingsSection(title: "F\u{00FC}llw\u{00F6}rter") {
                Toggle("\u{201E}\u{00C4}h\u{201C} und \u{201E}\u{00E4}hm\u{201C} entfernen", isOn: $appState.appSettings.removeFillerWordsEnabled)
                    .toggleStyle(.trailingSwitch)
                    .font(.ui(11.5))
            }
            }

        }
    }

    private var dampfPromptIsCustom: Bool {
        appState.dampfAblassenSettings.systemPrompt != ModePrompts.dampfAblassenDefault
    }

    private var canAddReplacement: Bool {
        !newSpoken.trimmingCharacters(in: .whitespaces).isEmpty && !newWritten.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addReplacement() {
        guard canAddReplacement else { return }
        let rule = TermReplacement(
            spoken: newSpoken.trimmingCharacters(in: .whitespaces),
            written: newWritten.trimmingCharacters(in: .whitespaces)
        )
        withAnimation(.easeOut(duration: 0.15)) {
            appState.textImprovementSettings.replacements.removeAll { $0.id == rule.id }
            appState.textImprovementSettings.replacements.append(rule)
        }
        newSpoken = ""
        newWritten = ""
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appState.textImprovementSettings.customTerms.contains(trimmed) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            appState.textImprovementSettings.customTerms.append(trimmed)
        }
        newTerm = ""
    }
}

// MARK: - Mode settings helpers

/// What a mode does and which shortcut starts it, at the top of its settings.
private struct ModeSummary: View {
    @Bindable var appState: AppState
    let type: WorkflowType

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(type.subtitle)
                .font(.ui(12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(appState.hotkeyLabel(for: type))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Multi-line instruction field with a placeholder.
private struct PromptEditor: View {
    @Binding var text: String
    let placeholder: String
    let height: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.ui(12))
            .frame(height: height)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.ui(12))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderButton: View {
    @Bindable var appState: AppState
    let type: WorkflowType

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var globalMonitor: Any?
    @State private var needsModifierHint = false
    /// fn cannot be part of a global shortcut; macOS does not report it to Carbon hotkeys.
    @State private var fnHint = false

    private var combo: KeyCombo? {
        appState.appSettings.customHotkey(for: type)
    }

    private var registrationFailed: Bool {
        combo != nil && appState.hotkeyService.failedCustomHotkeys.contains(type)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 10.5, weight: .medium, design: combo == nil || isRecording ? .default : .rounded))
                    .foregroundStyle(isRecording ? BlitztextTheme.accent : (combo == nil ? .secondary : .primary))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording ? BlitztextTheme.accent.opacity(0.12) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(registrationFailed ? BlitztextTheme.danger : Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help(helpText)

            if combo != nil && !isRecording {
                Button {
                    appState.setCustomHotkey(nil, for: type)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ui(10.5))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(SubtleButtonStyle())
                .help("Eigenes K\u{00FC}rzel entfernen")
            }
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if isRecording {
            if fnHint { return "fn geht nicht" }
            return needsModifierHint ? "+ \u{2303}\u{2325}\u{2318}" : "Dr\u{00FC}cken ..."
        }
        if let combo {
            return combo.displayLabel.replacingOccurrences(of: " + ", with: "")
        }
        return "Eigenes"
    }

    private var helpText: String {
        if registrationFailed {
            return "Dieses K\u{00FC}rzel ist bereits von macOS oder einer anderen App belegt."
        }
        return isRecording
            ? "Tastenkombination mit \u{2303}, \u{2325} oder \u{2318} dr\u{00FC}cken (fn geht nicht), Escape bricht ab."
            : "Eigenes Tastenk\u{00FC}rzel festlegen"
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        needsModifierHint = false
        fnHint = false
        appState.hotkeyService.setCustomHotkeysSuspended(true)

        // A local monitor only sees keys while Blitztext is the active app. The
        // settings live in a popover of an accessory app, so make sure it is key.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible && $0.canBecomeKey && $0.className.contains("Popover") }?.makeKey()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleCaptured(event)
            return nil
        }
        // Fallback when another app keeps focus anyway (needs Accessibility,
        // which Blitztext already has for pasting). The key press still reaches
        // that app, but the shortcut gets recorded.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async { handleCaptured(event) }
        }
    }

    private func handleCaptured(_ event: NSEvent) {
        guard isRecording else { return }
        switch KeyCombo.capture(from: event) {
        case .combo(let combo):
            appState.setCustomHotkey(combo, for: type)
            stopRecording()
        case .cancelled:
            stopRecording()
        case .needsModifier:
            needsModifierHint = true
            fnHint = event.modifierFlags.contains(.function)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        monitor = nil
        globalMonitor = nil
        isRecording = false
        needsModifierHint = false
        fnHint = false
        appState.hotkeyService.setCustomHotkeysSuspended(false)
    }
}

// MARK: - Flow Layout (for term tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
