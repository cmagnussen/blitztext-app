import Foundation

/// The own modes also live in a file of their own. settings.json is rewritten by every build,
/// and builds without own modes drop the fields they don't know; this file they never touch,
/// so the modes survive going back to an older version and forward again. Its existence also
/// means the templates were added once (`AppState.seedCustomModesIfNeeded`).
/// Foundation only, so the tests compile it.
enum CustomModeFile {
    private struct Stored: Codable {
        var modes: [CustomMode]
    }

    /// Nil when there is no readable file yet.
    static func load(from url: URL) -> [CustomMode]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Stored.self, from: data))?.modes
    }

    static func save(_ modes: [CustomMode], to url: URL) {
        guard let data = try? JSONEncoder().encode(Stored(modes: modes)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
