import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermissionService {
    private static var hasPromptedThisSession = false

    static func currentStatus() -> Bool {
        AXIsProcessTrusted()
    }

    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        let shouldPrompt = promptIfNeeded && !hasPromptedThisSession
        if shouldPrompt {
            hasPromptedThisSession = true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPermissionPrompt() -> Bool {
        hasPromptedThisSession = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Removes the Accessibility entry for this bundle ID. After an update macOS can keep a stale
    /// entry that shows as enabled but no longer matches the app; only removing it helps.
    nonisolated static func resetPermission() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
