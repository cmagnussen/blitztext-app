import AppKit

/// Uses the macOS spell checker to tell real words ("Cloud", "Blackbox") from
/// misheard names ("Clawd", "Blackboad"), so fuzzy term correction leaves real words alone.
enum DictionaryWordChecker {
    private static let languages = ["de", "en"]

    static func isKnownWord(_ word: String) -> Bool {
        guard word.count > 1 else { return true }
        let checker = NSSpellChecker.shared
        let available = Set(checker.availableLanguages.map { $0.split(separator: "_").first.map(String.init) ?? $0 })

        for language in languages where available.contains(language) {
            let range = checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            if range.location == NSNotFound {
                return true
            }
        }
        return false
    }
}
