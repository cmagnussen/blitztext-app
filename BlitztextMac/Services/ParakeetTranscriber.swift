import Foundation
import FluidAudio

/// Local transcription with NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0) via FluidAudio (Apache-2.0).
/// Runs on the Apple Neural Engine and supports 25 European languages including German.
/// Apple Silicon only; Intel Macs keep using WhisperKit.
actor ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    static let modelName = "parakeet-tdt-0.6b-v3"
    static let modelPageURL = URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// FluidAudio expects the repo folder itself (it resolves siblings via its parent).
    static var modelsDirectoryURL: URL {
        AppSupportPaths.localModelsDirectoryURL
            .appendingPathComponent("parakeet", isDirectory: true)
            .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    static var isInstalled: Bool {
        isSupported && AsrModels.modelsExist(at: modelsDirectoryURL, version: .v3)
    }

    private var manager: AsrManager?
    /// The load in flight. Actor methods are reentrant at `await`, so without this a
    /// second dictation during a slow load started another full model load.
    private var loadTask: Task<AsrManager, Error>?

    var isReady: Bool { manager != nil }

    func download(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(
            at: Self.modelsDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await AsrModels.download(to: Self.modelsDirectoryURL, version: .v3) { progress in
            let fraction = progress.fractionCompleted
            progressHandler(fraction.isFinite ? min(max(fraction, 0), 1) : 0)
        }
        manager = nil
        loadTask = nil
        progressHandler(1)
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

    private func loadedManager() async throws -> AsrManager {
        if let manager {
            return manager
        }
        if let loadTask {
            return try await loadTask.value
        }
        guard Self.isInstalled else {
            throw LocalTranscriptionError.modelMissing(Self.modelsDirectoryURL)
        }

        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.load(from: Self.modelsDirectoryURL, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loadTask = task
        do {
            let manager = try await task.value
            self.manager = manager
            loadTask = nil
            return manager
        } catch {
            loadTask = nil
            throw error
        }
    }
}
