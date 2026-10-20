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

    var rating: LocalModelRating? {
        LocalModelRating.rating(for: id)
    }

    /// The same entry in the menu bar and in the settings.
    var pickerLabel: String {
        isInstalled ? displayName : "\(displayName) (nicht installiert)"
    }

    static func displayName(for modelName: String) -> String {
        if modelName == ParakeetTranscriber.modelName {
            return ParakeetTranscriber.displayName
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
        // OpenAI's large-v3-turbo, released 2024-09-30; Argmax ships it in two builds.
        if modelName.contains("large-v3-v20240930") {
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

/// Relative speed and accuracy (0...1) to compare local models at a glance, derived from
/// published benchmarks (October 2026), not measured by Blitztext.
///
/// Accuracy: `1 - WER / 25` with the German FLEURS word error rate, so 25 % WER is an empty
/// bar. Parakeet Ultra 4.9 % and v3 5.8 % (Blitztext's run of FluidAudio's FLEURS benchmark,
/// 350 German samples on Apple M5; FluidAudio publishes 5.9 % for v3); Whisper
/// large-v3-turbo 5.8 % (OpenAI, whisper discussion #2363) plus about 1 point for the
/// 4-bit compression (Argmax, German Common Voice 17: 12.26 % to 13.21 %); Whisper small
/// 10.2 % (Whisper paper, table 13; no figure for the compressed file).
///
/// Speed: `log10(x) / log10(200)` with x times real time on an M4 Pro, so 1x is an empty
/// bar and 200x a full one. Parakeet v3 155.6x (FluidAudio, LibriSpeech test-clean), Ultra
/// about 11 % slower in the same run as above, so about 140x; WhisperKit
/// 27.3x small, 15.8x turbo_632MB, 10.5x 626MB (Argmax whisperkit-benchmarks). Logarithmic,
/// because a dictation of a few seconds feels instant at 100x and still quick at 10x.
///
/// Both Whisper large entries are OpenAI's large-v3-turbo (v20240930) with the same 4-bit
/// weights; the `_turbo` file adds Argmax's streaming optimizations and runs about 1.5x faster.
struct LocalModelRating: Equatable {
    let speed: Double
    let accuracy: Double
    let sizeLabel: String
    /// Which languages the model handles; all of them detect the language themselves.
    var languages = "Erkennt die Sprache selbst, rund 100 Sprachen."

    static func rating(for modelName: String) -> LocalModelRating? {
        if modelName == ParakeetTranscriber.modelName {
            let legacy = ParakeetTranscriber.usesLegacyModel
            return LocalModelRating(
                speed: legacy ? 0.95 : 0.93,
                accuracy: legacy ? 0.77 : 0.80,
                sizeLabel: legacy ? "~460 MB" : "~630 MB",
                languages: "Erkennt die Sprache selbst: Deutsch, Englisch und 23 weitere europäische Sprachen."
            )
        }
        if modelName.contains("large-v3-v20240930_turbo") {
            return LocalModelRating(speed: 0.52, accuracy: 0.73, sizeLabel: "632 MB")
        }
        if modelName.contains("large-v3-v20240930") {
            return LocalModelRating(speed: 0.44, accuracy: 0.73, sizeLabel: "626 MB")
        }
        if modelName.contains("small") {
            return LocalModelRating(speed: 0.62, accuracy: 0.59, sizeLabel: "216 MB")
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
    /// What a new Mac starts with: Parakeet Ultra on Apple Silicon (faster and more accurate),
    /// Whisper Small on Intel.
    static var initialModelName: String {
        ParakeetTranscriber.isSupported ? ParakeetTranscriber.modelName : recommendedFastModelName
    }
    static let modelRepo = "argmaxinc/whisperkit-coreml"
    /// Both builds of Whisper large-v3-turbo carry the same 4-bit weights, so the app lists
    /// them as one model. The streaming build runs about 1.5x faster, but Argmax does not
    /// support it on M1, so M1 and Intel Macs get the plain build.
    static let turboModelNames = [fastModelName, defaultModelName]

    static var preferredTurboModelName: String {
        hasFastTurboSupport ? fastModelName : defaultModelName
    }

    private static let hasFastTurboSupport: Bool = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return false }
        let brand = String(cString: bytes)
        return brand.hasPrefix("Apple M") && !brand.hasPrefix("Apple M1")
    }()

    /// The one turbo entry: the build already selected and on disk, else a downloaded one,
    /// else the build for this Mac.
    static func turboModelName(selected: String) -> String {
        if turboModelNames.contains(selected), isModelInstalled(selected) {
            return selected
        }
        if isModelInstalled(preferredTurboModelName) {
            return preferredTurboModelName
        }
        return turboModelNames.first(where: { isModelInstalled($0) }) ?? preferredTurboModelName
    }

    static func supportedModelNames(selected: String) -> [String] {
        (ParakeetTranscriber.isSupported ? [ParakeetTranscriber.modelName] : []) + [
            recommendedFastModelName,
            turboModelName(selected: selected)
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
        return trimmed.isEmpty ? initialModelName : trimmed
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

    static func modelOptions(selected: String) -> [LocalTranscriptionModel] {
        var seen = Set<String>()
        let installed = installedModels()
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        let orderedIDs = supportedModelNames(selected: normalizedModelName(selected))
            + installed.map(\.id).filter { !turboModelNames.contains($0) }

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
        let padded = AudioPadding.paddedCopy(of: audioURL)
        defer { if let padded { try? FileManager.default.removeItem(at: padded) } }
        let audioURL = padded ?? audioURL

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
