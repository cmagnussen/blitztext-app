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

    /// What the AI step does with the transcript.
    enum Purpose {
        /// Writes new text from it: own modes like „Antworten“, meeting summaries.
        case generate
        /// Edits what was said and never answers it: the built-in modes. The transcript goes
        /// to the model framed as material, and the result is checked (`RewriteGuard`).
        case editTranscript
    }

    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    enum RewriteError: LocalizedError {
        case noModel
        /// Apple Intelligence on the device gave up, in words for the user.
        case onDevice(String)
        /// A provider is set up, but the user has not allowed sending text to it.
        case noConsent(String)
        /// A built-in mode got back something that is no edit of the transcript.
        case notEdited(String)

        var errorDescription: String? {
            switch self {
            case .noModel:
                return "Für diesen Modus braucht Blitztext Apple Intelligence oder einen API-Key in den Einstellungen."
            case .onDevice(let message), .noConsent(let message), .notEdited(let message):
                return message
            }
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

    /// - Parameters:
    ///   - dictationRules: Adds the rules for reading dictated speech (self-corrections, du/Sie).
    ///     Their examples name weekdays and numbers, which a small model copies into summaries.
    ///   - deterministic: On the device, always take the most likely wording, so the same text
    ///     gives the same result. Providers keep their default sampling.
    ///   - purpose: `.editTranscript` for the built-in modes; a result that is no edit throws
    ///     `RewriteError.notEdited`, so callers keep the word-for-word text (`AIStepFailed`).
    static func rewrite(
        _ text: String,
        instruction: String,
        engine: Engine,
        dictationRules: Bool = true,
        deterministic: Bool = false,
        purpose: Purpose = .generate
    ) async throws -> String {
        var instruction = dictationRules ? instruction + "\n\n" + ModePrompts.spokenTranscriptRules : instruction
        var prompt = text
        if purpose == .editTranscript {
            instruction += "\n\n" + RewriteGuard.framingRule
            prompt = RewriteGuard.framed(text)
        }

        let result: String
        if runsLocally(engine: engine) {
            // No silent switch to a provider: the app promises the text stays on the device.
            result = try await rewriteLocally(prompt, instruction: instruction, deterministic: deterministic)
        } else {
            guard let config = AIProviderStore.config, AIProviderStore.isConfigured else {
                if let config = AIProviderStore.config, AIProviderStore.awaitsConsent {
                    throw RewriteError.noConsent(AIProviderConsent.missingMessage(for: config))
                }
                throw RewriteError.noModel
            }
            result = try await AIClient.complete(instruction: instruction, text: prompt, config: config)
        }

        guard purpose == .editTranscript else { return result }
        let edited = RewriteGuard.unwrapped(result)
        if let problem = RewriteGuard.problem(in: edited, source: text) {
            throw RewriteError.notEdited(problem.message)
        }
        return edited
    }

    /// Apple Intelligence on the device and nothing else, for features that promise the text
    /// stays on the device whatever the engine setting. Throws when it is not available.
    static func rewriteOnDevice(_ text: String, instruction: String, deterministic: Bool = false) async throws -> String {
        if case .unavailable(let reason) = localAvailability { throw RewriteError.onDevice(reason) }
        return try await rewriteLocally(text, instruction: instruction, deterministic: deterministic)
    }

    private static func rewriteLocally(_ text: String, instruction: String, deterministic: Bool) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instruction)
            let options = deterministic ? GenerationOptions(sampling: .greedy) : GenerationOptions()
            do {
                let response = try await session.respond(to: text, options: options)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                throw RewriteError.onDevice(Self.message(for: error))
            }
        }
        #endif
        throw RewriteError.noModel
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        let reason: String
        switch error {
        case .exceededContextWindowSize:
            reason = "Der Text ist zu lang für Apple Intelligence auf dem Gerät."
        case .guardrailViolation:
            reason = "Apple Intelligence hat den Text abgelehnt."
        case .unsupportedLanguageOrLocale:
            reason = "Apple Intelligence kann diese Sprache auf dem Gerät nicht bearbeiten."
        default:
            reason = "Apple Intelligence konnte den Text nicht bearbeiten."
        }
        let way = AIProviderStore.isConfigured
            ? "Mit „\(Engine.provider.displayName)“ in den Einstellungen übernimmt dein Modell-Anbieter."
            : "Mit einem eigenen API-Key in den Einstellungen geht es über einen Modell-Anbieter."
        return reason + " " + way
    }
    #endif
}
