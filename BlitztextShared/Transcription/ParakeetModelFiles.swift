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

    /// Where Ultra downloads first. FluidAudio names the folder after the model, so the
    /// staging place is a parent of its own; an interrupted download resumes in there.
    var stagedUltraDirectory: URL {
        parent.appendingPathComponent("download", isDirectory: true)
            .appendingPathComponent(Repo.parakeetUltra.folderName, isDirectory: true)
    }

    /// The build to load: Ultra when complete, else v3, nil when nothing is downloaded.
    /// Ultra must be complete, not only present: builds before October 2026 downloaded it
    /// straight into place, and an interrupted download left it half there.
    var installed: Build? {
        if AsrModels.modelsExist(at: ultraDirectory, version: .ultra), CompiledModelCheck.isComplete(ultraDirectory) {
            return .ultra
        }
        if AsrModels.modelsExist(at: legacyDirectory, version: .v3) { return .legacy }
        return nil
    }

    /// Moves a complete staged Ultra into place in one step, replacing a half one.
    func installStagedUltra() throws {
        guard CompiledModelCheck.isComplete(stagedUltraDirectory) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: ultraDirectory.path) {
            try fileManager.removeItem(at: ultraDirectory)
        }
        try fileManager.moveItem(at: stagedUltraDirectory, to: ultraDirectory)
        try? fileManager.removeItem(at: stagedUltraDirectory.deletingLastPathComponent())
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
