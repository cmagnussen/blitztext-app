import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    static let width: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            switch appState.page {
            case .main:
                mainPage
            case .onboarding:
                onboardingPage
            case .settings:
                settingsPage
            case .workflow:
                workflowPage
            case .history:
                historyPage
            case .audioFile:
                AudioFileView(appState: appState)
            case .whatsNew:
                WhatsNewView(appState: appState)
            }
        }
        .frame(width: Self.width)
        .background {
            BlitztextSurface.windowBackground
        }
        .tint(BlitztextTheme.accent)
        .animation(.easeInOut(duration: 0.2), value: appState.page)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            miniHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider().opacity(0.16)

            VStack(alignment: .leading, spacing: 14) {
                if !appState.isConfigured {
                    setupHero
                }

                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    NoticeRow(
                        icon: "externaldrive.badge.plus",
                        title: "Nach /Applications verschieben",
                        detail: "So startet Blitztext zuverl\u{00E4}ssig mit dem Mac und bekommt Updates.",
                        actionTitle: "Pr\u{00FC}fen",
                        action: { appState.page = .settings }
                    )
                }

                if !appState.accessibilityPermissionGranted {
                    NoticeRow(
                        icon: "hand.raised.fill",
                        title: "Einf\u{00FC}gen braucht Bedienungshilfen",
                        detail: "Nach Updates kann macOS die Freigabe neu verlangen.",
                        actionTitle: "\u{00D6}ffnen",
                        action: { appState.requestAccessibilityPermission() }
                    )
                }

                transcriptionModePanel

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Modi")

                    VStack(spacing: 0) {
                        ForEach(Array(WorkflowType.mainMenuCases.enumerated()), id: \.element) { index, type in
                            if index > 0 {
                                Divider().opacity(0.18).padding(.horizontal, 12)
                            }
                            WorkflowRowView(
                                type: type,
                                enabled: appState.isWorkflowAvailable(type),
                                customName: appState.displayName(for: type),
                                subtitle: appState.workflowSubtitle(for: type),
                                hotkeyLabel: appState.hotkeyLabel(for: type)
                            ) {
                                appState.startWorkflow(type)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .glassPanel()
                }
            }
            .padding(16)

            Divider().opacity(0.16)

            footerBar
        }
    }

    private var miniHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Blitztext")
                    .font(BlackboatType.publicSans(20, .bold, relativeTo: .title3))
                    .foregroundStyle(.primary)
                Text("by Blackboat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.2)
            }

            Spacer(minLength: 0)

            headerStatusCapsule

            Button {
                appState.page = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.subtle)
            .keyboardShortcut(",", modifiers: .command)
            .help("Einstellungen")
        }
    }

    @ViewBuilder
    private var headerStatusCapsule: some View {
        if !appState.isConfigured {
            StatusCapsule(title: "Einrichten", icon: "key.fill", tint: BlitztextTheme.accent)
        } else if let provider = appState.providerInUse {
            StatusCapsule(title: "KI: \(provider)", icon: "arrow.up.forward.circle.fill", tint: BlitztextTheme.accent)
                .help("Sprache bleibt auf diesem Mac. Die KI-Modi laufen über \(provider).")
        } else {
            StatusCapsule(
                title: "Alles lokal",
                icon: "lock.shield.fill",
                tint: appState.selectedLocalModelIsInstalled ? BlitztextTheme.ready : BlitztextTheme.accent
            )
            .help("Sprache und KI bleiben auf diesem Mac.")
        }
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Einrichtung n\u{00F6}tig")
                .font(BlackboatType.publicSans(18, .semibold, relativeTo: .headline))
            Text("Installiere in den Einstellungen ein lokales Sprachmodell. Blitztext transkribiert direkt auf diesem Mac.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                appState.page = .settings
            } label: {
                Label("Einstellungen \u{00F6}ffnen", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glassAction)
            .padding(.top, 2)
        }
    }

    private var transcriptionModePanel: some View {
        let modelOptions = LocalTranscriptionService.modelOptions(selected: appState.selectedLocalModelName)
        let selectedModelInstalled = appState.selectedLocalModelIsInstalled

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lokale Transkription")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(modePanelSubtitle(selectedModelInstalled: selectedModelInstalled))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            Group {
                Divider().opacity(0.18)

                HStack(spacing: 8) {
                    Text("Modell")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(modelOptions) { model in
                            Text(model.pickerLabel)
                                .tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let rating = LocalModelRating.rating(for: appState.selectedLocalModelName) {
                    ModelRatingPanel(rating: rating, modelName: appState.selectedLocalModelName)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen ...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else if !selectedModelInstalled {
                    Button {
                        appState.installSelectedLocalModel()
                    } label: {
                        Label(appState.localModelDownloadButtonTitle, systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.glassAction)
                }

                if let errorText = appState.localModelDownloadErrorText {
                    NoticeRow(icon: "xmark.circle.fill", title: errorText, tint: BlitztextTheme.danger)
                }

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(appState.canRewrite ? BlitztextTheme.ready : BlitztextTheme.accent)
                    Text(aiStatusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .glassPanel()
    }

    /// Where Blitztext+, $%&! and :) run right now.
    private var aiStatusText: String {
        let engine = appState.appSettings.rewriteEngine
        if TextRewriter.runsLocally(engine: engine) {
            return "KI-Modi laufen auf diesem Mac (Apple Intelligence)."
        }
        if appState.isAIProviderReady, let provider = appState.aiProvider?.provider {
            return "KI-Modi laufen über \(provider.displayName)."
        }
        return "KI-Modi brauchen Apple Intelligence oder einen API-Key."
    }

    private func modePanelSubtitle(selectedModelInstalled: Bool) -> String {
        if appState.isDownloadingLocalModel {
            return appState.localModelDownloadStatusText ?? "Lokales Modell wird geladen."
        }
        if selectedModelInstalled {
            return "Audio bleibt auf diesem Mac, mit \(appState.selectedLocalModelDisplayName)."
        }
        return "\(appState.selectedLocalModelDisplayName) ist noch nicht installiert."
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text(versionText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.58))
                .lineLimit(1)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .chooseAudioFile, object: nil)
            } label: {
                Label("Audiodatei", systemImage: "waveform.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.glassAction)
            .help("Sprachmemo oder WhatsApp-Sprachnachricht transkribieren. Du kannst Dateien auch auf das Blitztext-Symbol im Finder ziehen.")

            Button {
                appState.page = .history
            } label: {
                Label("Verlauf", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.glassAction)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Beenden")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .buttonStyle(.subtle)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.white.opacity(0.035))
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        let suffix = Bundle.main.bundleURL.path.hasPrefix("/Applications/") ? "" : ", Dev"
        return "v\(version) (\(build))\(suffix)"
    }

    // MARK: - Onboarding

    private var onboardingPage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Willkommen")
                        .font(BlackboatType.publicSans(20, .bold, relativeTo: .title3))
                    Text("bei Blitztext")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sp\u{00E4}ter") {
                    appState.page = .main
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .buttonStyle(.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.16)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Einmal einrichten, dann direkt loslegen.")
                        .font(BlackboatType.publicSans(18, .semibold, relativeTo: .headline))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Ein lokales Sprachmodell reicht. Danach sprechen und einf\u{00FC}gen, alles auf diesem Mac.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    NoticeRow(
                        icon: "arrow.down.app",
                        title: "Lege Blitztext zuerst nach /Applications",
                        detail: "So startet Blitztext zuverl\u{00E4}ssig mit dem Mac und bekommt Updates."
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    onboardingStep(number: "1", title: "Sprachmodell laden", detail: "In den Einstellungen ein lokales Modell installieren, zum Beispiel Parakeet Ultra.")
                    Divider().opacity(0.18)
                    onboardingStep(number: "2", title: "Berechtigungen erlauben", detail: "Mikrofon und Bedienungshilfen f\u{00FC}r das Einf\u{00FC}gen freigeben.")
                    Divider().opacity(0.18)
                    onboardingStep(number: "3", title: "Modus w\u{00E4}hlen", detail: "Per Tastenk\u{00FC}rzel oder direkt aus der Men\u{00FC}leiste starten.")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glassPanel()

                Button {
                    appState.page = .settings
                } label: {
                    Label("Jetzt einrichten", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassAction)
            }
            .padding(16)
        }
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .glassCapsule(tint: .primary, fillOpacity: 0.04)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Einstellungen", onBack: { appState.page = .main }) {
                settingsQuickAction
            }

            SettingsContentView(appState: appState)
        }
        .frame(height: 640)
    }

    @ViewBuilder
    private var settingsQuickAction: some View {
        if !appState.accessibilityPermissionGranted {
            Button {
                appState.requestAccessibilityPermission()
            } label: {
                Label("Rechte", systemImage: "hand.raised")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.subtle)
        } else if BlitztextInstallLocationService.currentInstallLocation.isCanonicalInstall &&
            appState.appUpdateService.updatesInApp {
            Button {
                appState.appUpdateService.checkForUpdates()
            } label: {
                Label("Updates", systemImage: "arrow.trianglehead.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.subtle)
            .disabled(!appState.appUpdateService.canCheckForUpdates)
        }
    }

    // MARK: - History Page

    private var historyPage: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Verlauf", onBack: { appState.page = .main })

            Divider().opacity(0.16)

            HistoryListView(appState: appState)
        }
        .frame(height: 520)
    }

    // MARK: - Workflow Page

    private var workflowPage: some View {
        VStack(spacing: 0) {
            if let workflow = appState.activeWorkflow {
                PageHeader(title: appState.displayName(for: workflow.type), onBack: { appState.resetCurrentWorkflow() }) {
                    Image(systemName: workflow.type.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }

                Divider().opacity(0.16)

                switch workflow.type {
                case .tapTalk, .localTapTalk:
                    if let w = workflow as? TranscriptionWorkflow {
                        TapTalkActiveView(workflow: w)
                    }
                case .textImprover:
                    if let w = workflow as? TextImprovementWorkflow {
                        TextImproverActiveView(workflow: w)
                    }
                case .dampfAblassen:
                    if let w = workflow as? DampfAblassenWorkflow {
                        DampfAblassenActiveView(workflow: w)
                    }
                case .emojiText:
                    if let w = workflow as? EmojiTextWorkflow {
                        EmojiTextActiveView(workflow: w)
                    }
                }
            }
        }
    }
}

// MARK: - TapTalk Active View

struct TapTalkActiveView: View {
    @Bindable var workflow: TranscriptionWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else if case .running(let message) = workflow.phase,
                          message == LocalTranscriptionService.slowPreparationMessage {
                    processingView(message: message)
                } else {
                    processingView(message: "Wird transkribiert \u{2026}")
                }

            case .done(let text):
                autoPasteView(text: text)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                .frame(height: 44)
                .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            Text("Aufnahme l\u{00E4}uft. Zum Stoppen klicken.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Text Improver Active View

struct TextImproverActiveView: View {
    @Bindable var workflow: TextImprovementWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 24)
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        if case .running(let msg) = workflow.phase {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 24)
                    }
                }

            case .done(let text):
                autoPasteView(text: text)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                .frame(height: 44)
                .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            Text("Aufnahme l\u{00E4}uft. Zum Stoppen klicken.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Rage Mode Active View

struct DampfAblassenActiveView: View {
    @Bindable var workflow: DampfAblassenWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 24)
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        if case .running(let msg) = workflow.phase {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 24)
                    }
                }

            case .done(let text):
                autoPasteView(text: text)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                .frame(height: 44)
                .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            Text("Aufnahme l\u{00E4}uft. Zum Stoppen klicken.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Emoji Text Active View

struct EmojiTextActiveView: View {
    @Bindable var workflow: EmojiTextWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 24)
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        if case .running(let msg) = workflow.phase {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 24)
                    }
                }

            case .done(let text):
                autoPasteView(text: text)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                .frame(height: 44)
                .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            Text("Aufnahme l\u{00E4}uft. Zum Stoppen klicken.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Shared Result / Error Views

private func processingView(message: String) -> some View {
    VStack(spacing: 12) {
        Spacer().frame(height: 24)
        ProgressView()
            .scaleEffect(0.7)
            .controlSize(.small)
        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
        Spacer().frame(height: 24)
    }
}

private func autoPasteView(text: String) -> some View {
    VStack(spacing: 12) {
        Spacer().frame(height: 20)

        ZStack {
            Circle()
                .fill(BlitztextTheme.accent.opacity(0.1))
                .frame(width: 44, height: 44)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(BlitztextTheme.accent)
        }

        Text("Eingef\u{00FC}gt")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)

        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

        Spacer().frame(height: 12)
    }
}

private func errorView(message: String, onRetry: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
        Spacer().frame(height: 16)

        ZStack {
            Circle()
                .fill(BlitztextTheme.danger.opacity(0.08))
                .frame(width: 40, height: 40)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(BlitztextTheme.danger)
        }

        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

        Button(action: onRetry) {
            Text("Nochmal versuchen")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(SubtleButtonStyle())

        Spacer().frame(height: 4)
    }
}
