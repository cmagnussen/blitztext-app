import SwiftUI

/// Optional provider for Blitztext+, $%&! and :), connected with the user's own API key.
struct MacAIProviderSection: View {
    @Bindable var appState: AppState

    @State private var keyInput = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case testing
        case ok
        case failed(String)
    }

    var body: some View {
        SettingsSection(title: "Modell-Anbieter") {
            Text("Optional. Mit Apple Intelligence laufen die KI-Modi auf diesem Mac. Ein eigener API-Key hilft, wenn Apple Intelligence fehlt oder mehr Qualität gefragt ist.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Anbieter", selection: providerBinding) {
                Text("Keiner, nur auf diesem Mac").tag(AIProvider?.none)
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(AIProvider?.some(provider))
                }
            }
            .controlSize(.small)

            if let config = appState.aiProvider {
                providerFields(config)
            }
        }
    }

    @ViewBuilder
    private func providerFields(_ config: AIProviderConfig) -> some View {
        let provider = config.provider

        HStack(spacing: 8) {
            SecureField(maskedKey(provider) ?? (provider.requiresAPIKey ? "API-Key einfügen" : "API-Key (optional)"), text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.ui(11.5))
            Button("Sichern") { saveKey(provider) }
                .buttonStyle(SubtleButtonStyle())
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        HStack(spacing: 10) {
            if maskedKey(provider) != nil {
                Label("API-Key gespeichert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(BlitztextTheme.ready)
                Button("Entfernen") {
                    APIKeyStore.delete(for: provider)
                    appState.aiKeyRevision += 1
                    testState = .idle
                }
                .buttonStyle(.plain)
                .foregroundStyle(BlitztextTheme.danger)
            }
            Spacer()
            if let url = provider.keyHelpURL {
                Link("Key erstellen", destination: url)
            }
        }
        .font(.ui(10.5, .medium))

        HStack(spacing: 8) {
            Text("Modell")
                .font(.ui(12))
                .foregroundStyle(.secondary)
            TextField(provider.defaultModel, text: modelBinding)
                .textFieldStyle(.roundedBorder)
                .font(.ui(11.5))
        }

        if provider == .custom {
            HStack(spacing: 8) {
                Text("Adresse")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                TextField(provider.defaultBaseURL, text: baseURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.ui(11.5))
            }
            Text("OpenAI-kompatible Adresse, zum Beispiel Ollama oder LM Studio auf diesem Mac.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
            if AIClient.isInsecureAddress(appState.aiProvider?.baseURL ?? "") {
                Label(
                    "http:// zu einem anderen Rechner: Texte gehen unverschlüsselt durchs Netz. Mit API-Key lehnt Blitztext die Anfrage ab; ohne Key geht sie durch.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.ui(12))
                .foregroundStyle(BlitztextTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack(spacing: 8) {
            Button("Verbindung testen") { test(config) }
                .buttonStyle(SubtleButtonStyle())
                .disabled(testState == .testing)
            switch testState {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .ok: Label("Funktioniert", systemImage: "checkmark.circle.fill").foregroundStyle(BlitztextTheme.ready)
            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(BlitztextTheme.danger)
            }
        }
        .font(.ui(10.5, .medium))

        if case .failed(let message) = testState {
            Text(message)
                .font(.ui(12))
                .foregroundStyle(BlitztextTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }

        Label {
            Text("Ab jetzt gehen die Texte der KI-Modi an \(provider.displayName), wenn Apple Intelligence nicht übernimmt. Die Sprache selbst bleibt auf diesem Mac. Es gelten die Bedingungen und Kosten des Anbieters. Der Key liegt im Schlüsselbund dieses Macs.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.up.forward.circle.fill")
                .foregroundStyle(BlitztextTheme.accent)
        }
        .font(.ui(12))
        .foregroundStyle(.secondary)
    }

    // MARK: - Bindings

    private var providerBinding: Binding<AIProvider?> {
        Binding(
            get: { appState.aiProvider?.provider },
            set: { provider in
                keyInput = ""
                testState = .idle
                appState.aiProvider = provider.map { AIProviderConfig(provider: $0) }
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { appState.aiProvider?.model ?? "" },
            set: { appState.aiProvider?.model = $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { appState.aiProvider?.baseURL ?? "" },
            set: { appState.aiProvider?.baseURL = $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    // MARK: - Actions

    private func maskedKey(_ provider: AIProvider) -> String? {
        _ = appState.aiKeyRevision
        return APIKeyStore.maskedKey(for: provider)
    }

    private func saveKey(_ provider: AIProvider) {
        // The Keychain can refuse the write (locked keychain, no entitlement). Say so instead
        // of clearing the field and looking as if the key were stored.
        guard APIKeyStore.save(keyInput, for: provider) else {
            testState = .failed("Der Key konnte nicht im Schlüsselbund gespeichert werden.")
            return
        }
        keyInput = ""
        appState.aiKeyRevision += 1
        testState = .idle
    }

    private func test(_ config: AIProviderConfig) {
        testState = .testing
        Task {
            do {
                try await AIClient.testConnection(config: config)
                testState = .ok
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
