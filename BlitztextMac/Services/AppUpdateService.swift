import Combine
import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class AppUpdateService {
    private let updaterController: SPUStandardUpdaterController
    private let updaterSettings: SPUUpdaterSettings
    private var cancellables: Set<AnyCancellable> = []
    private var didStartUpdater = false

    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false {
        didSet {
            guard oldValue != automaticallyChecksForUpdates else { return }
            updaterSettings.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var automaticallyDownloadsUpdates = false {
        didSet {
            guard oldValue != automaticallyDownloadsUpdates else { return }
            updaterSettings.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    var statusText: String

    private let feedURLString: String
    private let publicKey: String

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterSettings = SPUUpdaterSettings(hostBundle: .main)
        self.feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        self.publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        self.automaticallyChecksForUpdates = updaterSettings.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updaterSettings.automaticallyDownloadsUpdates
        self.statusText = Self.configurationHint(
            isConfigured: Self.isConfigured(
                feedURLString: feedURLString,
                publicKey: publicKey
            )
        )
        bindUpdaterState()
    }

    var isConfigured: Bool {
        Self.isConfigured(feedURLString: feedURLString, publicKey: publicKey)
    }

    /// Jamf installs Blitztext on managed Macs. Sparkle stays off there, so nobody gets a
    /// second update channel or an admin password prompt. This applies to the whole Mac,
    /// also to a copy installed by hand.
    let isManagedByDeviceManagement = BlitztextInstallLocationService.isManagedByJamf

    /// Sparkle runs: the build has a feed and key, and no device management does the job.
    var updatesInApp: Bool {
        isConfigured && !isManagedByDeviceManagement
    }

    var configurationHint: String {
        Self.configurationHint(isConfigured: isConfigured)
    }

    func startIfConfigured() {
        guard updatesInApp, !didStartUpdater else { return }

        updaterController.startUpdater()
        didStartUpdater = true
        statusText = "Blitztext hält sich über Sparkle aktuell."
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        guard updatesInApp else {
            statusText = configurationHint
            return
        }

        startIfConfigured()
        statusText = "Suche nach Updates …"
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }

    private func bindUpdaterState() {
        canCheckForUpdates = updatesInApp

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    private static func isConfigured(feedURLString: String, publicKey: String) -> Bool {
        let normalizedFeedURL = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFeedURL.isEmpty,
              !normalizedPublicKey.isEmpty,
              URL(string: normalizedFeedURL) != nil,
              !normalizedFeedURL.contains("example.invalid"),
              normalizedPublicKey != "SPARKLE_PUBLIC_ED_KEY_NOT_CONFIGURED",
              normalizedPublicKey != "REPLACE_WITH_GENERATED_PUBLIC_KEY" else {
            return false
        }

        return true
    }

    private static func configurationHint(isConfigured: Bool) -> String {
        if isConfigured {
            return "Updates werden über den hinterlegten Sparkle-Feed verteilt."
        }
        return "Für Auto-Updates fehlen noch Feed-URL oder öffentlicher Sparkle-Key im Build."
    }
}
