import Foundation
import NaturalLanguage

/// The language the instructions are written in. It follows the transcript: the on-device
/// model drifts towards the language of its instructions, so German instructions turned
/// English dictations German, and English instructions turned half of the German
/// dictations English. German is the fallback when the recognizer cannot decide (short or
/// mixed dictations), because most dictations are German.
enum PromptLanguage {
    case german
    case english

    static func of(_ text: String) -> PromptLanguage {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else { return .german }
        return language == .english ? .english : .german
    }
}
