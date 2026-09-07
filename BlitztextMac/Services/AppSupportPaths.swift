import Foundation

enum AppSupportPaths {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.blitztext.mac"

    static var appSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Blitztext", isDirectory: true)
    }

    static var settingsURL: URL {
        appSupportDirectoryURL.appendingPathComponent("settings.json")
    }

    static var dictationQueueURL: URL {
        appSupportDirectoryURL.appendingPathComponent("dictation-queue.json")
    }

    static var updatesDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("updates", isDirectory: true)
    }

    static var localModelsDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("models", isDirectory: true)
    }

    static var whisperKitModelsDirectoryURL: URL {
        localModelsDirectoryURL.appendingPathComponent("whisperkit", isDirectory: true)
    }

    static var defaultWhisperKitModelURL: URL {
        whisperKitModelsDirectoryURL.appendingPathComponent(
            "openai_whisper-large-v3-v20240930_626MB",
            isDirectory: true
        )
    }

    static var cachesDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist")
    }

    static var savedApplicationStateDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
    }

    static func ensureAppSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectoryURL,
            withIntermediateDirectories: true
        )
    }
}
