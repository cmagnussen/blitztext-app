import Foundation

enum AIClientError: LocalizedError {
    case notConfigured
    case missingKey(AIProvider)
    case invalidAddress
    case http(Int, String?)
    case refused
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Kein Modell-Anbieter eingerichtet. Bitte in den Einstellungen einen API-Key hinterlegen."
        case .missingKey(let provider):
            return "Für \(provider.displayName) fehlt der API-Key."
        case .invalidAddress:
            return "Die Adresse des Modell-Anbieters ist ungültig."
        case .http(401, _), .http(403, _):
            return "Der API-Key wurde abgelehnt. Bitte in den Einstellungen prüfen."
        case .http(429, _):
            return "Zu viele Anfragen oder das Guthaben beim Anbieter ist aufgebraucht."
        case .http(let status, let message):
            return "Fehler vom Modell-Anbieter (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .refused:
            return "Der Modell-Anbieter hat die Anfrage abgelehnt."
        case .emptyResponse:
            return "Keine Antwort vom Modell-Anbieter erhalten. Bitte nochmal versuchen."
        }
    }
}

/// One instruction plus one text in, one text out. Talks directly to the provider,
/// so the text never passes through a Blitztext server.
enum AIClient {
    static func complete(instruction: String, text: String, config: AIProviderConfig) async throws -> String {
        let key = APIKeyStore.key(for: config.provider)
        if config.provider.requiresAPIKey, key == nil {
            throw AIClientError.missingKey(config.provider)
        }
        switch config.provider.apiStyle {
        case .openAICompatible:
            return try await openAICompatible(instruction: instruction, text: text, config: config, key: key)
        case .anthropic:
            return try await anthropic(instruction: instruction, text: text, config: config, key: key ?? "")
        }
    }

    /// Sends a tiny request to check address, key and model.
    static func testConnection(config: AIProviderConfig) async throws {
        _ = try await complete(instruction: "Antworte nur mit OK.", text: "Test", config: config)
    }

    // MARK: - OpenAI-compatible (OpenAI, Gemini, Mistral, OpenRouter, Ollama, ...)

    private static func openAICompatible(instruction: String, text: String, config: AIProviderConfig, key: String?) async throws -> String {
        guard let url = URL(string: trimmedBase(config.baseURL) + "/chat/completions") else {
            throw AIClientError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        // No temperature: several current models only accept their default.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text],
            ],
        ])

        let json = try await send(request)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIClientError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic Messages API

    private static func anthropic(instruction: String, text: String, config: AIProviderConfig, key: String) async throws -> String {
        guard let url = URL(string: trimmedBase(config.baseURL) + "/messages") else {
            throw AIClientError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": 16_000,
            "system": instruction,
            "messages": [["role": "user", "content": text]],
        ]
        if supportsEffort(config.model) {
            // Short rewrites need little reasoning; keeps answers fast and cheap.
            body["output_config"] = ["effort": "low"]
        }
        if ["claude-opus-5", "claude-fable-5", "claude-fable-5-1"].contains(config.model) {
            // If a safety classifier declines, Anthropic retries on a suitable model server-side.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await send(request)
        if (json["stop_reason"] as? String) == "refusal" {
            throw AIClientError.refused
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIClientError.emptyResponse }
        return text
    }

    // MARK: - Helpers

    /// `effort` exists on the current Opus, Sonnet and Fable models; Haiku 4.5 and
    /// older models reject it with a 400.
    private static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-fable", "claude-mythos", "claude-sonnet-5", "claude-opus-4-8",
         "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6"].contains { model.hasPrefix($0) }
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw AIClientError.http(status, errorMessage(in: json))
        }
        return json
    }

    /// Both API styles nest the message under "error".
    private static func errorMessage(in json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return json["error"] as? String
    }

    private static func trimmedBase(_ base: String) -> String {
        base.trimmingCharacters(in: CharacterSet(charactersIn: "/ ").union(.whitespacesAndNewlines))
    }
}
