#if arch(arm64)
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// A local language model in MLX format (tested with Gemma 4 E4B and 12B, 4-bit), loaded
/// from a folder on disk with `config.json`, `*.safetensors`, `tokenizer.json`,
/// `tokenizer_config.json` and `chat_template.jinja`. Nothing is downloaded.
///
/// Runs on the GPU of Apple Silicon Macs only, hence `#if arch(arm64)`. Load once, run one
/// or more prompts, then `unload()`: the weights stay in memory until then (about 4 GB for
/// E4B and 6 GB for 12B at 4 bit).
actor LocalLanguageModel {
    enum Failure: LocalizedError {
        case missingFile(String)
        /// The answer reached `maxTokens` and is cut off.
        case cutOff

        var errorDescription: String? {
            switch self {
            case .missingFile(let name):
                "Im Modellordner fehlt \(name)."
            case .cutOff:
                "Die Antwort war zu lang und wurde abgeschnitten."
            }
        }
    }

    /// How prompts are written for the loaded model.
    enum PromptFormat: Sendable, Equatable {
        /// Gemma 4, written by `GemmaChatFormat` (see there why not by the template).
        case gemma4(closesThinking: Bool)
        /// Any other model: the chat template that ships with it.
        case chatTemplate
    }

    /// Figures of the last `complete` call.
    struct Statistics: Sendable {
        var promptTokens: Int
        var generatedTokens: Int
        var promptSeconds: Double
        var generationSeconds: Double
        var promptFormat: PromptFormat
        var stoppedAtTokenLimit: Bool

        var promptTokensPerSecond: Double { promptSeconds > 0 ? Double(promptTokens) / promptSeconds : 0 }
        var tokensPerSecond: Double { generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0 }
    }

    /// Upper bound for MLX's buffer cache, the freed GPU buffers MLX keeps for reuse.
    /// Without a limit it grows to the size of the largest prompt and stays there; with it,
    /// memory goes back to the system between steps. 256 MB is what mlx-swift-lm uses for
    /// its own on-device adapter. The weights and the KV cache are not affected.
    static let bufferCacheLimit = 256 * 1024 * 1024

    let folder: URL
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private(set) var promptFormat: PromptFormat = .chatTemplate
    private(set) var lastStatistics: Statistics?

    init(folder: URL) {
        self.folder = folder
    }

    var isLoaded: Bool { container != nil }

    /// Reads weights and tokenizer. Called by `complete` if needed; call it ahead to
    /// measure or to hide the load time.
    func load() async throws {
        _ = try await loadedContainer()
    }

    /// Answers `text` following `instruction` (sent as the system turn), greedy at
    /// temperature 0 so the same input gives the same output. Returns the answer without
    /// thinking and control tokens. With `failsWhenCutOff`, an answer that reached
    /// `maxTokens` throws `Failure.cutOff` instead of coming back incomplete.
    func complete(instruction: String, text: String, maxTokens: Int, failsWhenCutOff: Bool = false) async throws -> String {
        let container = try await loadedContainer()
        let format = promptFormat
        let (raw, statistics) = try await container.perform { context in
            let promptTokens = try Self.promptTokens(
                instruction: instruction, text: text, format: format, tokenizer: context.tokenizer
            )
            let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
            var generated: [Int] = []
            var info: GenerateCompletionInfo?
            let (stream, generation) = try generateTokensTask(
                input: LMInput(tokens: MLXArray(promptTokens)), parameters: parameters, context: context
            )
            for await item in stream {
                switch item {
                case .token(let token): generated.append(token)
                case .info(let completion): info = completion
                }
            }
            // A cancelled caller ends the stream early while MLX still finishes its step and
            // holds the model; `unload()` right after must find it done, or the weights stay.
            await generation.value
            let raw = context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: false)
            let statistics = Statistics(
                promptTokens: promptTokens.count,
                generatedTokens: generated.count,
                promptSeconds: info?.promptTime ?? 0,
                generationSeconds: info?.generateTime ?? 0,
                promptFormat: format,
                stoppedAtTokenLimit: info?.stopReason == .length
            )
            return (raw, statistics)
        }
        lastStatistics = statistics
        if failsWhenCutOff, statistics.stoppedAtTokenLimit { throw Failure.cutOff }
        return GemmaChatFormat.cleaned(raw)
    }

    /// Frees the weights and MLX's buffer cache. The next `complete` loads again.
    func unload() {
        loading?.cancel()
        loading = nil
        container = nil
        Memory.clearCache()
    }

    /// Memory MLX holds right now: in arrays (weights, KV cache), in its buffer cache, and
    /// the peak since launch. Bytes.
    nonisolated static func memory() -> (active: Int, cache: Int, peak: Int) {
        (Memory.activeMemory, Memory.cacheMemory, Memory.peakMemory)
    }

    private static func promptTokens(
        instruction: String, text: String, format: PromptFormat, tokenizer: any MLXLMCommon.Tokenizer
    ) throws -> [Int] {
        switch format {
        case .gemma4(let closesThinking):
            let prompt = GemmaChatFormat.prompt(system: instruction, user: text, closesThinking: closesThinking)
            return tokenizer.encode(text: prompt, addSpecialTokens: false)
        case .chatTemplate:
            var messages: [[String: any Sendable]] = []
            if !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(["role": "system", "content": instruction])
            }
            messages.append(["role": "user", "content": text])
            return try tokenizer.applyChatTemplate(
                messages: messages, tools: nil, additionalContext: ["enable_thinking": false]
            )
        }
    }

    /// Gemma 4 by `model_type` in `config.json`; whether its template closes the thinking
    /// channel by `chat_template.jinja`.
    private static func promptFormat(of folder: URL) -> PromptFormat {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelType = config["model_type"] as? String,
              GemmaChatFormat.isGemma4(modelType: modelType) else {
            return .chatTemplate
        }
        let template = (try? String(contentsOf: folder.appendingPathComponent("chat_template.jinja"), encoding: .utf8)) ?? ""
        return .gemma4(closesThinking: GemmaChatFormat.closesThinking(template: template))
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }
        for name in ["config.json", "tokenizer.json"]
        where !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            throw Failure.missingFile(name)
        }
        Memory.cacheLimit = Self.bufferCacheLimit
        let folder = folder
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(from: folder, using: TransformersTokenizerLoader())
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        promptFormat = Self.promptFormat(of: folder)
        container = loaded
        return loaded
    }
}

