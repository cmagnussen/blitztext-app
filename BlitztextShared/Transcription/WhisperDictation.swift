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
    static func transcribe(_ pipeline: WhisperKit, audioPath: String) async throws -> String {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
        // No fixed language: Whisper follows a given language strictly and turns English
        // speech into German. Detection keeps every dictation in its spoken language.
        let options = DecodingOptions(task: .transcribe, language: nil, detectLanguage: true)
        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if HallucinationFilter.isInvented(text, longestVoicedRun: HallucinationFilter.longestVoicedRun(samples)) {
            return ""
        }
        return HallucinationFilter.removingTrailingCredits(text)
    }
}
