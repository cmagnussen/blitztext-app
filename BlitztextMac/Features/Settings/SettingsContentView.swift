import SwiftUI
import AppKit
import AVFoundation

struct SettingsContentView: View {
    /// Der Tab "Zugang", in dem unter anderem der Abschnitt Updates steckt.
    static let accessTabIndex = 1

    @Bindable var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Three-tab segmented picker
            Picker("", selection: $selectedTab) {
                Text("Anpassen").tag(0)
                Text("Zugang").tag(1)
                Text("Verlauf").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                switch selectedTab {
                case 0:
                    CustomizeSettingsView(appState: appState)
                case 2:
                    DictationHistoryView()
                default:
                    AccessSettingsView(appState: appState)
                }
            }
        }
        .onAppear {
            appState.refreshAccessibilityPermission()
            // Eine gezielte Vorgabe gilt genau einmal, danach wieder die
            // uebliche Vorauswahl.
            if let vorgabe = appState.settingsTabSeed {
                appState.settingsTabSeed = nil
                selectedTab = vorgabe
            } else {
                selectedTab = defaultTabSelection
            }
        }
    }

    private var defaultTabSelection: Int {
        if !appState.accessibilityPermissionGranted {
            return 1
        }
        if appState.isConfigured && !BlitztextInstallLocationService.shouldOfferMoveToApplications {
            return 0
        }
        return 1
    }
}

// MARK: - Section Label (quiet style)

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Dictation History (Verlauf, debug)

/// Plays back history recordings, one at a time. AVAudioPlayer handles the m4a
/// recordings the workflows produce.
@MainActor
@Observable
final class HistoryAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = HistoryAudioPlayer()
    var playingID: UUID?
    private var player: AVAudioPlayer?

    func toggle(_ entry: DictationHistoryEntry) {
        if playingID == entry.id {
            stop()
            return
        }
        guard let url = entry.audioURL else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.play()
            player = newPlayer
            playingID = entry.id
        } catch {
            playingID = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

private struct DictationHistoryView: View {
    private let store = DictationHistoryStore.shared
    private let audio = HistoryAudioPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Verlauf · letzte 10")
                Spacer()
                if !store.entries.isEmpty {
                    Button("Löschen") {
                        audio.stop()
                        store.clear()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }

            Text("Nur diese Sitzung, nur zum Debuggen: Aufnahme anhören und prüfen, ob richtig erkannt wurde.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.entries.isEmpty {
                Text("Noch keine Aufnahmen in dieser Sitzung.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(store.entries) { entry in
                    DictationHistoryRow(entry: entry, audio: audio)
                }
            }
        }
        .padding(16)
    }
}

private struct DictationHistoryRow: View {
    let entry: DictationHistoryEntry
    let audio: HistoryAudioPlayer

