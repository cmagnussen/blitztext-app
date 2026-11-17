import Foundation
import WhisperKit

/// How both apps run Whisper on a dictation: language detection and dropping text that
/// Whisper most likely invented. Short live dictations without speech never get here: both
/// apps check for speech before any model runs (`HallucinationFilter.longestVoicedRun(in:)`);
/// a cough or a click that passes that check still loses a lone "Thank you." here.
///
/// No dictionary prompt: with WhisperKit 0.18 and Large v3 Turbo, any `promptTokens`
/// (even a single word) made the decoder stop at once and return an empty text.
enum WhisperDictation {
    enum Outcome: Equatable {
        case text(String)
        /// Only a phrase Whisper invents on silence ("Thank you."), on a recording with hardly
        /// any speech: the Mac treats it as a dictation without speech, so a short one goes.
        case inventedOnSilence
    }

    /// The text, empty when Whisper most likely invented it.
    static func transcribe(_ pipeline: WhisperKit, audioPath: String) async throws -> String {
        switch try await run(pipeline, audioPath: audioPath) {
        case .text(let text): return text
        case .inventedOnSilence: return ""
        }
    }

    /// No fixed language: Whisper follows a given language strictly and turns English
    /// speech into German. Detection keeps every dictation in its spoken language.
    ///
    /// No check of the first token: when the model is unsure of its first word, WhisperKit
    /// stops the first pass and retries with rising temperature. With the streaming build of
    /// Large v3 Turbo (the one on iOS and on Macs from M2) those retries returned nothing or a
    /// lone "Vielen Dank." for dictations with speech: 8 of 55 Swiss German recordings and
    /// 3 of 20 clips of two seconds. Without the check the first
    /// pass runs to the end; the other fallback checks stay. Standard German, English, silence
    /// and noise gave the same text with and without it, and so did the plain Turbo build.
    static var decodingOptions: DecodingOptions {
        var options = DecodingOptions(task: .transcribe, language: nil, detectLanguage: true)
        options.firstTokenLogProbThreshold = nil
        return options
    }

    static func run(_ pipeline: WhisperKit, audioPath: String) async throws -> Outcome {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: decodingOptions)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let kept = HallucinationFilter.whisperText(text, longestVoicedRun: HallucinationFilter.longestVoicedRun(samples)) else {
            return .inventedOnSilence
        }
        return .text(kept)
    }
}
