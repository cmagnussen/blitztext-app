import Foundation
import Observation

/// Zustandsautomat fuer Updates. Die einzige Einheit, die die Oberflaeche
/// kennt. Sie liest nur `state` und ruft die drei Methoden auf.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading(Double)
        case verifying
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    var automaticChecksEnabled: Bool {
        didSet { onSettingsChange(automaticChecksEnabled, lastCheck) }
    }

    private let repository: String?
    private let publicKey: String?
    private let isBusy: @MainActor () -> Bool
    private let onSettingsChange: @MainActor (Bool, Date?) -> Void
    private var laufenderVorgang = false

    init(
        automaticChecksEnabled: Bool,
        lastCheck: Date?,
        repository: String? = UpdateConfiguration.repository,
        publicKey: String? = UpdateConfiguration.publicKey,
        isBusy: @escaping @MainActor () -> Bool,
        onSettingsChange: @escaping @MainActor (Bool, Date?) -> Void
    ) {
        self.automaticChecksEnabled = automaticChecksEnabled
        self.lastCheck = lastCheck
        self.repository = repository
        self.publicKey = publicKey
        self.isBusy = isBusy
        self.onSettingsChange = onSettingsChange
    }

    var availableRelease: UpdateRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var hasAvailableUpdate: Bool {
        availableRelease != nil
    }

    var currentInstallBlock: UpdatePolicy.InstallBlock? {
        UpdatePolicy.installBlock(
            isInApplicationsFolder: BlitztextInstallLocationService
                .currentInstallLocation
                .isInApplicationsFolder,
            isBusy: isBusy()
        )
    }

    /// Beim Programmstart aufrufen. Prueft nur, wenn die Automatik an ist und
    /// heute noch nicht geprueft wurde.
    func startAutomaticCheckIfNeeded() {
        guard UpdatePolicy.shouldRunAutomaticCheck(
            now: Date(),
            lastCheck: lastCheck,
            automaticChecksEnabled: automaticChecksEnabled,
            calendar: Calendar.current
        ) else { return }
        checkForUpdates(manuell: false)
    }

    func checkForUpdates(manuell: Bool) {
        guard !laufenderVorgang else { return }
        guard let repository else {
            if manuell { state = .failed("In dieser App ist kein Update-Repository hinterlegt.") }
            return
        }

        laufenderVorgang = true
        state = .checking

        Task { [weak self] in
            guard let self else { return }
            defer { self.laufenderVorgang = false }
            do {
                let client = UpdateFeedClient(repository: repository)
                let treffer = try await client.fetchNewestRelease()
                self.merkePruefzeitpunkt()

                guard let treffer, let aktuell = AppVersion.current, treffer.version > aktuell else {
                    self.state = .upToDate
                    return
                }
                self.state = .available(treffer)
            } catch {
                // Der automatische Check scheitert still, damit ein fehlendes
                // Netz beim Start niemanden stoert.
                self.state = manuell ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available(let release) = state, !laufenderVorgang else { return }
        if let sperre = currentInstallBlock {
            state = .failed(sperre.hinweis)
            return
        }
        guard let publicKey else {
            state = .failed("In dieser App ist kein Update-Schlüssel hinterlegt.")
            return
        }

        laufenderVorgang = true
        state = .downloading(0)

        Task { [weak self] in
            guard let self else { return }
            defer { self.laufenderVorgang = false }
            do {
                let downloader = UpdateDownloader()
                let ergebnis = try await downloader.download(
                    release,
                    into: AppSupportPaths.updatesDirectoryURL
                ) { anteil in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(anteil)
                    }
                }

                // Beide Schritte abseits des Hauptthreads, sonst friert die
                // Oberflaeche waehrend des Entpackens ein.
                self.state = .verifying
                try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.verify(
                        archiv: ergebnis.archivURL,
                        signatur: ergebnis.signatur,
                        publicKeyBase64: publicKey
                    )
                }.value

                // Die Sperre gilt nicht nur beim Klick: zwischen Klick und
                // hier liegen Download und Pruefung, und ein globaler Hotkey
                // kann in dieser Zeit eine Aufnahme gestartet haben. Bis zu
                // diesem Punkt ist ein Abbruch folgenlos, nach dem
                // Bundle-Tausch waere er es nicht mehr. Deshalb genau hier.
                if let sperre = self.currentInstallBlock {
                    self.state = .failed(sperre.hinweis)
                    return
                }

                self.state = .installing
                try await Task.detached(priority: .userInitiated) {
                    // Beendet die App im Erfolgsfall, damit sie neu startet.
                    try UpdateInstaller.install(
                        archiv: ergebnis.archivURL,
                        erwarteteVersion: release.version
                    )
                }.value
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func merkePruefzeitpunkt() {
        lastCheck = Date()
        onSettingsChange(automaticChecksEnabled, lastCheck)
    }
}