    private var isPlaying: Bool { audio.playingID == entry.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if entry.audioURL != nil {
                    Button {
                        audio.toggle(entry)
                    } label: {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .help("Keine Audiodatei gespeichert")
                }
                Text(entry.workflow.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(Self.timeFormatter.string(from: entry.date))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            labeled("Eingabe (erkannt)", entry.input)
            if entry.output != entry.input {
                labeled("Ausgabe (eingefügt)", entry.output)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }

    @ViewBuilder
    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "(leer)" : value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Access Settings (Tab 1: Zugang)

struct AccessSettingsView: View {
    private static let openAIAPIKeyPattern = #"^sk-[A-Za-z0-9_-]{20,}$"#

    @Bindable var appState: AppState

    private enum FieldFocus {
        case openAIAPIKey
        case liteLLMAPIKey
    }

    @State private var launchAtLoginService = LaunchAtLoginService()
    @State private var currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
    @State private var openAIAPIKey = ""
    @State private var editingAPIKey = false
    @State private var liteLLMAPIKey = ""
    @State private var editingLiteLLMKey = false
    @State private var saved = false
    @State private var saveErrorText: String?
    @State private var installActionErrorText: String?
    @State private var showCleanupOptions = false
    @State private var deleteLocalDataOnCleanup = true
    @State private var cleanupStatusText: String?
    @State private var cleanupErrorText: String?
    @FocusState private var focusedField: FieldFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Berechtigungen")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: appState.accessibilityPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.accessibilityPermissionGranted ? .green : .orange)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.accessibilityPermissionGranted ? "Direktes Einfügen ist freigegeben." : "Direktes Einfügen ist noch nicht freigegeben.")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Öffne Bedienungshilfen und aktiviere Blitztext. Falls Blitztext schon aktiv ist, einmal aus- und wieder einschalten.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Button("Bedienungshilfen öffnen") {
                        appState.requestAccessibilityPermission()
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Button("Erneut prüfen") {
                        appState.refreshAccessibilityPermission()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Anbieter")

                Picker("", selection: $appState.appSettings.apiProvider) {
                    ForEach(APIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if appState.appSettings.apiProvider == .openAI {
                    openAIKeySection
                } else {
                    liteLLMSection
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Installation")

                Text(installationHeadline)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(installationDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(BlitztextInstallLocationService.bundleURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                    Text("Weitere Blitztext-Kopien auf diesem Mac können doppelte Login-Items auslösen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
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
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Updates")

                Text("Installiert: Version \(Self.installierteVersion)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                switch appState.updateController.state {
                case .idle:
                    Text(letztePruefungText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .checking:
                    Text("Suche nach Updates ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .upToDate:
                    Text("Blitztext ist aktuell. \(letztePruefungText)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .available(let release):
                    Text("Version \(release.version.description) ist verfügbar.")
                        .font(.system(size: 11, weight: .medium))

                    if !release.releaseNotes.isEmpty {
                        Text(release.releaseNotes.prefix(400))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sperre = appState.updateController.currentInstallBlock {
                        Text(sperre.hinweis)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button("Version \(release.version.description) laden und installieren") {
                            appState.updateController.installAvailableUpdate()
                        }
                        .buttonStyle(SubtleButtonStyle())

                        Text("Blitztext startet sich für das Update neu.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                case .downloading(let anteil):
                    Text("Lade Update ... \(Int(anteil * 100)) Prozent")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .verifying:
                    Text("Prüfe die Signatur ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .installing:
                    Text("Installiere und starte neu ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .failed(let text):
                    Text(text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("Nach Updates suchen") {
                        appState.updateController.checkForUpdates(manuell: true)
                    }
                    .buttonStyle(SubtleButtonStyle())

                    if let seite = UpdateConfiguration.releasesPageURL {
                        Button("Releases im Browser") {
                            NSWorkspace.shared.open(seite)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                Toggle("Automatisch nach Updates suchen", isOn: Binding(
                    get: { appState.updateController.automaticChecksEnabled },
                    set: { appState.updateController.automaticChecksEnabled = $0 }
                ))
                .toggleStyle(.switch)

                if !currentInstallLocation.isCanonicalInstall {
                    Text("Hotkeys und Login-Start laufen am stabilsten, "
                        + "wenn Blitztext aus /Applications gestartet wird.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Beim Anmelden")

                Toggle("Blitztext automatisch starten", isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { launchAtLoginService.setEnabled($0) }
                ))
                .toggleStyle(.switch)

                Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        launchAtLoginService.errorText == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.red)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let saveErrorText {
                Text(saveErrorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Hinweis")

                Text("Fuer direktes Einfuegen: Blitztext einmal nach /Applications legen und danach Mikrofon sowie Bedienungshilfen erlauben.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Sauber Entfernen")

                Text("Vor dem Löschen Blitztext erst auf diesem Mac bereinigen. So verschwinden Anmeldestart und lokale Daten sauber aus dem Weg.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showCleanupOptions {
                    Toggle("Zugangsdaten und Einstellungen dieses Macs löschen", isOn: $deleteLocalDataOnCleanup)
                        .toggleStyle(.switch)

                    Text("Danach Blitztext beenden und die App aus /Applications löschen. Bereits verwaiste alte Login-Items können in den Systemeinstellungen einmalig manuell entfernt werden.")
                        .font(.system(size: 10.5))
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
                        .foregroundStyle(.red)
                    }
                } else {
                    Button("Entfernung vorbereiten") {
                        showCleanupOptions = true
                    }
                    .buttonStyle(SubtleButtonStyle())
                }

                if let cleanupStatusText {
                    Text(cleanupStatusText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cleanupErrorText {
                    Text(cleanupErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Save button (right-aligned, text only)
            HStack {
                Spacer()
                Button {
                    save()
                } label: {
                    if saved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Gespeichert")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                    } else {
                        Text("Speichern")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                .animation(.easeInOut(duration: 0.2), value: saved)
            }
        }
        .padding(16)
        .onAppear {
            launchAtLoginService.refresh()
            refreshInstallState()
            load()
            if appState.appSettings.apiProvider == .openAI, !appState.hasValue(for: .openAIAPIKey) {
                editingAPIKey = true
                focusedField = .openAIAPIKey
            } else if appState.appSettings.apiProvider == .liteLLM, !appState.hasValue(for: .liteLLMAPIKey) {
                editingLiteLLMKey = true
                focusedField = .liteLLMAPIKey
            }
        }
    }

    private static let installierteVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    private var letztePruefungText: String {
        guard let zeitpunkt = appState.updateController.lastCheck else {
            return "Noch nicht nach Updates gesucht."
        }
        let formatierer = DateFormatter()
        formatierer.dateStyle = .medium
        formatierer.timeStyle = .short
        return "Zuletzt geprüft: \(formatierer.string(from: zeitpunkt))"
    }

    // MARK: - Provider Sections

    @ViewBuilder
    private var openAIKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "OpenAI API Key")
                Spacer()
                if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                    Button("Aendern") { editingAPIKey = true }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
            }

            if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                maskedKeyRow(for: .openAIAPIKey)
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-...", text: $openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .focused($focusedField, equals: .openAIAPIKey)

                    Button("Einfuegen") {
                        pasteAPIKeyFromClipboard()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            Text("Dein Key bleibt lokal in dieser App. Audio und Text werden direkt an die OpenAI API gesendet.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var liteLLMSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Gateway-URL")
                TextField("http://host:4000", text: $appState.appSettings.liteLLMBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .autocorrectionDisabled(true)
                Text("Basis-URL deines LiteLLM-Proxys, ohne /v1.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "LiteLLM API Key")
                    Spacer()
                    if appState.hasValue(for: .liteLLMAPIKey) && !editingLiteLLMKey {
                        Button("Aendern") { editingLiteLLMKey = true }
                            .font(.system(size: 10, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                }

                if appState.hasValue(for: .liteLLMAPIKey) && !editingLiteLLMKey {
                    maskedKeyRow(for: .liteLLMAPIKey)
                } else {
                    HStack(spacing: 8) {
                        SecureField("sk-...", text: $liteLLMAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .focused($focusedField, equals: .liteLLMAPIKey)

                        Button("Einfuegen") {
                            pasteLiteLLMKeyFromClipboard()
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Modelle")
                modelField(
                    title: "Text verbessern",
                    text: $appState.appSettings.liteLLMFastModel,
                    placeholder: "z. B. gpt-5.5-mini"
                )
                modelField(
                    title: "Dampf ablassen",
                    text: $appState.appSettings.liteLLMStrongModel,
                    placeholder: "z. B. gpt-5.5"
                )
                modelField(
                    title: "Transkription",
                    text: $appState.appSettings.liteLLMTranscriptionModel,
                    placeholder: "z. B. whisper-1"
                )
            }

            Text("Key und URL bleiben lokal. Audio und Text gehen an dein Gateway. Die Modellnamen müssen exakt denen in deiner LiteLLM-Config entsprechen.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func maskedKeyRow(for key: KeychainKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green.opacity(0.8))
            Text(appState.apiKeyDisplayValue(for: key))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func modelField(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .autocorrectionDisabled(true)
        }
    }

    private func load() {
        openAIAPIKey = ""
        liteLLMAPIKey = ""
    }

    private func save() {
        saveErrorText = nil
        cleanupStatusText = nil
        cleanupErrorText = nil
        KeychainService.invalidateCache()

        switch appState.appSettings.apiProvider {
        case .openAI:
            let trimmedAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if editingAPIKey || !appState.hasValue(for: .openAIAPIKey) {
                guard !trimmedAPIKey.isEmpty else {
                    saveErrorText = "Bitte trage deinen OpenAI API Key ein."
                    return
                }
                do {
                    try KeychainService.save(key: .openAIAPIKey, value: trimmedAPIKey)
                    openAIAPIKey = ""
                    editingAPIKey = false
                } catch {
                    saveErrorText = "OpenAI API Key konnte nicht gespeichert werden."
                    return
                }
            }
            KeychainService.invalidateCache()
            if !appState.hasValue(for: .openAIAPIKey) {
                saveErrorText = "OpenAI API Key wurde nicht persistent gespeichert. Bitte App neu starten und erneut versuchen."
                return
            }

        case .liteLLM:
            let trimmedURL = appState.appSettings.liteLLMBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard APIConfiguration.normalizedBaseURL(trimmedURL) != nil else {
                saveErrorText = "Bitte trage eine gültige Gateway-URL ein, inklusive http:// oder https://."
                return
            }
            let trimmedKey = liteLLMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if editingLiteLLMKey || !appState.hasValue(for: .liteLLMAPIKey) {
                guard !trimmedKey.isEmpty else {
                    saveErrorText = "Bitte trage deinen LiteLLM API Key ein."
                    return
                }
                do {
                    try KeychainService.save(key: .liteLLMAPIKey, value: trimmedKey)
                    liteLLMAPIKey = ""
                    editingLiteLLMKey = false
                } catch {
                    saveErrorText = "LiteLLM API Key konnte nicht gespeichert werden."
                    return
                }
            }
            KeychainService.invalidateCache()
            if !appState.hasValue(for: .liteLLMAPIKey) {
                saveErrorText = "LiteLLM API Key wurde nicht persistent gespeichert. Bitte App neu starten und erneut versuchen."
                return
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { saved = false }
        }
    }

    private func pasteAPIKeyFromClipboard() {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            saveErrorText = "Zwischenablage enthält keinen Text."
            return
        }

        let firstLine = rawText.components(separatedBy: .newlines).first ?? rawText
        let trimmedKey = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.range(of: Self.openAIAPIKeyPattern, options: .regularExpression) != nil else {
            saveErrorText = "Zwischenablage enthält keinen plausiblen OpenAI API Key."
            return
        }

        openAIAPIKey = trimmedKey
        NSPasteboard.general.clearContents()
        saveErrorText = nil
    }

    private func pasteLiteLLMKeyFromClipboard() {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            saveErrorText = "Zwischenablage enthält keinen Text."
            return
        }

        let firstLine = rawText.components(separatedBy: .newlines).first ?? rawText
        let trimmedKey = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 8 else {
            saveErrorText = "Zwischenablage enthält keinen plausiblen API Key."
            return
        }

        liteLLMAPIKey = trimmedKey
        NSPasteboard.general.clearContents()
        saveErrorText = nil
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
            return "Fuer stabile Hotkeys und Login-Items sollte Blitztext nur aus /Applications laufen."
        case .outsideApplications:
            return "Verschiebe Blitztext einmal nach /Applications, damit Anmeldestart und Hotkeys sauber bleiben."
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

    private func runCleanup() {
        cleanupStatusText = nil
        cleanupErrorText = nil

        let report = deleteLocalDataOnCleanup
            ? BlitztextCleanupService.cleanupUserData()
            : BlitztextCleanupService.removeLaunchAtLoginRegistration()

        KeychainService.invalidateCache()
        launchAtLoginService.refresh()
        refreshInstallState()

        if deleteLocalDataOnCleanup {
            openAIAPIKey = ""
            liteLLMAPIKey = ""
            editingAPIKey = true
            editingLiteLLMKey = true
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

// MARK: - Customize Settings (Tab 2: Anpassen)

struct CustomizeSettingsView: View {
    @Bindable var appState: AppState
    @State private var newTerm = ""

    private var installedLocalModels: [LocalTranscriptionModel] {
        LocalTranscriptionService.installedModels()
    }

    private var localModelOptions: [LocalTranscriptionModel] {
        LocalTranscriptionService.modelOptions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Lokaler Modus
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Sicherer Lokaler Modus")

                Toggle("Sicherer Lokaler Modus", isOn: $appState.appSettings.secureLocalModeEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: appState.appSettings.secureLocalModeEnabled) { _, newValue in
                        if newValue && !appState.selectedLocalModelIsInstalled {
                            appState.installSelectedLocalModel()
                        }
                    }

                HStack(spacing: 6) {
                    Image(systemName: appState.selectedLocalModelIsInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.selectedLocalModelIsInstalled ? .green : .blue)
                    Text(appState.selectedLocalModelIsInstalled ? "\(installedLocalModels.count) lokales WhisperKit-Modell installiert." : "Das ausgewählte Modell wird beim Installieren lokal gespeichert.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("Lokales Modell")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(localModelOptions) { model in
                            Text("\(model.displayName) · \(model.installStateLabel)").tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                            .font(.system(size: 10.5))
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
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }

                if let errorText = appState.localModelDownloadErrorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: Tastenkuerzel
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Tastenk\u{00FC}rzel")

                VStack(spacing: 6) {
                    ForEach(WorkflowType.mainMenuCases) { type in
                        HStack {
                            Text(type.hotkeyLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 124, alignment: .leading)
                            Text(appState.displayName(for: type))
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                        }
                    }
                }

                // Mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.appSettings.hotkeyMode) {
                        ForEach(HotkeyMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // MARK: Diktat
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Diktat")

                Text("fn + Shift + Option h\u{00E4}lt einen Gedanken in einer Tagesdatei fest, statt ihn am Cursor einzusetzen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ablageordner")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(appState.vaultFolderConfigured
                             ? appState.dictationSettings.vaultFolderPath
                             : "Kein Ordner gew\u{00E4}hlt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(appState.vaultFolderConfigured ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Ordner w\u{00E4}hlen") {
                            chooseVaultFolder()
                        }
                        .font(.system(size: 11))
                    }
                }

                Toggle("Second-Brain-Frontmatter schreiben", isOn: $appState.dictationSettings.writesSecondBrainFrontmatter)
                    .toggleStyle(.switch)
                    .font(.system(size: 11.5))

                if appState.dictationSettings.writesSecondBrainFrontmatter {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sph\u{00E4}re")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $appState.dictationSettings.sphere) {
                            ForEach(DictationSphere.allCases) { sphere in
                                Text(sphere.displayName).tag(sphere)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if appState.dictationQueueCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(appState.dictationQueueCount == 1
                             ? "1 Diktat wartet auf die Ablage."
                             : "\(appState.dictationQueueCount) Diktate warten auf die Ablage.")
                            .font(.system(size: 11))
                        Spacer()
                        Button("Jetzt nachziehen") {
                            appState.flushDictationQueue()
                        }
                        .font(.system(size: 11))
                    }
                }

                if let issue = appState.dictationQueueIssue {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Letzter Versuch abgebrochen: \(issue)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.notificationsDenied {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Benachrichtigungen sind aus. Die Best\u{00E4}tigung erscheint dann nur im Men\u{00FC}leisten-Symbol.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Blitztext+
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext+")

                // Tone
                VStack(alignment: .leading, spacing: 8) {
                    Text("Schreibstil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.textImprovementSettings.tone) {
                        ForEach(TextImprovementSettings.TextTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // System Prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text("Eigene Anweisung")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.textImprovementSettings.systemPrompt)
                        .font(.system(size: 11))
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if appState.textImprovementSettings.systemPrompt.isEmpty {
                                Text("z.B. \"Schreibe pr\u{00E4}gnant und ohne F\u{00FC}llw\u{00F6}rter.\"")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // Context
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kontext")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("z.B. \"E-Mails im Bereich Unternehmensberatung\"", text: $appState.textImprovementSettings.context)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            // MARK: Blitztext $%&!
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext $%&!")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Eigene Anweisung")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.dampfAblassenSettings.systemPrompt)
                        .font(.system(size: 11))
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if appState.dampfAblassenSettings.systemPrompt.isEmpty {
                                Text("z.B. \"Formuliere den Text sachlich und freundlich um.\"")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // MARK: Blitztext :)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext :)")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Emoji-Dichte")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.emojiTextSettings.emojiDensity) {
                        ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // MARK: Eigennamen
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Eigennamen")

                // Term chips
                if !appState.textImprovementSettings.customTerms.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(appState.textImprovementSettings.customTerms, id: \.self) { term in
                            HStack(spacing: 3) {
                                Text(term)
                                    .font(.system(size: 10.5))
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        appState.textImprovementSettings.customTerms.removeAll { $0 == term }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
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
                        .font(.system(size: 11))
                        .onSubmit { addTerm() }

                    Button { addTerm() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

        }
        .padding(16)
        .onAppear {
            appState.refreshNotificationPermission()
            appState.refreshDictationQueueCount()
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appState.textImprovementSettings.customTerms.contains(trimmed) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            appState.textImprovementSettings.customTerms.append(trimmed)
        }
        newTerm = ""
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ausw\u{00E4}hlen"
        panel.message = "Ordner f\u{00FC}r die Diktat-Tagesdateien w\u{00E4}hlen"

        if appState.vaultFolderConfigured {
            panel.directoryURL = URL(fileURLWithPath: appState.dictationSettings.vaultFolderPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setVaultFolder(url)
        appState.flushDictationQueue()
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
