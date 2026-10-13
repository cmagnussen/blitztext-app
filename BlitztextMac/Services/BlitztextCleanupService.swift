import Foundation
import ServiceManagement

enum BlitztextCleanupService {
    struct CleanupItemFailure: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let errorDescription: String
    }

    struct CleanupReport: Equatable {
        let removedURLs: [URL]
        let failedItems: [CleanupItemFailure]
        let knownInstallBundleURLs: [URL]

        var didSucceedFully: Bool {
            failedItems.isEmpty
        }
    }

    static func cleanupUserData() -> CleanupReport {
        cleanup(paths: [
            AppSupportPaths.settingsURL,
            AppSupportPaths.credentialsURL,
            AppSupportPaths.appSupportDirectoryURL,
            AppSupportPaths.cachesDirectoryURL,
            AppSupportPaths.preferencesURL,
            AppSupportPaths.savedApplicationStateDirectoryURL
        ], unregisterLaunchAtLogin: true)
    }

    static func removeLaunchAtLoginRegistration() -> CleanupReport {
        cleanup(paths: [], unregisterLaunchAtLogin: true)
    }

    static func removeApplicationSupportFiles() -> CleanupReport {
        cleanup(
            paths: [
                AppSupportPaths.settingsURL,
                AppSupportPaths.credentialsURL,
                AppSupportPaths.appSupportDirectoryURL
            ],
            unregisterLaunchAtLogin: false
        )
    }

    static func removeCacheAndStateFiles() -> CleanupReport {
        cleanup(
            paths: [
                AppSupportPaths.cachesDirectoryURL,
                AppSupportPaths.preferencesURL,
                AppSupportPaths.savedApplicationStateDirectoryURL
            ],
            unregisterLaunchAtLogin: false
        )
    }

    static func knownInstallBundleURLs() -> [URL] {
        BlitztextInstallLocationService.knownInstallBundleURLs
    }

    static func cleanup(paths: [URL], unregisterLaunchAtLogin: Bool) -> CleanupReport {
        var removedURLs: [URL] = []
        var failedItems: [CleanupItemFailure] = []

        if unregisterLaunchAtLogin {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                failedItems.append(
                    CleanupItemFailure(
                        url: BlitztextInstallLocationService.bundleURL,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        for url in paths {
            do {
                try removeItemIfNeeded(at: url)
                removedURLs.append(url)
            } catch {
                failedItems.append(
                    CleanupItemFailure(
                        url: url,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        return CleanupReport(
            removedURLs: removedURLs,
            failedItems: failedItems,
            knownInstallBundleURLs: BlitztextInstallLocationService.otherInstalledBundleURLs
        )
    }

    private static func removeItemIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
