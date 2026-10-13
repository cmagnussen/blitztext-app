import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One rule: dictating with the Blitztext shortcut in this app uses `mode` instead.
struct AppModeRule: Codable, Hashable, Identifiable {
    var bundleID: String
    var appName: String
    var mode: WorkflowType

    var id: String { bundleID }
}

/// The same for a website in a browser, e.g. Gmail. `host` matches subdomains too.
struct WebsiteModeRule: Codable, Hashable, Identifiable {
    var host: String
    var mode: WorkflowType

    var id: String { host }
}

/// Settings for "Modus je App": e.g. Mail or Gmail always become Blitztext+.
struct AppModeRulesSection: View {
    @Bindable var appState: AppState

    private var rules: [AppModeRule] { appState.appSettings.appModeRules }
    private var websiteRules: [WebsiteModeRule] { appState.appSettings.websiteModeRules }

    private static let websitePresets: [(name: String, host: String)] = [
        ("Gmail", "mail.google.com"),
        ("Outlook im Web", "outlook.office.com"),
        ("Google Docs", "docs.google.com"),
        ("Notion", "notion.so"),
        ("Slack", "app.slack.com"),
        ("Microsoft Teams", "teams.microsoft.com"),
        ("WhatsApp Web", "web.whatsapp.com"),
        ("LinkedIn", "linkedin.com"),
    ]

    private static let selectableModes: [WorkflowType] = [.tapTalk, .textImprover, .dampfAblassen, .emojiText]

    var body: some View {
        SettingsSection(title: "Modus je App") {
            Text("Das Blitztext-K\u{00FC}rzel (\(appState.hotkeyLabel(for: .tapTalk))) kann je App oder Website automatisch einen anderen Modus nutzen, zum Beispiel Blitztext+ in Gmail, w\u{00E4}hrend es in Slack wortgenau bleibt. Die \u{00FC}brigen K\u{00FC}rzel bleiben wie sie sind.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(rules) { rule in
                HStack(spacing: 8) {
                    appIcon(for: rule.bundleID)
                    Text(rule.appName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Picker("", selection: binding(for: rule)) {
                        ForEach(Self.selectableModes) { mode in
                            Text(appState.displayName(for: mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            appState.appSettings.appModeRules.removeAll { $0.id == rule.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .help("Regel entfernen")
                }
            }

            ForEach(websiteRules) { rule in
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                    Text(rule.host)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Picker("", selection: binding(for: rule)) {
                        ForEach(Self.selectableModes) { mode in
                            Text(appState.displayName(for: mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            appState.appSettings.websiteModeRules.removeAll { $0.id == rule.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .help("Regel entfernen")
                }
            }

            if !websiteRules.isEmpty {
                Text("Websites erkennt Blitztext in Safari, Chrome, Edge, Brave, Arc und Firefox. Eine Website-Regel gilt vor der Regel f\u{00FC}r den Browser.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if (rules.contains(where: { $0.mode != .tapTalk }) || websiteRules.contains(where: { $0.mode != .tapTalk }))
                && !appState.canRewrite {
                Text("KI-Modi brauchen Apple Intelligence oder einen API-Key. Bis dahin diktiert Blitztext dort wortgenau.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Menu {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                        addRule(bundleID: app.bundleIdentifier, name: app.localizedName)
                    }
                }
                if !runningApps.isEmpty {
                    Divider()
                }
                Button("Andere App \u{2026}") { chooseApp() }
                Divider()
                Menu("Website") {
                    ForEach(availablePresets, id: \.host) { preset in
                        Button("\(preset.name) (\(preset.host))") { addWebsite(preset.host) }
                    }
                    if !availablePresets.isEmpty {
                        Divider()
                    }
                    Button("Andere Website \u{2026}") { enterWebsite() }
                }
            } label: {
                Label("App oder Website hinzuf\u{00FC}gen", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    /// Open apps with a window, without Blitztext and apps that already have a rule.
    private var runningApps: [NSRunningApplication] {
        let existing = Set(rules.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return id != Bundle.main.bundleIdentifier && !existing.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private var availablePresets: [(name: String, host: String)] {
        let existing = Set(websiteRules.map(\.host))
        return Self.websitePresets.filter { !existing.contains($0.host) }
    }

    private func binding(for rule: WebsiteModeRule) -> Binding<WorkflowType> {
        Binding(
            get: { rule.mode },
            set: { newMode in
                guard let index = appState.appSettings.websiteModeRules.firstIndex(where: { $0.id == rule.id }) else { return }
                appState.appSettings.websiteModeRules[index].mode = newMode
            }
        )
    }

    private func addWebsite(_ host: String) {
        guard !websiteRules.contains(where: { $0.host == host }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            appState.appSettings.websiteModeRules.append(WebsiteModeRule(host: host, mode: .textImprover))
        }
    }

    private func enterWebsite() {
        let alert = NSAlert()
        alert.messageText = "Website hinzuf\u{00FC}gen"
        alert.informativeText = "Adresse der Website, zum Beispiel mail.google.com. Die Regel gilt auch f\u{00FC}r Unteradressen."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "mail.google.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "Hinzuf\u{00FC}gen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let host = WebsiteHost.normalized(field.stringValue) else { return }
        addWebsite(host)
    }

    private func binding(for rule: AppModeRule) -> Binding<WorkflowType> {
        Binding(
            get: { rule.mode },
            set: { newMode in
                guard let index = appState.appSettings.appModeRules.firstIndex(where: { $0.id == rule.id }) else { return }
                appState.appSettings.appModeRules[index].mode = newMode
            }
        )
    }

    private func addRule(bundleID: String?, name: String?) {
        guard let bundleID, !rules.contains(where: { $0.bundleID == bundleID }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            appState.appSettings.appModeRules.append(
                AppModeRule(bundleID: bundleID, appName: name ?? bundleID, mode: .textImprover)
            )
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "App w\u{00E4}hlen"
        panel.prompt = "Hinzuf\u{00FC}gen"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url) else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        addRule(bundleID: bundle.bundleIdentifier, name: name)
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app")
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
        }
    }
}
