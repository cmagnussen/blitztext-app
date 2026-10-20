import AVFoundation
import SwiftUI

/// First start: walks through what Blitztext needs, each step with its live state and its
/// own button: microphone, Accessibility for pasting, the speech model. Granting a permission
/// opens System Settings, which closes the popover; the assistant comes back on the next
/// click until everything is done or the user picks "Später".
struct SetupAssistantView: View {
    @Bindable var appState: AppState

    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    /// No input device or a very quiet one, refreshed with the permissions.
    @State private var microphoneIssue = MicrophoneCheck.issue
    @State private var isResettingAccessibility = false
    @State private var resetFailed = false

    #if DEBUG
    /// Snapshots draw the assistant before anything is set up.
    static var debugShowsFreshMac = false
    #endif

    private var showsFreshMac: Bool {
        #if DEBUG
        return Self.debugShowsFreshMac
        #else
        return false
        #endif
    }

    private var microphoneReady: Bool { !showsFreshMac && microphone == .authorized }
    private var accessibilityReady: Bool { !showsFreshMac && appState.accessibilityPermissionGranted }
    private var modelReady: Bool { !showsFreshMac && appState.selectedLocalModelIsInstalled }
    private var openSteps: Int { [microphoneReady, accessibilityReady, modelReady].filter { !$0 }.count }

