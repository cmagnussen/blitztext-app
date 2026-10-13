import Foundation
import WhisperKit

struct LocalTranscriptionModel: Identifiable, Hashable {
    let id: String
    let url: URL
    let isInstalled: Bool

    init(id: String, url: URL, isInstalled: Bool = true) {
        self.id = id
        self.url = url
        self.isInstalled = isInstalled
    }

    var displayName: String {
        Self.displayName(for: id)
    }

    var isParakeet: Bool {
        id == ParakeetTranscriber.modelName
    }

    var shortDisplayName: String {
        if isParakeet {
            return "Parakeet v3"
        }
        if id.contains("small") {
            return "Whisper Small"
        }
        if id.contains("base") {
            return "Whisper Base"
        }
        if id.contains("tiny") {
            return "Whisper Tiny"
        }
        if id.contains("turbo") {
            return "Whisper Turbo"
        }
        if id.contains("large-v3") {
            return "Whisper Large"
        }
        return displayName
    }

    var rating: LocalModelRating? {
        LocalModelRating.rating(for: id)
    }

    var installStateLabel: String {
        isInstalled ? "Installiert" : "Nicht installiert"
    }

    static func displayName(for modelName: String) -> String {
        if modelName == ParakeetTranscriber.modelName {
            return "Parakeet v3"
        }
        if modelName.contains("small") {
            return "Whisper Small"
        }
        if modelName.contains("base") {
            return "Whisper Base"
        }
        if modelName.contains("tiny") {
            return "Whisper Tiny"
        }
        if modelName.contains("turbo") {
            return "Whisper Large v3 Turbo"
        }
        if modelName.contains("large-v3") {
            return "Whisper Large v3"
        }
        return modelName
            .replacingOccurrences(of: "openai_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

/// Relative speed and accuracy (0...1) to compare local models at a glance.
/// Values follow Handy's model catalog (github.com/cjpais/handy, `catalog.json`) and are
/// a rough guide, not a Blitztext benchmark on German audio.
struct LocalModelRating: Equatable {
    let speed: Double
    let accuracy: Double
    let sizeLabel: String
    /// Which languages the model handles; all of them detect the language themselves.
    var languages = "Erkennt die Sprache selbst, rund 100 Sprachen."

    static func rating(for modelName: String) -> LocalModelRating? {
        if modelName == ParakeetTranscriber.modelName {
            // FluidAudio benchmark: German FLEURS 5.9 % WER, ~220x real time on Apple Silicon.
            return LocalModelRating(
                speed: 0.95,
                accuracy: 0.9,
                sizeLabel: "~500 MB",
                languages: "Erkennt die Sprache selbst: Deutsch, Englisch und 23 weitere europäische Sprachen."
            )
        }
        if modelName.contains("turbo") {
            return LocalModelRating(speed: 0.35, accuracy: 0.88, sizeLabel: "632 MB")
        }
        if modelName.contains("large-v3") {
            return LocalModelRating(speed: 0.23, accuracy: 0.89, sizeLabel: "626 MB")
        }
        if modelName.contains("small") {
            return LocalModelRating(speed: 0.78, accuracy: 0.80, sizeLabel: "216 MB")
        }
        if modelName.contains("base") {
            return LocalModelRating(speed: 0.99, accuracy: 0.71, sizeLabel: "~140 MB")
        }
        if modelName.contains("tiny") {
            return LocalModelRating(speed: 1.0, accuracy: 0.61, sizeLabel: "~75 MB")
        }
        return nil
    }
}

enum LocalTranscriptionError: LocalizedError {
    case modelMissing(URL)
    case downloadedModelInvalid(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            return "Lokales Modell fehlt: \(url.path)"
        case .downloadedModelInvalid(let modelName):
            return "Das geladene Modell ist unvollständig: \(modelName)"
        case .noText:
            return "Das lokale Modell hat keinen Text erkannt."
        }
    }
}

actor LocalTranscriptionService {
    static let shared = LocalTranscriptionService()

    static let defaultModelName = "openai_whisper-large-v3-v20240930_626MB"
    static let fastModelName = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let recommendedFastModelName = "openai_whisper-small_216MB"
    static let modelRepo = "argmaxinc/whisperkit-coreml"
    static var supportedModelNames: [String] {
        (ParakeetTranscriber.isSupported ? [ParakeetTranscriber.modelName] : []) + [
            recommendedFastModelName,
            fastModelName,
            defaultModelName
        ]
    }
    static let modelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB"
    )!
    static let fastModelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo_632MB"
    )!
    static let recommendedFastModelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small_216MB"
    )!

    static func modelPageURL(for modelName: String) -> URL {
        switch normalizedModelName(modelName) {
        case ParakeetTranscriber.modelName:
            return ParakeetTranscriber.modelPageURL
        case recommendedFastModelName:
            return recommendedFastModelPageURL
        case fastModelName:
            return fastModelPageURL
        case defaultModelName:
            return modelPageURL
        default:
            return URL(string: "https://huggingface.co/\(modelRepo)/tree/main/\(normalizedModelName(modelName))")!
        }
    }

    private var whisperKit: WhisperKit?
    private var pipelineTask: Task<WhisperKit, Error>?
    private var pipelineTaskModelName: String?
    private var loadedModelName: String?

    static var isModelInstalled: Bool {
        isModelInstalled(defaultModelName)
    }

    static func modelURL(named modelName: String) -> URL {
        if normalizedModelName(modelName) == ParakeetTranscriber.modelName {
            return ParakeetTranscriber.modelsDirectoryURL
        }
        return AppSupportPaths.whisperKitModelsDirectoryURL.appendingPathComponent(normalizedModelName(modelName), isDirectory: true)
    }

    static func isModelInstalled(_ modelName: String) -> Bool {
        if normalizedModelName(modelName) == ParakeetTranscriber.modelName {
            return ParakeetTranscriber.isInstalled
        }
        return isUsableModel(at: modelURL(named: modelName))
    }

    static func normalizedModelName(_ modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? recommendedFastModelName : trimmed
    }

    static func installedModels() -> [LocalTranscriptionModel] {
        let directory = AppSupportPaths.whisperKitModelsDirectoryURL
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let parakeet = ParakeetTranscriber.isInstalled
            ? [LocalTranscriptionModel(id: ParakeetTranscriber.modelName, url: ParakeetTranscriber.modelsDirectoryURL)]
            : []

        return parakeet + urls
            .filter { isUsableModel(at: $0) }
            .map { LocalTranscriptionModel(id: $0.lastPathComponent, url: $0) }
            .sorted { lhs, rhs in
                if lhs.id == recommendedFastModelName { return true }
                if rhs.id == recommendedFastModelName { return false }
                if lhs.id == fastModelName { return true }
                if rhs.id == fastModelName { return false }
                if lhs.id == defaultModelName { return true }
                if rhs.id == defaultModelName { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func modelOptions() -> [LocalTranscriptionModel] {
        var seen = Set<String>()
        let installed = installedModels()
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        let orderedIDs = supportedModelNames + installed.map(\.id)

        return orderedIDs.compactMap { modelName in
            let normalizedName = normalizedModelName(modelName)
            guard seen.insert(normalizedName).inserted else { return nil }

            if let installedModel = installedByID[normalizedName] {
                return installedModel
            }

            return LocalTranscriptionModel(
                id: normalizedName,
                url: modelURL(named: normalizedName),
                isInstalled: false
            )
        }
    }

    static func resolvedModelName(_ preferredModelName: String) -> String {
        let normalizedName = normalizedModelName(preferredModelName)
        if isModelInstalled(normalizedName) {
            return normalizedName
        }

        return installedModels().first?.id ?? normalizedName
    }

    static func shouldAutoSelectRecommendedFastModel(currentModelName: String) -> Bool {
        guard isModelInstalled(recommendedFastModelName) else {
            return false
        }

        return currentModelName == defaultModelName || currentModelName == fastModelName
    }

    func prepare(modelName: String) async throws {
        if Self.resolvedModelName(modelName) == ParakeetTranscriber.modelName {
            try await ParakeetTranscriber.shared.prepare()
            return
        }
        _ = try await pipeline(modelName: modelName)
    }

    func downloadAndInstall(
        modelName: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let normalizedName = Self.normalizedModelName(modelName)
        if normalizedName == ParakeetTranscriber.modelName {
            try await ParakeetTranscriber.shared.download(progressHandler: progressHandler)
            guard ParakeetTranscriber.isInstalled else {
                throw LocalTranscriptionError.downloadedModelInvalid(normalizedName)
            }
            return ParakeetTranscriber.modelsDirectoryURL
        }
        let destinationURL = Self.modelURL(named: normalizedName)

        if Self.isUsableModel(at: destinationURL) {
            progressHandler(1)
            return destinationURL
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: AppSupportPaths.whisperKitModelsDirectoryURL,
            withIntermediateDirectories: true
        )

        let downloadRoot = AppSupportPaths.localModelsDirectoryURL
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: downloadRoot, withIntermediateDirectories: true)

        do {
            let downloadedURL = try await WhisperKit.download(
                variant: normalizedName,
                downloadBase: downloadRoot,
                from: Self.modelRepo
            ) { progress in
                let fraction = progress.fractionCompleted
                progressHandler(fraction.isFinite ? fraction : 0)
            }

            guard Self.isUsableModel(at: downloadedURL) else {
                throw LocalTranscriptionError.downloadedModelInvalid(normalizedName)
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: downloadedURL, to: destinationURL)
            try? fileManager.removeItem(at: downloadRoot)

            if loadedModelName == normalizedName {
                whisperKit = nil
                loadedModelName = nil
            }

            progressHandler(1)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: downloadRoot)
            throw error
        }
    }

    func transcribe(audioURL: URL, language: String, modelName: String) async throws -> String {
        let resolvedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)

        let text: String
        if Self.resolvedModelName(modelName) == ParakeetTranscriber.modelName {
            let raw = try await ParakeetTranscriber.shared.transcribe(audioURL: audioURL, language: resolvedLanguage)
            text = HallucinationFilter.removingTrailingCredits(raw)
        } else {
            let pipeline = try await pipeline(modelName: modelName)
            text = try await WhisperDictation.transcribe(pipeline, audioPath: audioURL.path)
        }

        guard !text.isEmpty else {
            throw LocalTranscriptionError.noText
        }
        return text
    }

    /// True once the model is loaded and compiled for this Mac, so a transcription
    /// starts right away.
    func isReady(modelName: String) async -> Bool {
        let resolvedModelName = Self.resolvedModelName(modelName)
        if resolvedModelName == ParakeetTranscriber.modelName {
            return await ParakeetTranscriber.shared.isReady
        }
        return whisperKit != nil && loadedModelName == resolvedModelName
    }

    /// Transcribes and calls `onSlowPreparation` once if the model is still not ready
    /// after `delay`. After a macOS update Core ML recompiles every model for the
    /// Neural Engine, which can take minutes; without a hint the app looks stuck.
    static func transcribe(
        audioURL: URL,
        language: String,
        modelName: String,
        slowPreparationAfter delay: Duration = .seconds(8),
        onSlowPreparation: @escaping @MainActor () -> Void
    ) async throws -> String {
        let watcher = Task {
            try await Task.sleep(for: delay)
            if await !shared.isReady(modelName: modelName) {
                await onSlowPreparation()
            }
        }
        defer { watcher.cancel() }
        return try await shared.transcribe(audioURL: audioURL, language: language, modelName: modelName)
    }

    static let slowPreparationMessage = "Sprachmodell wird vorbereitet. Nach einem macOS-Update dauert das einmalig einige Minuten, bitte Blitztext nicht beenden."

    private func pipeline(modelName: String) async throws -> WhisperKit {
        let resolvedModelName = Self.resolvedModelName(modelName)
        if let whisperKit, loadedModelName == resolvedModelName {
            return whisperKit
        }
        if let pipelineTask, pipelineTaskModelName == resolvedModelName {
            return try await pipelineTask.value
        }

        let url = Self.modelURL(named: resolvedModelName)
        guard Self.isUsableModel(at: url) else {
            throw LocalTranscriptionError.modelMissing(url)
        }

        try FileManager.default.createDirectory(
            at: AppSupportPaths.whisperKitTokenizersDirectoryURL,
            withIntermediateDirectories: true
        )
        // Reentrancy guard: a second dictation during a slow load waits for this one
        // instead of starting another full load and compile.
        let task = Task<WhisperKit, Error> {
            try await WhisperKit(
                modelFolder: url.path,
                tokenizerFolder: AppSupportPaths.whisperKitTokenizersDirectoryURL,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
        }
        pipelineTask = task
        pipelineTaskModelName = resolvedModelName
        defer {
            if pipelineTaskModelName == resolvedModelName {
                pipelineTask = nil
                pipelineTaskModelName = nil
            }
        }
        let loaded = try await task.value
        whisperKit = loaded
        loadedModelName = resolvedModelName
        return loaded
    }

    private static func isUsableModel(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlmodelc").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("MelSpectrogram.mlmodelc").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("TextDecoder.mlmodelc").path)
    }
}
