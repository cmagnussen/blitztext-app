import Foundation
import Security

/// A language model provider the user connects with their own API key.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case mistral
    case openRouter
    /// Any OpenAI-compatible endpoint: Azure, a company proxy, Ollama or LM Studio on the Mac.
    case custom

    var id: String { rawValue }

    enum APIStyle {
        case openAICompatible
        case anthropic
    }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google Gemini"
        case .mistral: return "Mistral"
        case .openRouter: return "OpenRouter"
        case .custom: return "Eigene Adresse"
        }
    }

    var apiStyle: APIStyle {
        self == .anthropic ? .anthropic : .openAICompatible
    }

    /// Base URL; for OpenAI-compatible providers `/chat/completions` is appended.
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .mistral: return "https://api.mistral.ai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .custom: return "http://localhost:11434/v1"
        }
    }

    /// Suggested model, editable in the settings.
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-opus-5"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-small-latest"
        case .openRouter: return "openai/gpt-4o-mini"
        case .custom: return "llama3.2"
        }
    }

    /// Local servers like Ollama run without a key.
    var requiresAPIKey: Bool { self != .custom }

    var keyHelpURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .custom: return nil
        }
    }
}

/// Which provider is connected, with which model and address. The key itself lives in the Keychain.
struct AIProviderConfig: Codable, Equatable {
    var provider: AIProvider
    var model: String
    var baseURL: String

    init(provider: AIProvider, model: String? = nil, baseURL: String? = nil) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.baseURL = baseURL ?? provider.defaultBaseURL
    }
}

enum AIProviderStore {
    private static let configKey = "AIProviderStore.config"

    /// The connected provider, or nil when only the on-device model is used.
    static var config: AIProviderConfig? {
        get {
            guard let data = UserDefaults.standard.data(forKey: configKey) else { return nil }
            return try? JSONDecoder().decode(AIProviderConfig.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: configKey)
            } else {
                UserDefaults.standard.removeObject(forKey: configKey)
            }
        }
    }

    /// True when a provider is set up and has its key (or needs none).
    static var isConfigured: Bool {
        guard let config else { return false }
        return !config.provider.requiresAPIKey || APIKeyStore.key(for: config.provider) != nil
    }
}

/// API keys in the system Keychain, one per provider. Available after the first unlock,
/// so dictations finishing in the background can still use them.
enum APIKeyStore {
    private static let service = "app.blitztext.ai-provider"

    static func key(for provider: AIProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(for: provider)
        guard !trimmed.isEmpty else { return true }
        var item = baseQuery(provider)
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(for provider: AIProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    /// "sk-…abcd" for display, never the full key.
    static func maskedKey(for provider: AIProvider) -> String? {
        guard let key = key(for: provider) else { return nil }
        guard key.count > 8 else { return "••••••••" }
        return String(key.prefix(3)) + "…" + String(key.suffix(4))
    }

    private static func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
