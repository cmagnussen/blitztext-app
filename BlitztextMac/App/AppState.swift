import SwiftUI
import Observation
import AppKit

enum PopoverPage: Equatable {
    case main
    case onboarding
    case settings
    case workflow
}

@Observable
@MainActor
final class AppState {
    private static let pasteRetryInitialAttempts = 22
    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var activeWorkflow: (any Workflow)?
    var page: PopoverPage = .main
    /// Tab, auf dem die Einstellungen einmalig oeffnen sollen. Wer gezielt in
    /// einen Abschnitt fuehrt, setzt den Wert vor dem Wechsel auf `.settings`.
    /// `SettingsContentView` verbraucht ihn beim Erscheinen und setzt ihn
    /// zurueck, danach greift wieder die uebliche Vorauswahl.
    var settingsTabSeed: Int?
    var isPopoverShown = false
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            onMenuBarStatusChange?(menuBarStatus)
        }
    }
    var accessibilityPermissionGranted = false
    var localModelDownloadProgress: Double?
    var localModelDownloadStatusText: String?
    var localModelDownloadErrorText: String?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    private var activeLaunchSource: WorkflowLaunchSource = .manual
    private var activePasteTarget: PasteTarget?
    private var lastPopoverPasteTarget: PasteTarget?
    private var menuBarStatusResetTask: Task<Void, Never>?
    private var workflowCleanupTask: Task<Void, Never>?

    // Persisted settings
    var appSettings: AppSettings {
        didSet {
            saveSettings()
            prewarmLocalTranscriptionIfNeeded()
        }
    }
    var transcriptionSettings: TranscriptionSettings {
        didSet { saveSettings() }
    }
    var textImprovementSettings: TextImprovementSettings {
        didSet { saveSettings() }
    }
    var dampfAblassenSettings: DampfAblassenSettings {
        didSet { saveSettings() }
    }
    var emojiTextSettings: EmojiTextSettings {
        didSet { saveSettings() }
    }
    var dictationSettings: DictationSettings {
        didSet { saveSettings() }
    }

    // Hotkeys
    let hotkeyService = HotkeyService()

    // Diktat
    private let vaultInboxService = VaultInboxService()
    private let dictationQueue = DictationQueueStore(fileURL: AppSupportPaths.dictationQueueURL)
    var dictationQueueCount = 0
    /// Grund, warum der letzte Nachziehversuch vorzeitig endete. nil heisst,
    /// es gab nichts Ungewöhnliches. Wird in den Einstellungen angezeigt.
    var dictationQueueIssue: String?
    var notificationsDenied = false

    // Update
    @ObservationIgnored
    private(set) lazy var updateController: UpdateController = {
        UpdateController(
            automaticChecksEnabled: appSettings.automaticUpdateChecksEnabled,
            lastCheck: appSettings.lastUpdateCheck,
            isBusy: { [weak self] in
                guard let self else { return false }
                return self.activeWorkflow?.phase.isActive ?? false
            },
            onSettingsChange: { [weak self] automatik, zeitpunkt in
                guard let self else { return }
                self.appSettings.automaticUpdateChecksEnabled = automatik
                self.appSettings.lastUpdateCheck = zeitpunkt
            }
        )
    }()

    // Computed

    /// The resolved remote configuration for the currently selected provider,
    /// or `nil` if that provider is not fully configured yet.
    var activeAPIConfiguration: APIConfiguration? {
        APIConfiguration.resolve(settings: appSettings)
    }

    /// Whether the selected remote provider (OpenAI or LiteLLM) is ready to use.
    var remoteProviderConfigured: Bool {
        activeAPIConfiguration != nil
    }

    var isConfigured: Bool {
        remoteProviderConfigured || !LocalTranscriptionService.installedModels().isEmpty
    }
    var shouldShowOnboarding: Bool {
        !isConfigured && !appSettings.hasSeenOnboarding
    }

    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    var vaultFolderConfigured: Bool {
        !dictationSettings.vaultFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        self.appSettings = Self.loadAppSettings()
        self.transcriptionSettings = Self.loadTranscriptionSettings()
        self.textImprovementSettings = Self.loadTextImprovementSettings()
        self.dampfAblassenSettings = Self.loadDampfAblassenSettings()
        self.emojiTextSettings = Self.loadEmojiTextSettings()
        self.dictationSettings = Self.loadDictationSettings()
        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()

        if !dictationSettings.vaultFolderPath.isEmpty {
            flushDictationQueue()
        } else {
            refreshDictationQueueCount()
        }
    }

    // MARK: - Custom Display Names

    func displayName(for type: WorkflowType) -> String {
        switch type {
        case .textImprover:
            let name = textImprovementSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .dampfAblassen:
            let name = dampfAblassenSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .emojiText:
            let name = emojiTextSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        default:
            return type.displayName
        }
    }

    func workflowSubtitle(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            if appSettings.secureLocalModeEnabled {
                let modelName = selectedLocalModelName
                return LocalTranscriptionService.isModelInstalled(modelName)
                    ? "Lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
                    : "Lokales WhisperKit-Modell fehlt."
            }
            return "Online: Transkription über \(appSettings.apiProvider.displayName)."
        case .localTranscription:
            return "Nur lokal. Kein Server."
        case .vaultDictation:
            guard vaultFolderConfigured else {
                return "Kein Ablageordner eingestellt."
            }
            let ordner = URL(fileURLWithPath: dictationSettings.vaultFolderPath).lastPathComponent
            return "In die Tagesdatei in \(ordner)."
        case .textImprover, .dampfAblassen, .emojiText:
            if appSettings.secureLocalModeEnabled {
                return "Im lokalen Modus pausiert."
            }
            return type.subtitle
        }
    }

    var resolvedLocalModelName: String {
        LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedLocalModelName)
    }

    var selectedLocalModelName: String {
        LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelIsInstalled: Bool {
        LocalTranscriptionService.isModelInstalled(selectedLocalModelName)
    }

    var isDownloadingLocalModel: Bool {
        localModelDownloadProgress != nil
    }

    var localModelDownloadButtonTitle: String {
        selectedLocalModelIsInstalled
            ? "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) ist installiert"
            : "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) installieren"
    }

    // MARK: - Workflow Management

    func startWorkflow(_ type: WorkflowType, source: WorkflowLaunchSource = .manual) {
        guard isWorkflowAvailable(type) else {
            if source == .manual {
                page = .settings
            }
            return
        }

        activeWorkflow?.stop()
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        activeLaunchSource = source
        activePasteTarget = capturePasteTarget(for: source)

        let apiConfiguration = activeAPIConfiguration

        switch type {
        case .transcription:
            let workflow = TranscriptionWorkflow(
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: appSettings.secureLocalModeEnabled ? .local : .remote,
                localModelName: selectedLocalModelName,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .localTranscription:
            let workflow = TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: .local,
                localModelName: selectedLocalModelName
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .textImprover:
            guard let apiConfiguration else { page = .settings; return }
            let workflow = TextImprovementWorkflow(
                settings: textImprovementSettings,
                language: transcriptionSettings.language,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .dampfAblassen:
            guard let apiConfiguration else { page = .settings; return }
            let workflow = DampfAblassenWorkflow(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .emojiText:
            guard let apiConfiguration else { page = .settings; return }
            let workflow = EmojiTextWorkflow(
                settings: emojiTextSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .vaultDictation:
            let workflow = TranscriptionWorkflow(
                type: .vaultDictation,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: appSettings.secureLocalModeEnabled ? .local : .remote,
                localModelName: selectedLocalModelName,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            Task { await UserNotificationService.requestAuthorizationIfNeeded() }
            workflow.start()
        }

        page = source.presentsWorkflowPage ? .workflow : .main
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .localTranscription:
            return selectedLocalModelIsInstalled
        case .transcription:
            return appSettings.secureLocalModeEnabled
                ? selectedLocalModelIsInstalled
                : remoteProviderConfigured
        case .vaultDictation:
            guard vaultFolderConfigured else { return false }
            return appSettings.secureLocalModeEnabled
                ? selectedLocalModelIsInstalled
                : remoteProviderConfigured
        case .textImprover, .dampfAblassen, .emojiText:
            return !appSettings.secureLocalModeEnabled && remoteProviderConfigured
        }
    }

    func stopCurrentWorkflow() {
        activeWorkflow?.stop()
    }

    func resetCurrentWorkflow() {
        activeWorkflow?.reset()
        activeWorkflow = nil
        activePasteTarget = nil
        activeLaunchSource = .manual
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        menuBarStatus = .idle
        page = .main
    }

    func enableSecureLocalMode() {
        appSettings.secureLocalModeEnabled = true
        if !selectedLocalModelIsInstalled {
            installSelectedLocalModel()
        }
    }

    func installSelectedLocalModel() {
        guard !isDownloadingLocalModel else { return }

        let modelName = selectedLocalModelName
        localModelDownloadProgress = 0
        localModelDownloadStatusText = "Download startet..."
        localModelDownloadErrorText = nil

        Task {
            do {
                let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
                    modelName: modelName
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localModelDownloadProgress = clampedProgress
                        self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
                appSettings.secureLocalModeEnabled = true
                localModelDownloadProgress = nil
                localModelDownloadStatusText = "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
                localModelDownloadErrorText = nil

                try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
            } catch {
                localModelDownloadProgress = nil
                localModelDownloadStatusText = nil
                localModelDownloadErrorText = error.localizedDescription
            }
        }
    }

    func copyToClipboard(_ text: String) {
        writeSensitiveTextToPasteboard(text)
    }

    // MARK: - Auto-Paste

    /// Copies the text, restores focus when needed, then simulates Cmd+V.
    /// The text intentionally remains on the clipboard as a fallback if paste is blocked.
    private func pasteAtCursor(_ text: String, target: PasteTarget? = nil) {
        writeSensitiveTextToPasteboard(text)

        if isPopoverShown {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
        accessibilityPermissionGranted = trusted
        guard trusted else {
            menuBarStatus = .error(activeWorkflow?.type)
            return
        }

        attemptPasteTrusted(
            target: target,
            attemptsRemaining: Self.pasteRetryInitialAttempts
        )
    }

    private func writeSensitiveTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedPasteboardType)
    }

    func prepareForPopoverPresentation() {
        lastPopoverPasteTarget = captureCurrentFrontmostApp()
        if let activeWorkflow, activeWorkflow.phase.isActive {
            page = .workflow
        } else if shouldShowOnboarding {
            page = .onboarding
            markOnboardingSeen()
        } else if page == .workflow {
            page = .main
        } else if page == .onboarding {
            page = .main
        }
    }

    func markOnboardingSeen() {
        guard !appSettings.hasSeenOnboarding else { return }
        appSettings.hasSeenOnboarding = true
    }

    // MARK: - API Key Status

    func apiKeyDisplayValue(for key: KeychainKey) -> String {
        guard let value = KeychainService.load(key: key), !value.isEmpty else {
            return ""
        }
        if value.count > 8 {
            return String(value.prefix(4)) + " \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
        }
        return "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }

    func hasValue(for key: KeychainKey) -> Bool {
        guard let value = KeychainService.load(key: key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Settings Persistence

    private static let settingsURL: URL = {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        return AppSupportPaths.settingsURL
    }()

    private func saveSettings() {
        let container = SettingsContainer(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            dampfAblassen: dampfAblassenSettings,
            emojiText: emojiTextSettings,
            dictation: dictationSettings
        )
        if let data = try? JSONEncoder().encode(container) {
            try? data.write(to: Self.settingsURL)
        }
    }

    private static func loadAppSettings() -> AppSettings {
        loadContainer()?.app ?? AppSettings()
    }

    private static func loadTranscriptionSettings() -> TranscriptionSettings {
        loadContainer()?.transcription ?? TranscriptionSettings()
    }

    private static func loadTextImprovementSettings() -> TextImprovementSettings {
        loadContainer()?.textImprovement ?? TextImprovementSettings()
    }

    private static func loadDampfAblassenSettings() -> DampfAblassenSettings {
        loadContainer()?.dampfAblassen ?? DampfAblassenSettings()
    }

    private static func loadEmojiTextSettings() -> EmojiTextSettings {
        loadContainer()?.emojiText ?? EmojiTextSettings()
    }

    private static func loadDictationSettings() -> DictationSettings {
        loadContainer()?.dictation ?? DictationSettings()
    }

    private static func loadContainer() -> SettingsContainer? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(SettingsContainer.self, from: data)
    }

    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.currentStatus()
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
        AccessibilityPermissionService.openSystemSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
    }

    private func autoSelectFastLocalModelIfNeeded() {
        guard !appSettings.hasAutoSelectedFastLocalModel,
              LocalTranscriptionService.shouldAutoSelectRecommendedFastModel(
                currentModelName: appSettings.selectedLocalTranscriptionModelName
              ) else {
            return
        }

        appSettings.selectedLocalTranscriptionModelName = LocalTranscriptionService.recommendedFastModelName
        appSettings.hasAutoSelectedFastLocalModel = true
    }

    private func prewarmLocalTranscriptionIfNeeded() {
        guard appSettings.secureLocalModeEnabled,
              LocalTranscriptionService.isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        Task.detached(priority: .utility) {
            try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
        }
    }

    private func handleWorkflowOutput(_ text: String, from workflow: any Workflow) {
        let destination = workflow.type.outputDestination

        switch destination {
        case .cursor:
            pasteAtCursor(text, target: activePasteTarget)
        case .vaultInbox:
            // Bewusst kein pasteAtCursor: es darf kein Text in ein fremdes
            // Fenster rutschen.
            writeToVaultInbox(text)
        }

        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
        scheduleWorkflowCleanup(after: 1.05)
    }

    // MARK: - Diktat in den Vault

    private func writeToVaultInbox(_ text: String) {
        let settings = dictationSettings
        let recordedAt = Date()

        Task { [weak self] in
            guard let self else { return }

            // Vor jedem neuen Schreiben nachziehen, damit die Reihenfolge
            // stimmt und liegengebliebene Gedanken nicht verhungern.
            let vorlauf = await self.dictationQueue.flush(
                using: self.vaultInboxService,
                settings: settings
            )
            self.dictationQueueIssue = vorlauf.stoppedBecause

            do {
                let ziel = try await self.vaultInboxService.append(
                    text: text,
                    recordedAt: recordedAt,
                    settings: settings
                )
                await self.finishVaultWrite(
                    text: text,
                    fileName: ziel.lastPathComponent,
                    queueRemaining: vorlauf.remaining
                )
            } catch {
                await self.handleVaultWriteFailure(
                    text: text,
                    recordedAt: recordedAt,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func finishVaultWrite(text: String, fileName: String, queueRemaining: Int) async {
        dictationQueueCount = queueRemaining
        UserNotificationService.notifyDictationSaved(
            preview: text,
            fileName: fileName,
            olderPending: queueRemaining
        )
    }

    private func handleVaultWriteFailure(text: String, recordedAt: Date, reason: String) async {
        // Zwischenablage zuerst: sie ist sofort greifbar, auch wenn das
        // Ablegen in die Warteschlange scheitert.
        copyToClipboard(text)

        menuBarStatus = .error(.vaultDictation)

        do {
            try await dictationQueue.enqueue(
                QueuedDictation(recordedAt: recordedAt, text: text)
            )
            dictationQueueCount = (try? await dictationQueue.pending())?.count ?? dictationQueueCount
            UserNotificationService.notifyDictationFailed(reason: reason)
        } catch {
            // Auch die Warteschlange ist beschädigt: der Text steht dann
            // ausschließlich in der Zwischenablage, und genau das muss die
            // Meldung sagen, statt fälschlich "liegt in der Warteschlange"
            // zu suggerieren.
            UserNotificationService.notifyDictationFailed(
                reason: "\(reason) Auch das Ablegen in der Warteschlange ist fehlgeschlagen."
            )
        }
    }

    /// Zieht liegengebliebene Diktate nach. Aufgerufen beim Start und von der
    /// Schaltfläche in den Einstellungen.
    func flushDictationQueue() {
        let settings = dictationSettings
        Task { [weak self] in
            guard let self else { return }
            let ergebnis = await self.dictationQueue.flush(
                using: self.vaultInboxService,
                settings: settings
            )
            self.dictationQueueCount = ergebnis.remaining
            self.dictationQueueIssue = ergebnis.stoppedBecause
        }
    }

    func refreshDictationQueueCount() {
        Task { [weak self] in
            guard let self else { return }
            // Ist die Warteschlangendatei beschädigt, bleibt der letzte
            // bekannte Zähler stehen. Ein stilles 0 wäre die falsche
            // Auskunft, denn die Einträge sind ja noch da.
            if let offen = try? await self.dictationQueue.pending() {
                self.dictationQueueCount = offen.count
            }
        }
    }

    func refreshNotificationPermission() {
        Task { [weak self] in
            guard let self else { return }
            self.notificationsDenied = await UserNotificationService.authorizationDenied()
        }
    }

    func setVaultFolder(_ url: URL) {
        dictationSettings.vaultFolderPath = url.path
    }

    private func configureWorkflowHandlers<T: Workflow>(_ workflow: T) {
        workflow.onOutput = { [weak self, weak workflow] text in
            guard let self, let workflow else { return }
            self.handleWorkflowOutput(text, from: workflow)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handleWorkflowPhaseChange(phase, workflow: workflow)
        }
    }

    private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
        menuBarStatusResetTask?.cancel()

        switch phase {
        case .idle:
            if activeWorkflow == nil {
                menuBarStatus = .idle
            }

        case .running:
            menuBarStatus = workflow.isRecording
                ? .recording(workflow.type)
                : .processing(workflow.type)

        case .done:
            menuBarStatus = .success(workflow.type)

        case .error:
            menuBarStatus = .error(workflow.type)
            if activeLaunchSource == .hotkeyBackground {
                activeWorkflow = nil
                activePasteTarget = nil
                page = .main
            }
            scheduleMenuBarStatusReset(after: 1.6)
        }
    }

    private func scheduleWorkflowCleanup(after delay: TimeInterval) {
        guard let workflow = activeWorkflow else { return }

        workflowCleanupTask?.cancel()
        let workflowID = ObjectIdentifier(workflow)

        workflowCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let activeWorkflow = self.activeWorkflow else { return }
            guard ObjectIdentifier(activeWorkflow) == workflowID else { return }

            activeWorkflow.reset()
            self.activeWorkflow = nil
            self.activePasteTarget = nil
            self.activeLaunchSource = .manual
            if !self.isPopoverShown {
                self.page = .main
            }
            self.menuBarStatus = .idle
        }
    }

    private func scheduleMenuBarStatusReset(after delay: TimeInterval) {
        menuBarStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
                self.menuBarStatus = .idle
            }
        }
    }

    private func capturePasteTarget(for source: WorkflowLaunchSource) -> PasteTarget? {
        switch source {
        case .manual:
            return lastPopoverPasteTarget
        case .hotkeyBackground:
            return captureCurrentFrontmostApp()
        }
    }

    private func attemptPasteTrusted(
        target: PasteTarget?,
        attemptsRemaining: Int
    ) {
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let target {
            if frontmostPid == target.processIdentifier {
                performPaste()
                return
            }

            target.application.activate(options: [])
        } else {
            return
        }

        guard attemptsRemaining > 0 else {
            return
        }

        let delay: TimeInterval
        switch attemptsRemaining {
        case 16...:
            delay = 0.015
        case 8...15:
            delay = 0.025
        default:
            delay = 0.04
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptPasteTrusted(
                target: target,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func performPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func captureCurrentFrontmostApp() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let ownPid = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != ownPid else { return nil }

        return PasteTarget(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            application: app
        )
    }
}

private struct SettingsContainer: Codable {
    var app: AppSettings?
    var transcription: TranscriptionSettings
    var textImprovement: TextImprovementSettings
    var dampfAblassen: DampfAblassenSettings?
    var emojiText: EmojiTextSettings?
    var dictation: DictationSettings?
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}

private struct PasteTarget {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let application: NSRunningApplication
}
