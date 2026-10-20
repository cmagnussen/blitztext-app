import Foundation

/// Gemma 4 chat format, written out from the model's `chat_template.jinja`.
///
/// Why by hand: swift-jinja 2.3.5 (the version WhisperKit's swift-transformers pins) renders
/// the Gemma 4 template, but keeps the blank lines before `{#- ... -#}` comments that
/// Python's Jinja, the reference the model was trained with, strips. The prompt would then
/// carry an extra "\n\n" after the system turn. The format itself is short and stable, so
/// it is built here exactly as the reference renders it.
///
/// Also strips what is not part of the answer (thinking channel, control tokens) from the
/// generated text. Pure string logic, no MLX, so it builds on every architecture and is
/// unit tested.
enum GemmaChatFormat {
    static let bosToken = "<bos>"
    static let turnStart = "<|turn>"
    static let turnEnd = "<turn|>"
    static let channelStart = "<|channel>"
    static let channelEnd = "<channel|>"

    /// Whether a `config.json` `model_type` is a Gemma 4 model (`gemma4`, `gemma4_unified`,
    /// `gemma4_text`).
    static func isGemma4(modelType: String) -> Bool {
        modelType.hasPrefix("gemma4")
    }

    /// Whether the template closes the thinking channel right after `<|turn>model\n` when
    /// thinking is off. Newer Gemma 4 templates do, so the model answers directly; older
    /// ones end at `model\n`. Looks for the literal the newer template writes.
    static func closesThinking(template: String) -> Bool {
        template.contains("<|channel>thought\\n<channel|>")
    }

    /// What the Gemma 4 template renders for `[system, user]` with `add_generation_prompt`
    /// and thinking off:
    ///
    ///     <bos><|turn>system\n{system}<turn|>\n<|turn>user\n{user}<turn|>\n<|turn>model\n
    ///
    /// plus `<|channel>thought\n<channel|>` when the template closes the thinking channel.
    /// The template trims both contents and writes no system turn without a system message.
    static func prompt(system: String, user: String, closesThinking: Bool) -> String {
        var text = bosToken
        let system = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            text += turnStart + "system\n" + system + turnEnd + "\n"
        }
        text += turnStart + "user\n" + user.trimmingCharacters(in: .whitespacesAndNewlines) + turnEnd + "\n"
        text += turnStart + "model\n"
        if closesThinking {
            text += channelStart + "thought\n" + channelEnd
        }
        return text
    }

    /// The answer alone: without thinking, without anything after the end of the model's
    /// turn and without control tokens.
    static func cleaned(_ output: String) -> String {
        var text = output
        // Thinking runs from <|channel> to <channel|>. One that never closes was cut off
        // by the token limit, so everything after it is thinking too.
        while let start = text.range(of: channelStart) {
            if let end = text.range(of: channelEnd, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                text.removeSubrange(start.lowerBound..<text.endIndex)
            }
        }
        text = text.replacingOccurrences(of: channelEnd, with: "")
        if let end = text.range(of: turnEnd) {
            text = String(text[..<end.lowerBound])
        }
        for token in ["<eos>", bosToken, "<pad>", turnStart] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
