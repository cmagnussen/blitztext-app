import Foundation
import FluidAudio

/// The Parakeet files on disk. New downloads are Parakeet Ultra, Moondream's post-training of
/// NVIDIA Parakeet TDT 0.6B v3: same architecture, languages and speed, fewer errors (4.9 instead
/// of 5.8 % WER on German FLEURS in Blitztext's run of FluidAudio's benchmark, October 2026).
/// A v3 download from an earlier version keeps working until Ultra is on disk, then it goes.
struct ParakeetModelFiles {
    enum Build {
        case ultra
        /// Parakeet TDT 0.6B v3, downloaded by Blitztext 1.11 and earlier.
        case legacy

        var version: AsrModelVersion {
            self == .ultra ? .ultra : .v3
        }
    }

    /// Holds one folder per build; FluidAudio finds a build's files by its folder name in here.
    let parent: URL

    var ultraDirectory: URL {
        parent.appendingPathComponent(Repo.parakeetUltra.folderName, isDirectory: true)
    }

    var legacyDirectory: URL {
        parent.appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    /// The build to load: Ultra when complete, else v3, nil when nothing is downloaded.
    var installed: Build? {
        if AsrModels.modelsExist(at: ultraDirectory, version: .ultra) { return .ultra }
        if AsrModels.modelsExist(at: legacyDirectory, version: .v3) { return .legacy }
        return nil
    }

    func directory(for build: Build) -> URL {
        build == .ultra ? ultraDirectory : legacyDirectory
    }

    /// Deletes the v3 files once Ultra is complete.
    func removeLegacyIfUpgraded() {
        guard installed == .ultra, FileManager.default.fileExists(atPath: legacyDirectory.path) else { return }
        try? FileManager.default.removeItem(at: legacyDirectory)
    }
}