    /// The step the assistant points at: the first one still open.
    private var currentStep: Int {
        if !microphoneReady { return 1 }
        if !accessibilityReady { return 2 }
        if !modelReady { return 3 }
        return 4
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Willkommen")
                        .font(BlackboatType.publicSans(20, .bold, relativeTo: .title3))
                    Text("bei Blitztext")
                        .font(.ui(12, .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sp\u{00E4}ter") { appState.finishSetupAssistant() }
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.16)

            VStack(alignment: .leading, spacing: 12) {
                Text(openSteps == 0 ? "Alles bereit." : "In drei Schritten startklar. Alles l\u{00E4}uft auf diesem Mac.")
                    .font(BlackboatType.publicSans(17, .semibold, relativeTo: .headline))
                    .fixedSize(horizontal: false, vertical: true)

                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    NoticeRow(
                        icon: "arrow.down.app",
                        title: "Lege Blitztext zuerst in den Ordner Programme",
                        detail: "So startet Blitztext zuverl\u{00E4}ssig mit dem Mac, und die Freigaben bleiben erhalten."
                    )
                }

                step(1, title: "Mikrofon erlauben", done: microphoneReady, detail: microphoneDetail) {
                    microphoneAction
                }
                step(2, title: "Einf\u{00FC}gen erlauben", done: accessibilityReady, detail: accessibilityDetail) {
                    accessibilityAction
                }
                step(3, title: "Sprachmodell laden", done: modelReady, detail: modelDetail) {
                    modelAction
                }

                finish
            }
            .padding(16)
        }
        // Permissions change in System Settings, outside the app: keep the steps current.
        .task {
            while !Task.isCancelled {
                microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                microphoneIssue = MicrophoneCheck.issue
                appState.refreshAccessibilityPermission()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Steps

    private func step<Action: View>(
        _ number: Int,
        title: String,
        done: Bool,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let isCurrent = number == currentStep
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? BlitztextTheme.ready.opacity(0.16) : (isCurrent ? BlitztextTheme.accent : BlitztextTheme.tonal))
                if done {
                    Image(systemName: "checkmark")
                        .font(.ui(11, .bold))
                        .foregroundStyle(BlitztextTheme.ready)
                } else {
                    Text("\(number)")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(isCurrent ? BlitztextTheme.onAccent : .secondary)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                Text(detail)
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !done {
                    action()
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BlitztextTheme.accent.opacity(isCurrent ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    private var microphoneDetail: String {
        if microphoneReady {
            switch microphoneIssue {
            case .noInput:
                return "Erlaubt. Gerade ist aber kein Mikrofon da, bei zugeklapptem MacBook ein Headset anschlie\u{00DF}en."
            case .quiet(let percent):
                return "Erlaubt. Das Mikrofon ist aber sehr leise eingestellt (\(percent) %), in den Systemeinstellungen unter Ton, Eingang lauter stellen."
            case nil:
                return "Blitztext darf das Mikrofon nutzen."
            }
        }
        switch microphone {
        case .denied, .restricted:
            return "In den Systemeinstellungen ist das Mikrofon f\u{00FC}r Blitztext aus. Dort unter Datenschutz & Sicherheit > Mikrofon einschalten."
        default:
            return "Damit Blitztext h\u{00F6}rt, was du sagst. Die Aufnahme bleibt auf diesem Mac."
        }
    }

    @ViewBuilder
    private var microphoneAction: some View {
        switch microphone {
        case .denied, .restricted:
            Button("Systemeinstellungen \u{00F6}ffnen") { MicrophonePermission.openSystemSettings() }
                .buttonStyle(actionStyle(for: 1))
        default:
            Button("Mikrofon erlauben") {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    Task { @MainActor in microphone = AVCaptureDevice.authorizationStatus(for: .audio) }
                }
            }
            .buttonStyle(actionStyle(for: 1))
        }
    }

    private var accessibilityDetail: String {
        if accessibilityReady { return "Blitztext darf den Text dort einf\u{00FC}gen, wo dein Cursor steht." }
        return appState.hasRequestedAccessibility
            ? "In den Systemeinstellungen bei Bedienungshilfen Blitztext einschalten. Danach geht es hier von selbst weiter."
            : "Damit der Text dort landet, wo dein Cursor steht. macOS fragt dazu nach den Bedienungshilfen."
    }

    private var accessibilityAction: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Bedienungshilfen \u{00F6}ffnen") {
                    appState.requestAccessibilityPermission()
                }
                .buttonStyle(actionStyle(for: 2))

                if appState.hasRequestedAccessibility {
                    // macOS sometimes shows Blitztext as on although the grant no longer counts.
                    Button("Steht schon auf an?") {
                        isResettingAccessibility = true
                        resetFailed = false
                        Task {
                            resetFailed = !(await appState.resetAccessibilityPermission())
                            isResettingAccessibility = false
                        }
                    }
                    .buttonStyle(.subtle)
                    .disabled(isResettingAccessibility)
                    .help("Setzt die Freigabe zur\u{00FC}ck, danach in den Systemeinstellungen neu einschalten.")
                }
            }
            if resetFailed {
                Text("Zur\u{00FC}cksetzen hat nicht geklappt. In den Bedienungshilfen Blitztext mit \u{201E}\u{2212}\u{201C} entfernen und neu hinzuf\u{00FC}gen.")
                    .font(.ui(11))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modelName: String { LocalTranscriptionModel.displayName(for: appState.selectedLocalModelName) }

    private var modelDetail: String {
        if modelReady { return "\(modelName) ist installiert." }
        let size = LocalModelRating.rating(for: appState.selectedLocalModelName)?.sizeLabel
        let sizeText = size.map { ", \($0)" } ?? ""
        return "\(modelName)\(sizeText), einmalig. Danach erkennt Blitztext Sprache ohne Internet."
    }

    @ViewBuilder
    private var modelAction: some View {
        if let progress = appState.localModelDownloadProgress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
                Text(appState.localModelDownloadStatusText ?? "L\u{00E4}dt ...")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button("\(modelName) laden") { appState.installSelectedLocalModel() }
                    .buttonStyle(actionStyle(for: 3))
                if let error = appState.localModelDownloadErrorText {
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(BlitztextTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Finish

    private var finish: some View {
        VStack(alignment: .leading, spacing: 8) {
            if openSteps == 0 {
                Text("\(shortcutHint): Der Text landet dort, wo dein Cursor steht. Ohne Apple-Tastatur legst du in den Einstellungen ein eigenes K\u{00FC}rzel fest.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                appState.finishSetupAssistant()
            } label: {
                Text(openSteps == 0 ? "Los geht's" : (openSteps == 1 ? "Noch 1 Schritt" : "Noch \(openSteps) Schritte"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.filledAction)
            .disabled(openSteps > 0)
        }
    }

    /// "fn + Shift halten und sprechen" or "... drücken ...", as on the main page.
    private var shortcutHint: String {
        let hotkey = appState.hotkeyLabel(for: .tapTalk)
        return appState.appSettings.hotkeyMode == .hold
            ? "\(hotkey) halten und sprechen"
            : "\(hotkey) dr\u{00FC}cken, sprechen, nochmal dr\u{00FC}cken"
    }

    /// The current step's button is the filled one.
    private func actionStyle(for step: Int) -> AnyButtonStyle {
        step == currentStep ? AnyButtonStyle(FilledActionButtonStyle()) : AnyButtonStyle(GlassActionButtonStyle())
    }

}

/// Lets one button switch between the filled and the tonal style.
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
