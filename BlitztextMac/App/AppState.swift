import SwiftUI
import Observation
import AppKit
import ApplicationServices

enum PopoverPage: Equatable {
    case main
    case onboarding
    case settings
    case workflow
    case history
    case audioFile
    case meeting
    case whatsNew
}

@Observable
@MainActor
final class AppState {
    private static let pasteRetryInitialAttempts = 22
    var activeWorkflow: (any Workflow)?
    var page: PopoverPage = .main
    var isPopoverShown = false
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            publishMenuBarStatus()
        }
    }

    /// While a meeting records, the resting menu bar icon shows that instead of idle.
    func publishMenuBarStatus() {
        onMenuBarStatusChange?(menuBarStatus == .idle && meeting.isRecording ? .meeting : menuBarStatus)
    }
    var accessibilityPermissionGranted = false
    var microphoneDenied = false
    /// No microphone or a very quiet one, checked when the menu opens.
    var microphoneIssue: MicrophoneCheck.Issue?
    var localModelDownloadProgress: Double?
    var localModelDownloadStatusText: String?
    var localModelDownloadErrorText: String?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    /// Tells the status item whether to show the "new" dot.
    var onWhatsNewChange: ((Bool) -> Void)?
    private var whatsNewTask: Task<Void, Never>?
    private var activeLaunchSource: WorkflowLaunchSource = .manual
    private var activePasteTarget: PasteTarget?
    /// The field in focus when the recording ended; text goes there or, if the focus moved on
    /// while the dictation was processed, to the clipboard.
    private var targetField: Task<FocusedFieldReader.FocusSpot?, Never>?
    /// The last text an AI mode inserted, with what was said, for "Wortgenau statt KI-Text".
    private(set) var lastInsertion: LastInsertion?
    /// Shown on the main page after "Wortgenau statt KI-Text" could not replace in place.
    var lastInsertionNotice: String?
    private var lastPopoverPasteTarget: PasteTarget?
    /// The field the active dictation goes into, read when it started.
    private var activeField: FocusedField?
    private var fieldReadTask: Task<Void, Never>?
    private let audioMuter = SystemAudioMuter()
    private var menuBarStatusResetTask: Task<Void, Never>?
    private var workflowCleanupTask: Task<Void, Never>?

    // Persisted settings
    var appSettings: AppSettings {
        didSet {
            saveSettings()
            prewarmLocalTranscriptionIfNeeded()
            if oldValue.customHotkeys != appSettings.customHotkeys {
                hotkeyService.updateCustomHotkeys(appSettings.resolvedCustomHotkeys)
            }
            if oldValue.historyRetention != appSettings.historyRetention {
                history.updateRetention(appSettings.historyRetention)
            }
            if oldValue.showsRecordingIndicator != appSettings.showsRecordingIndicator {
                onRecordingIndicatorSettingChange?()
            }
        }
    }
    /// Lets the recording pill react at once when its setting changes.
    var onRecordingIndicatorSettingChange: (() -> Void)?
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

    // Hotkeys
    let hotkeyService = HotkeyService()
    let appUpdateService = AppUpdateService()
    let history: TranscriptHistoryStore
    let audioFile = AudioFileController()
    @ObservationIgnored private(set) lazy var meeting = MeetingController(store: MeetingStore(persistent: !Self.isToolRun)) { [unowned self] in
        MeetingController.Settings(
            language: self.transcriptionSettings.language,
            postProcessor: self.postProcessor,
            summarizes: self.appSettings.summarizesMeetings,
            engine: self.appSettings.rewriteEngine
        )
    }

    // Computed
    /// Ready once a local speech model is installed; transcription always runs on this Mac.
    var isConfigured: Bool {
        !LocalTranscriptionService.installedModels().isEmpty
    }

    /// The provider connected with the user's own API key, nil for on-device only.
    var aiProvider: AIProviderConfig? = AIProviderStore.config {
        didSet { AIProviderStore.config = aiProvider }
    }
    /// Bumped when a key is saved or removed; the Keychain itself is not observable.
    var aiKeyRevision = 0

    var isAIProviderReady: Bool {
        _ = aiKeyRevision
        _ = aiProvider
        return AIProviderStore.isConfigured
    }

    /// Name of the provider that AI modes use right now, nil when everything stays on this Mac.
    var providerInUse: String? {
        _ = aiKeyRevision
        guard !TextRewriter.runsLocally(engine: appSettings.rewriteEngine), isAIProviderReady else { return nil }
        return aiProvider?.provider.displayName
    }

    /// Blitztext+, $%&! and :) can run: on this Mac (Apple Intelligence) or via the provider.
    var canRewrite: Bool {
        _ = aiKeyRevision
        _ = aiProvider
        return TextRewriter.canRewrite(engine: appSettings.rewriteEngine)
    }
    /// The setup assistant opens until it is finished or put off with "Später". Granting a
    /// permission closes the popover, so showing it once is not enough.
    var shouldShowOnboarding: Bool {
        (!appSettings.hasSeenOnboarding || keepsSetupAssistantOpen) && !isSetupComplete
    }

    /// Microphone, Accessibility and the selected speech model: what dictation needs.
    var isSetupComplete: Bool {
        selectedLocalModelIsInstalled && accessibilityPermissionGranted && MicrophonePermission.isAuthorized
    }

    /// Opened again from the "Einrichtung starten" card: it comes back like on the first
    /// run until it is done or closed.
    var keepsSetupAssistantOpen = false
    /// "Bedienungshilfen öffnen" was pressed; the assistant then offers the reset for a stale
    /// grant. Kept here because the assistant's view goes when System Settings closes the popover.
    var hasRequestedAccessibility = false


    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    /// Snapshot runs and meeting checks (debug tools): no keychain, no model loading, no
    /// settings changes.
    static var isToolRun: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "BlitztextSnapshotDir") != nil
            || UserDefaults.standard.string(forKey: "BlitztextMeetingCheck") != nil
        #else
        false
        #endif
    }

    init() {
        let loadedAppSettings = Self.loadAppSettings()
        self.appSettings = loadedAppSettings
        self.transcriptionSettings = Self.loadTranscriptionSettings()
        self.textImprovementSettings = Self.loadTextImprovementSettings()
        self.dampfAblassenSettings = Self.loadDampfAblassenSettings()
        self.emojiTextSettings = Self.loadEmojiTextSettings()
        self.history = TranscriptHistoryStore(retention: loadedAppSettings.historyRetention)
        if Self.isToolRun { return }
        meeting.onPhaseChange = { [unowned self] in self.publishMenuBarStatus() }
        meeting.onEvaluationEnd = { [unowned self] result in
            // With the menu open the result is on screen already.
            guard !self.isPopoverShown else { return }
            switch result {
            case .success(let record): MeetingNotifier.finished(record)
            case .failure(let failure): MeetingNotifier.failed(failure.message)
            }
        }
        hotkeyService.updateCustomHotkeys(appSettings.resolvedCustomHotkeys)
        refreshAccessibilityPermission()
        migrateToSetupAssistant()
        KeychainService.removeLegacyServerCredentials()
        AudioRecorder.removeLeftoverRecordings()
        preferParakeetIfNothingInstalled()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()
        upgradeParakeetIfNeeded()
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
        case .tapTalk, .localTapTalk:
            let modelName = selectedLocalModelName
            return LocalTranscriptionService.isModelInstalled(modelName)
                ? "Lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
                : "Lokales Sprachmodell fehlt."
        case .textImprover, .dampfAblassen, .emojiText:
            guard canRewrite else {
                return "Braucht Apple Intelligence oder einen API-Key."
            }
            return type.subtitle
        }
    }

    /// Badge label: the custom shortcut when set, otherwise the built-in fn shortcut.
    func hotkeyLabel(for type: WorkflowType) -> String {
        appSettings.customHotkey(for: type)?.displayLabel ?? type.hotkeyLabel
    }

    func setCustomHotkey(_ combo: KeyCombo?, for type: WorkflowType) {
        if let combo {
            // One shortcut can only trigger one workflow.
            for (rawValue, existing) in appSettings.customHotkeys where existing.keyCode == combo.keyCode
                && existing.modifiers == combo.modifiers && rawValue != type.rawValue {
                appSettings.customHotkeys.removeValue(forKey: rawValue)
            }
            appSettings.customHotkeys[type.rawValue] = combo
        } else {
            appSettings.customHotkeys.removeValue(forKey: type.rawValue)
        }
    }

    var postProcessor: TranscriptPostProcessor {
        TranscriptPostProcessor(
            customTerms: textImprovementSettings.customTerms,
            replacements: textImprovementSettings.replacements,
            correctCustomTerms: appSettings.correctCustomTermsEnabled,
            removeFillerWords: appSettings.removeFillerWordsEnabled,
            language: transcriptionSettings.language,
            isDictionaryWord: DictionaryWordChecker.isKnownWord
        )
    }

    var resolvedLocalModelName: String {
        LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedLocalModelName)
    }

    var selectedLocalModelName: String {
        let name = LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
        // Both turbo builds are one entry in the list; resolve to the build this Mac uses.
        guard LocalTranscriptionService.turboModelNames.contains(name) else { return name }
        return LocalTranscriptionService.turboModelName(selected: name)
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
        targetField = nil
        // A new dictation makes the offer for the previous one stale.
        lastInsertion = nil
        readActiveField()

        switch type {
        case .tapTalk:
            let workflow = TranscriptionWorkflow(
                language: transcriptionSettings.language,
                localModelName: selectedLocalModelName,
                postProcessor: postProcessor
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .localTapTalk:
            let workflow = TranscriptionWorkflow(
                type: .localTapTalk,
                language: transcriptionSettings.language,
                localModelName: selectedLocalModelName,
                postProcessor: postProcessor
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .textImprover:
            let workflow = TextImprovementWorkflow(
                settings: textImprovementSettings,
                language: transcriptionSettings.language,
                localModelName: selectedLocalModelName,
                rewriteEngine: appSettings.rewriteEngine,
                postProcessor: postProcessor,
                fieldContext: fieldContextForAI
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .dampfAblassen:
            let workflow = DampfAblassenWorkflow(
                settings: dampfAblassenSettings,
                language: transcriptionSettings.language,
                localModelName: selectedLocalModelName,
                rewriteEngine: appSettings.rewriteEngine,
                postProcessor: postProcessor,
                fieldContext: fieldContextForAI
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .emojiText:
            let workflow = EmojiTextWorkflow(
                settings: emojiTextSettings,
                language: transcriptionSettings.language,
                localModelName: selectedLocalModelName,
                rewriteEngine: appSettings.rewriteEngine,
                postProcessor: postProcessor,
                fieldContext: fieldContextForAI
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()
        }

        // An online meeting records the Mac's sound; muting it would cut the call out.
        if appSettings.muteOutputWhileRecording, activeWorkflow?.isRecording == true, !meeting.isRecordingSystemAudio {
            audioMuter.mute()
        }
        page = source.presentsWorkflowPage ? .workflow : .main
    }

    /// The mode a shortcut starts in the frontmost app. Only the Blitztext shortcut
    /// follows "Modus je App"; the other shortcuts stay explicit. A website rule wins over
    /// the rule for its browser. A rule whose AI mode cannot run falls back to plain dictation.
    func modeForShortcut(_ type: WorkflowType, frontmostApp: NSRunningApplication?) -> WorkflowType {
        guard type == .tapTalk, let app = frontmostApp else { return type }

        if !appSettings.websiteModeRules.isEmpty,
           FocusedFieldReader.isBrowser(app.bundleIdentifier),
           let host = FocusedFieldReader.webHost(pid: app.processIdentifier, bundleID: app.bundleIdentifier),
           let rule = appSettings.websiteModeRules
               .filter({ WebsiteHost.matches(host, rule: $0.host) })
               .max(by: { $0.host.count < $1.host.count }),
           isWorkflowAvailable(rule.mode) {
            return rule.mode
        }

        if let rule = appSettings.appModeRules.first(where: { $0.bundleID == app.bundleIdentifier }),
           isWorkflowAvailable(rule.mode) {
            return rule.mode
        }
        return type
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .tapTalk, .localTapTalk:
            return selectedLocalModelIsInstalled
        case .textImprover, .dampfAblassen, .emojiText:
            return selectedLocalModelIsInstalled && canRewrite
        }
    }

    /// Every way of ending a recording comes here (shortcut, Escape, pill, menu).
    func stopCurrentWorkflow() {
        guard let workflow = activeWorkflow else { return }
        if workflow.isRecording { noteTargetField() }
        workflow.stop()
    }

    /// The text goes into the field that has the focus when the recording ends, so clicking
    /// into the right field while still talking is fine; only a move during the processing
    /// sends the text to the clipboard.
    private func noteTargetField() {
        guard let target = activePasteTarget else {
            targetField = nil
            return
        }
        let pid = target.processIdentifier
        let bundleID = target.bundleIdentifier
        targetField = Task.detached(priority: .userInitiated) {
            FocusedFieldReader.focusSpot(pid: pid, bundleID: bundleID, textFieldOnly: true)
        }
    }

    /// Gives the Mac its sound back, e.g. when Blitztext quits during a recording.
    func restoreAudioOutput() {
        audioMuter.restoreIfNeeded()
    }

    func resetCurrentWorkflow() {
        activeWorkflow?.reset()
        audioMuter.restoreIfNeeded()
        activeWorkflow = nil
        activePasteTarget = nil
        activeLaunchSource = .manual
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        menuBarStatus = .idle
        page = .main
    }

    func installSelectedLocalModel() {
        guard !isDownloadingLocalModel else { return }

        let modelName = selectedLocalModelName
        localModelDownloadProgress = 0
        localModelDownloadStatusText = "Download startet..."
        localModelDownloadErrorText = nil

        Task {
            do {
                _ = try await LocalTranscriptionService.shared.downloadAndInstall(
                    modelName: modelName
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localModelDownloadProgress = clampedProgress
                        self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                appSettings.selectedLocalTranscriptionModelName = LocalTranscriptionService.normalizedModelName(modelName)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Auto-Paste

    /// Restores focus when needed, then pastes via Cmd+V.
    /// With `restoreClipboardAfterPaste` the previous clipboard comes back once the target app
    /// has read the text. Otherwise, or when pasting is impossible, the text stays on the clipboard.
    private func pasteAtCursor(_ text: String, target: PasteTarget? = nil) {
        if isPopoverShown {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
        accessibilityPermissionGranted = trusted
        guard trusted else {
            copyToClipboard(text)
            menuBarStatus = .error(activeWorkflow?.type)
            return
        }

        attemptPasteTrusted(
            text: text,
            target: target,
            attemptsRemaining: Self.pasteRetryInitialAttempts
        )
    }

    // MARK: - History

    func pasteFromHistory(_ entry: TranscriptHistoryEntry) {
        pasteAtCursor(entry.text, target: lastPopoverPasteTarget)
    }

    func prepareForPopoverPresentation() {
        lastPopoverPasteTarget = captureCurrentFrontmostApp()
        microphoneDenied = MicrophonePermission.isDenied
        microphoneIssue = MicrophoneCheck.issue
        noteSetupProgress()
        history.prune()
        // A running file transcription or meeting comes before the assistant.
        let hasWorkInProgress = audioFile.isWorking || meeting.isRecording || meeting.isProcessing
        if let activeWorkflow, activeWorkflow.phase.isActive {
            page = .workflow
        } else if shouldShowOnboarding, !hasWorkInProgress {
            page = .onboarding
        } else if hasUnseenWhatsNew {
            page = .whatsNew
        } else if page == .workflow {
            page = .main
        } else if page == .onboarding {
            page = .main
        }
    }

    /// "Los geht's" or "Später": the assistant does not open by itself again.
    func finishSetupAssistant() {
        markOnboardingSeen()
        keepsSetupAssistantOpen = false
        page = .main
    }

    /// From the "Einrichtung starten" card on the main page.
    func openSetupAssistant() {
        keepsSetupAssistantOpen = true
        page = .onboarding
    }

    /// A finished setup counts as seen however it was reached, so "What's new" works and the
    /// assistant does not return if a permission is withdrawn later.
    func noteSetupProgress() {
        guard isSetupComplete else { return }
        markOnboardingSeen()
        keepsSetupAssistantOpen = false
    }

    /// Macs set up before the assistant existed (a model is already there) never get it as a
    /// new install; their "What's new" stays as it is.
    private func migrateToSetupAssistant() {
        guard !appSettings.hasMigratedToSetupAssistant else { return }
        appSettings.hasMigratedToSetupAssistant = true
        if isConfigured, !appSettings.hasSeenOnboarding {
            appSettings.hasSeenOnboarding = true
        }
    }

    func markOnboardingSeen() {
        guard !appSettings.hasSeenOnboarding else { return }
        appSettings.hasSeenOnboarding = true
        // New installs get the onboarding, not the release note on top.
        markWhatsNewSeen()
    }

    // MARK: - What's new

    var hasUnseenWhatsNew: Bool {
        appSettings.hasSeenOnboarding && appSettings.lastSeenWhatsNewVersion != WhatsNew.version
    }

    func markWhatsNewSeen() {
        whatsNewTask?.cancel()
        guard appSettings.lastSeenWhatsNewVersion != WhatsNew.version else { return }
        appSettings.lastSeenWhatsNewVersion = WhatsNew.version
        onWhatsNewChange?(false)
    }

    func showWhatsNewAgain() {
        page = .whatsNew
    }

    /// People who only dictate via shortcut never open the popover. Show the note once,
    /// after the first dictation has been pasted, unless the next one already started.
    private func scheduleWhatsNewAfterDictation() {
        guard hasUnseenWhatsNew, activeLaunchSource == .hotkeyBackground, whatsNewTask == nil else { return }
        whatsNewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            self.whatsNewTask = nil
            guard self.hasUnseenWhatsNew, !self.isPopoverShown, !(self.activeWorkflow?.phase.isActive ?? false) else { return }
            NotificationCenter.default.post(name: .showWhatsNew, object: nil)
        }
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
            emojiText: emojiTextSettings
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

    private static func loadContainer() -> SettingsContainer? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(SettingsContainer.self, from: data)
    }

    func refreshAccessibilityPermission() {
        #if DEBUG
        if MacSnapshots.folder != nil { return }
        #endif
        accessibilityPermissionGranted = AccessibilityPermissionService.currentStatus()
        microphoneDenied = MicrophonePermission.isDenied
    }

    func requestAccessibilityPermission() {
        hasRequestedAccessibility = true
        accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
        AccessibilityPermissionService.openSystemSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
    }

    /// Clears a stale grant, then asks again so Blitztext shows up fresh in System Settings.
    func resetAccessibilityPermission() async -> Bool {
        guard await AccessibilityPermissionService.resetPermission() else { return false }
        requestAccessibilityPermission()
        return true
    }

    /// Up to 1.13 a new Mac started with Whisper Small selected. On Apple Silicon Parakeet
    /// Ultra is the better choice; switch while nothing has been downloaded yet.
    private func preferParakeetIfNothingInstalled() {
        // Once only, so a later deliberate choice of Whisper Small is kept.
        guard !appSettings.hasCheckedParakeetDefault else { return }
        appSettings.hasCheckedParakeetDefault = true
        guard ParakeetTranscriber.isSupported,
              LocalTranscriptionService.installedModels().isEmpty,
              appSettings.selectedLocalTranscriptionModelName == LocalTranscriptionService.recommendedFastModelName else {
            return
        }
        appSettings.selectedLocalTranscriptionModelName = ParakeetTranscriber.modelName
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

    /// Macs with Parakeet v3 from an earlier version get Ultra in the background, on a network
    /// without a data limit; until it is ready, dictation keeps using v3. Tried again at the
    /// next launch if it does not finish.
    private func upgradeParakeetIfNeeded() {
        ParakeetTranscriber.files.removeLegacyIfUpgraded()
        guard ParakeetTranscriber.needsUpgrade else { return }
        Task.detached(priority: .utility) {
            guard await UnmeteredNetwork.isAvailable() else { return }
            try? await ParakeetTranscriber.shared.upgrade()
        }
    }

    private func prewarmLocalTranscriptionIfNeeded() {
        guard LocalTranscriptionService.isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        Task.detached(priority: .utility) {
            try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
        }
    }

    private func handleWorkflowOutput(_ dictated: String) {
        var text = dictated
        // The AI modes shape their own paragraphs; word-for-word dictation gets them here.
        if appSettings.automaticParagraphs, let type = activeWorkflow?.type, type == .tapTalk || type == .localTapTalk {
            text = TranscriptParagraphService.format(text, language: transcriptionSettings.language)
        }
        if let type = activeWorkflow?.type {
            history.add(text, workflow: type)
        }
        var output = text
        var transcript = activeWorkflow?.transcript
        if appSettings.fitToSurroundingText, let field = activeField {
            output = InsertionFitter.fit(text, before: field.textBefore, after: field.textAfter)
            transcript = transcript.map { InsertionFitter.fit($0, before: field.textBefore, after: field.textAfter) }
        }
        let target = activePasteTarget
        let field = targetField
        let finishing = activeWorkflow
        let type = finishing?.type
        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
        Task { [weak self] in
            // An AI mode takes a few seconds; meanwhile the user may have clicked into
            // another field. Then the text goes to the clipboard, not into the wrong place.
            if let start = await field?.value, let pid = target?.processIdentifier {
                let bundleID = target?.bundleIdentifier
                let now = await Task.detached(priority: .userInitiated) {
                    FocusedFieldReader.focusSpot(pid: pid, bundleID: bundleID, textFieldOnly: false)
                }.value
                if let now, !now.isSameField(as: start) {
                    guard let self else { return }
                    self.copyToClipboard(output)
                    self.lastInsertion = nil
                    // A dictation started meanwhile keeps its own status and is not reset.
                    if self.activeWorkflow === finishing {
                        self.menuBarStatus = .copied(type)
                        self.scheduleWorkflowCleanup(for: finishing, after: 2.8)
                    }
                    return
                }
            }
            guard let self else { return }
            self.pasteAtCursor(output, target: target)
            if let transcript, let type, transcript != output, target != nil {
                self.lastInsertion = LastInsertion(inserted: output, transcript: transcript, mode: type, target: target, at: Date())
                self.lastInsertionNotice = nil
            } else {
                self.lastInsertion = nil
            }
            self.scheduleWhatsNewAfterDictation()
            self.scheduleWorkflowCleanup(for: finishing, after: 1.05)
        }
    }

    /// "Wortgenau statt KI-Text": replaces the text an AI mode just inserted with what was
    /// said. Selects it in the field through Accessibility and pastes over it; where the app
    /// does not allow that, the word-for-word text goes to the clipboard.
    func insertTranscriptInstead() {
        guard let last = lastInsertion else { return }
        lastInsertion = nil
        guard let pid = last.target?.processIdentifier else {
            copyToClipboard(last.transcript)
            lastInsertionNotice = "Ersetzen ging hier nicht. Der wortgenaue Text liegt in der Zwischenablage."
            return
        }
        Task { [weak self] in
            let selected = await Task.detached(priority: .userInitiated) {
                FocusedFieldReader.selectBeforeCursor(last.inserted, pid: pid)
            }.value
            guard let self else { return }
            if selected {
                self.pasteAtCursor(last.transcript, target: last.target)
                self.lastInsertionNotice = nil
            } else {
                self.copyToClipboard(last.transcript)
                self.lastInsertionNotice = "Ersetzen ging in dieser App nicht. Der wortgenaue Text liegt in der Zwischenablage."
            }
        }
    }

    /// "Wortgenau statt KI-Text" is offered for a few minutes after an AI mode inserted text.
    var offersTranscriptInstead: Bool {
        guard let lastInsertion else { return false }
        return Date().timeIntervalSince(lastInsertion.at) < 10 * 60
    }

    private func configureWorkflowHandlers<T: Workflow>(_ workflow: T) {
        workflow.onOutput = { [weak self] text in
            self?.handleWorkflowOutput(text)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handleWorkflowPhaseChange(phase, workflow: workflow)
        }
    }

    private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
        menuBarStatusResetTask?.cancel()
        // Sound comes back as soon as the recording ends, not after the transcription.
        // A late phase of a replaced workflow must not unmute the next recording.
        if !workflow.isRecording, workflow === activeWorkflow {
            audioMuter.restoreIfNeeded()
        }

        switch phase {
        case .idle:
            if activeWorkflow == nil {
                menuBarStatus = .idle
            }

        case .running(let message):
            menuBarStatus = workflow.isRecording
                ? .recording(workflow.type)
                : .processing(workflow.type)
            // Shortcut users never see the popover; a long model preparation would look
            // like a hang. Show the hint once.
            if message == LocalTranscriptionService.slowPreparationMessage, !isPopoverShown {
                NotificationCenter.default.post(name: .showPopover, object: nil)
            }

        case .done:
            menuBarStatus = .success(workflow.type)

        case .error:
            menuBarStatus = .error(workflow.type)
            microphoneDenied = MicrophonePermission.isDenied
            if activeLaunchSource == .hotkeyBackground {
                activeWorkflow = nil
                activePasteTarget = nil
                page = .main
            }
            scheduleMenuBarStatusReset(after: 1.6)
        }
    }

    /// Resets `workflow` after `delay`, unless another dictation has replaced it by then.
    private func scheduleWorkflowCleanup(for workflow: (any Workflow)?, after delay: TimeInterval) {
        guard let workflow, workflow === activeWorkflow else { return }

        workflowCleanupTask?.cancel()
        let workflowID = ObjectIdentifier(workflow)

        workflowCleanupTask = Task { @MainActor [weak self] in
            // `try?` alone would run the cleanup at once when the task is cancelled
            // (pattern found in cmagnussen/blitztext-app PR #10).
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let activeWorkflow = self.activeWorkflow else { return }
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
            guard !Task.isCancelled, let self else { return }
            if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
                self.menuBarStatus = .idle
            }
        }
    }

    /// Reads the target field in the background while recording starts. Nothing is read
    /// when neither setting needs it.
    private func readActiveField() {
        fieldReadTask?.cancel()
        activeField = nil
        guard appSettings.fitToSurroundingText || appSettings.aiSeesFieldContext,
              let target = activePasteTarget else { return }
        let pid = target.processIdentifier
        let bundleID = target.bundleIdentifier
        fieldReadTask = Task { [weak self] in
            let field = await Task.detached(priority: .userInitiated) {
                FocusedFieldReader.field(pid: pid, bundleID: bundleID)
            }.value
            guard !Task.isCancelled else { return }
            self?.activeField = field
        }
    }

    /// Text around the cursor for the AI modes, when the user allowed it.
    private var fieldContextForAI: @MainActor () -> String? {
        { [weak self] in
            guard let self, self.appSettings.aiSeesFieldContext else { return nil }
            return self.activeField?.aiContext
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
        text: String,
        target: PasteTarget?,
        attemptsRemaining: Int
    ) {
        let ownPid = NSRunningApplication.current.processIdentifier
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let target {
            if frontmostPid == target.processIdentifier {
                performPaste(text)
                return
            }

            target.application.activate(options: [])
        } else if frontmostPid != ownPid {
            performPaste(text)
            return
        }

        guard attemptsRemaining > 0 else {
            // Target never came to the front: keep the text available for a manual paste.
            copyToClipboard(text)
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
                text: text,
                target: target,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func performPaste(_ text: String) {
        if appSettings.restoreClipboardAfterPaste {
            ClipboardPasteService.shared.paste(text) {
                Self.postPasteShortcut()
            }
        } else {
            copyToClipboard(text)
            Self.postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
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
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
    static let chooseAudioFile = Notification.Name("chooseAudioFile")
    static let showWhatsNew = Notification.Name("showWhatsNew")
    static let showPopover = Notification.Name("showPopover")
}

struct LastInsertion {
    let inserted: String
    let transcript: String
    let mode: WorkflowType
    fileprivate let target: PasteTarget?
    let at: Date
}

private struct PasteTarget {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let application: NSRunningApplication
}
