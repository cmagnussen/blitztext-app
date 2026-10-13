import AppKit
import Foundation

enum BlitztextInstallLocationService {
    enum InstallLocation: Equatable {
        case applications
        case userApplications
        case outsideApplications(URL)
        case unknown

        var isInApplicationsFolder: Bool {
            switch self {
            case .applications, .userApplications:
                return true
            case .outsideApplications, .unknown:
                return false
            }
        }

        var isCanonicalInstall: Bool {
            if case .applications = self {
                return true
            }
            return false
        }
    }

    enum MoveError: LocalizedError {
        case sourceBundleMissing(URL)
        case destinationUnavailable
        case destinationExists(URL)
        case destinationNotWritable(URL)
        case copyFailed(source: URL, destination: URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceBundleMissing:
                return "Die aktuelle App-Installation wurde nicht gefunden."
            case .destinationUnavailable:
                return "Der Zielordner /Applications ist nicht verfügbar."
            case .destinationExists:
                return "Am Zielort liegt bereits eine Blitztext-Installation."
            case .destinationNotWritable:
                return "Der Zielordner /Applications ist auf diesem Mac nicht beschreibbar."
            case .copyFailed:
                return "Blitztext konnte nicht nach /Applications kopiert werden."
            }
        }
    }

    static var bundleURL: URL {
        Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static var bundleName: String {
        bundleURL.deletingPathExtension().lastPathComponent
    }

    static var currentInstallLocation: InstallLocation {
        let currentDirectory = bundleURL.deletingLastPathComponent()
        let standardizedCurrentDirectory = currentDirectory.standardizedFileURL.resolvingSymlinksInPath()

        if standardizedCurrentDirectory == systemApplicationsDirectoryURL.standardizedFileURL.resolvingSymlinksInPath() {
            return .applications
        }

        if standardizedCurrentDirectory == userApplicationsDirectoryURL.standardizedFileURL.resolvingSymlinksInPath() {
            return .userApplications
        }

        if FileManager.default.fileExists(atPath: bundleURL.path) {
            return .outsideApplications(bundleURL)
        }

        return .unknown
    }

    /// Jamf installs Blitztext into /Applications on managed Macs. There the app neither
    /// moves itself nor updates itself; device management does both.
    static let isManagedByJamf: Bool = {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: "/usr/local/jamf/bin/jamf")
            || fileManager.fileExists(atPath: "/Library/Application Support/JAMF")
    }()

    static var shouldOfferMoveToApplications: Bool {
        !currentInstallLocation.isCanonicalInstall && !isManagedByJamf
    }

    static var systemApplicationsDirectoryURL: URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static var userApplicationsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    static var preferredInstallDirectoryURL: URL? {
        systemApplicationsDirectoryURL
    }

    static var preferredInstallBundleURL: URL? {
        preferredInstallDirectoryURL?.appendingPathComponent(bundleURL.lastPathComponent)
    }

    static var knownInstallBundleURLs: [URL] {
        let candidates = [
            bundleURL,
            systemApplicationsDirectoryURL.appendingPathComponent(bundleURL.lastPathComponent),
            userApplicationsDirectoryURL.appendingPathComponent(bundleURL.lastPathComponent)
        ]

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { return false }
            return FileManager.default.fileExists(atPath: candidate.path)
        }
    }

    static var otherInstalledBundleURLs: [URL] {
        knownInstallBundleURLs.filter { $0 != bundleURL }
    }

    static func moveCurrentAppToApplications(replacingExisting: Bool = true) throws -> URL {
        let sourceURL = bundleURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MoveError.sourceBundleMissing(sourceURL)
        }

        guard let destinationDirectoryURL = preferredInstallDirectoryURL else {
            throw MoveError.destinationUnavailable
        }

        let destinationURL = destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)

        if sourceURL.standardizedFileURL.resolvingSymlinksInPath() == destinationURL.standardizedFileURL.resolvingSymlinksInPath() {
            return destinationURL
        }

        try ensureDirectoryExists(at: destinationDirectoryURL)

        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: destinationDirectoryURL.path) else {
            throw MoveError.destinationNotWritable(destinationDirectoryURL)
        }

        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists && !replacingExisting {
            throw MoveError.destinationExists(destinationURL)
        }

        // Copy next to the destination first and swap in one step, so a failed copy
        // never costs the installation that works.
        let stagingURL = destinationDirectoryURL
            .appendingPathComponent(".\(sourceURL.lastPathComponent).incoming-\(UUID().uuidString)")
        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            let executable = stagingURL.appendingPathComponent("Contents/MacOS")
            guard fileManager.fileExists(atPath: executable.path) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if destinationExists {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw MoveError.copyFailed(source: sourceURL, destination: destinationURL, underlying: error)
        }

        return destinationURL
    }

    static func moveToApplicationsAndRelaunch(replacingExisting: Bool = true) throws {
        let destinationURL = try moveCurrentAppToApplications(replacingExisting: replacingExisting)

        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [destinationURL.path]
        try openProcess.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func ensureDirectoryExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
