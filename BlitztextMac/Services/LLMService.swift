import Foundation

enum LLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von OpenAI: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        }
    }
}

enum RewriteModel: String {
    case fastEdit = "gpt-4o-mini"
    case rageMode = "gpt-4o"
}

/// Endpoint-Konfiguration für die Rewrite-Features.
/// `useLocal == false` → OpenAI; `true` → lokaler OpenAI-kompatibler Server (z. B. llama-server).
struct LLMConfig {
    var useLocal: Bool
    var baseURL: String
    var fastModel: String
    var strongModel: String

    static let openAI = LLMConfig(useLocal: false, baseURL: "", fastModel: "", strongModel: "")
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    // Nur für lokale Server gesetzt: begrenzt Runaway-Generierung bei GGUFs,
    // deren End-of-Turn-Token nicht als Stop-Token registriert ist (z. B. ChatML-Quants).
    var stop: [String]? = nil
    var maxTokens: Int? = nil

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case stop
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

enum LLMService {
    private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    static func improve(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit,
        config: LLMConfig = .openAI
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings),
            model: model,
            temperature: 0.3,
            config: config
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode,
        config: LLMConfig = .openAI
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4,
            config: config
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit,
        config: LLMConfig = .openAI
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3,
            config: config
        )
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double,
        config: LLMConfig
    ) async throws -> String {
        // Im Online-Modus ist der OpenAI-Key Pflicht; lokal ist er optional.
        let apiKey = KeychainService.load(key: .openAIAPIKey)
        if !config.useLocal && apiKey == nil {
            throw LLMError.notConfigured
        }

        let modelName: String
        if config.useLocal {
            modelName = model == .rageMode ? config.strongModel : config.fastModel
        } else {
            modelName = model.rawValue
        }

        let payload = OpenAIChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text),
            ],
            temperature: temperature,
            stop: config.useLocal ? ["<|im_end|>", "<end_of_turn>", "<|eot_id|>"] : nil,
            maxTokens: config.useLocal ? 2048 : nil
        )

        var request = URLRequest(url: config.useLocal ? resolvedLocalURL(config.baseURL) : chatCompletionsURL)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Keine gültige Antwort")
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noContent
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func openAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error?.message
    }

    /// Setzt aus der konfigurierten Base-URL (z. B. "http://localhost:8080/v1") den
    /// Chat-Completions-Endpoint zusammen. Fällt bei ungültiger URL auf OpenAI zurück.
    private static func resolvedLocalURL(_ baseURL: String) -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized + "/chat/completions") ?? chatCompletionsURL
    }

    private static func buildEmojiSystemPrompt(density: EmojiTextSettings.EmojiDensity) -> String {
        let densityInstruction: String
        switch density {
        case .wenig:
            densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
        case .mittel:
            densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
        case .viel:
            densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
        }

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
    }

    private static func buildSystemPrompt(settings: TextImprovementSettings) -> String {
        if !settings.systemPrompt.isEmpty {
            var prompt = settings.systemPrompt
            if !settings.customTerms.isEmpty {
                prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
            }
            return prompt
        }

        var prompt = """
        Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
        - Korrigiere Rechtschreibung und Grammatik
        - Verbessere die Formulierung und den Lesefluss
        - Behalte die urspruengliche Bedeutung bei
        - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
        """

        switch settings.tone {
        case .formal:
            prompt += "\n- Verwende einen formellen, professionellen Ton"
        case .neutral:
            prompt += "\n- Verwende einen neutralen, klaren Ton"
        case .casual:
            prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
        }

        if !settings.customTerms.isEmpty {
            prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
        }

        if !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt
    }
}