#if DEBUG
extension LocalLanguageModel {
    /// Debug check only: renders the prompt with the model's chat template (swift-jinja)
    /// and with the format in use, and says where they differ.
    func compareChatFormats(instruction: String, text: String) async throws -> String {
        let container = try await loadedContainer()
        let format = promptFormat
        return await container.perform { context in
            guard let used = try? Self.promptTokens(
                instruction: instruction, text: text, format: format, tokenizer: context.tokenizer
            ) else { return "Prompt nicht baubar" }
            let template: [Int]
            do {
                template = try Self.promptTokens(
                    instruction: instruction, text: text, format: .chatTemplate, tokenizer: context.tokenizer
                )
            } catch {
                return "Format \(format), Chat-Vorlage nicht renderbar: \(error.localizedDescription)"
            }
            if template == used {
                return "Format \(format), gleich wie Chat-Vorlage (\(used.count) Tokens)"
            }
            let first = zip(template, used).prefix { $0 == $1 }.count
            func excerpt(_ tokens: [Int]) -> String {
                context.tokenizer.decode(
                    tokenIds: Array(tokens[max(0, first - 3)..<min(tokens.count, first + 6)]), skipSpecialTokens: false
                ).debugDescription
            }
            return "Format \(format), Chat-Vorlage (swift-jinja) weicht ab (\(template.count) gegen \(used.count) Tokens), ab Token \(first): Vorlage \(excerpt(template)), verwendet \(excerpt(used))"
        }
    }
}
#endif
#endif
