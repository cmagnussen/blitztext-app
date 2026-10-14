import Foundation
import FluidAudio

/// Local transcription with Parakeet via FluidAudio (Apache-2.0): Parakeet Ultra by Moondream,
/// a post-training of NVIDIA Parakeet TDT 0.6B v3 (both CC BY 4.0). Macs that downloaded v3
/// with an earlier version keep using it until the background upgrade to Ultra is done.
/// Runs on the Apple Neural Engine and supports 25 European languages including German.
/// Apple Silicon only; Intel Macs keep using WhisperKit.
actor ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    /// Settings key of the Parakeet entry, kept from the v3 days so existing choices stay.
    static let modelName = "parakeet-tdt-0.6b-v3"
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static var files: ParakeetModelFiles {
        ParakeetModelFiles(parent: AppSupportPaths.localModelsDirectoryURL.appendingPathComponent("parakeet", isDirectory: true))
    }

    /// An earlier v3 download is in use because Ultra is not on disk yet.
    static var usesLegacyModel: Bool {
        files.installed == .legacy
    }

    static var displayName: String {
        usesLegacyModel ? "Parakeet v3" : "Parakeet Ultra"
    }

    static var modelPageURL: URL {
        usesLegacyModel
            ? URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!
            : URL(string: "https://huggingface.co/moondream/parakeet-ultra")!
    }

    /// Credit required by CC BY 4.0, as Markdown with the license link.
    static var attribution: String {
        let license = "[CC BY 4.0](\(licenseURL.absoluteString))"
        return usesLegacyModel
            ? "Parakeet TDT 0.6B v3 von NVIDIA, \(license), via FluidAudio."
            : "Parakeet Ultra von Moondream, nachtrainiert aus NVIDIA Parakeet TDT 0.6B v3, \(license), via FluidAudio."
    }

    /// The folder of the build in use, or of Ultra before anything is downloaded.
    static var modelsDirectoryURL: URL {
        files.directory(for: files.installed ?? .ultra)
    }

    static var isInstalled: Bool {
        isSupported && files.installed != nil
    }

    static var needsUpgrade: Bool {
        isSupported && files.installed == .legacy
    }

    private var manager: AsrManager?
    private var managerBuild: ParakeetModelFiles.Build?
    /// The load in flight. Actor methods are reentrant at `await`, so without this a
    /// second dictation during a slow load started another full model load.
    private var loadTask: Task<AsrManager, Error>?
    private var loadTaskBuild: ParakeetModelFiles.Build?
    private var downloadTask: Task<Void, Error>?

    var isReady: Bool {
        manager != nil && managerBuild == Self.files.installed
    }

    func download(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        try await downloadUltra(progressHandler: progressHandler)
        progressHandler(1)
    }

    /// Replaces an earlier v3 download with Ultra. Dictation keeps using v3 until Ultra is
    /// downloaded and loaded; then the v3 files are deleted.
    func upgrade() async throws {
        guard Self.needsUpgrade else { return }
        try await downloadUltra { _ in }
        try await prepare()
        Self.files.removeLegacyIfUpgraded()
    }

    func prepare() async throws {
        _ = try await loadedManager()
    }

    func transcribe(audioURL: URL, language: String) async throws -> String {
        let manager = try await loadedManager()
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let languageHint = Language(rawValue: language.lowercased())
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState, language: languageHint)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One download at a time, whether the user started it or the upgrade did.
    private func downloadUltra(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        if let downloadTask {
            return try await downloadTask.value
        }
        let files = Self.files
        let task = Task<Void, Error> {
            try FileManager.default.createDirectory(at: files.parent, withIntermediateDirectories: true)
            _ = try await AsrModels.download(to: files.ultraDirectory, version: .ultra) { progress in
                let fraction = progress.fractionCompleted
                progressHandler(fraction.isFinite ? min(max(fraction, 0), 1) : 0)
            }
        }
        downloadTask = task
        defer { downloadTask = nil }
        try await task.value
    }

    /// The loaded model, reloaded when the build on disk changed (v3 to Ultra).
    private func loadedManager() async throws -> AsrManager {
        guard Self.isSupported, let build = Self.files.installed else {
            throw LocalTranscriptionError.modelMissing(Self.modelsDirectoryURL)
        }
        if let manager, managerBuild == build {
            return manager
        }
        if let loadTask, loadTaskBuild == build {
            return try await loadTask.value
        }

        let directory = Self.files.directory(for: build)
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.load(from: directory, version: build.version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loadTask = task
        loadTaskBuild = build
        defer {
            if loadTaskBuild == build {
                loadTask = nil
                loadTaskBuild = nil
            }
        }
        let manager = try await task.value
        self.manager = manager
        managerBuild = build
        return manager
    }
}
