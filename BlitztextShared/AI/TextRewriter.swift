import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rewrites a transcript with an instruction. Local first: Apple Foundation Models
/// on the device when available (iOS 26 / macOS 26 with Apple Intelligence), otherwise
/// the provider the user connected with their own API key.
enum TextRewriter {
    enum Engine: String, Codable, CaseIterable, Identifiable {
        /// On the device when possible, otherwise the connected provider.
        case automatic
        /// Always the connected provider (larger model, text leaves the device).
        case provider

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .automatic: return "Gerät zuerst"
            case .provider: return "Immer Modell-Anbieter"
            }
        }

        // Settings saved by builds with the Blitztext server decode as "server".
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = raw == Engine.provider.rawValue || raw == "server" ? .provider : .automatic
        }
    }

    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    enum RewriteError: LocalizedError {
        case noModel

        var errorDescription: String? {
            "Für diesen Modus braucht Blitztext Apple Intelligence oder einen API-Key in den Einstellungen."
        }
    }

    static var localAvailability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("Dieses Gerät unterstützt Apple Intelligence nicht.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence ist in den Systemeinstellungen ausgeschaltet.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple Intelligence lädt das Modell noch.")
            case .unavailable:
                return .unavailable("Apple Intelligence ist gerade nicht verfügbar.")
            }
        }
        #endif
        return .unavailable("Braucht iOS 26 oder macOS 26 mit Apple Intelligence.")
    }

    static var isLocalAvailable: Bool { localAvailability == .available }

    /// Whether any model can run the AI step with this engine setting.
    static func canRewrite(engine: Engine) -> Bool {
        (engine == .automatic && isLocalAvailable) || AIProviderStore.isConfigured
    }

    /// True when the next rewrite runs on the device.
    static func runsLocally(engine: Engine) -> Bool {
        engine == .automatic && isLocalAvailable
    }

    static func rewrite(_ text: String, instruction: String, engine: Engine) async throws -> String {
        if runsLocally(engine: engine) {
            return try await rewriteLocally(text, instruction: instruction)
        }
        guard let config = AIProviderStore.config, AIProviderStore.isConfigured else {
            throw RewriteError.noModel
        }
        return try await AIClient.complete(
            instruction: instruction + "\n\n" + ModePrompts.spokenTranscriptRules,
            text: text,
            config: config
        )
    }

    private static func rewriteLocally(_ text: String, instruction: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instruction + "\n\n" + ModePrompts.spokenTranscriptRules)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw RewriteError.noModel
    }
}
