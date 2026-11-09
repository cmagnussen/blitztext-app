import FluidAudio
import Foundation

/// "Who spoke when" for meeting recordings, on device via FluidAudio's offline
/// pipeline (pyannote segmentation + WeSpeaker embeddings + VBx clustering).
/// The models download on first use.
actor SpeakerDiarizer {
    static let shared = SpeakerDiarizer()

    static var modelsDirectoryURL: URL {
        #if os(macOS)
        AppSupportPaths.localModelsDirectoryURL.appendingPathComponent("diarizer", isDirectory: true)
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Blitztext/Models/diarizer", isDirectory: true)
        #endif
    }

    private var manager: OfflineDiarizerManager?
    /// The load in flight. Actor methods are reentrant at `await`: the early load at the start
    /// of a meeting and the evaluation of a short one otherwise both downloaded the models into
    /// the same folder.
    private var loadTask: Task<Void, Error>?

    /// Loads the models, downloading them the first time.
    func prepare() async throws {
        guard manager == nil else { return }
        if let loadTask {
            return try await loadTask.value
        }
        // Runs on this actor and sets `manager` itself, before any waiting caller resumes.
        let task = Task {
            try FileManager.default.createDirectory(at: Self.modelsDirectoryURL, withIntermediateDirectories: true)
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels(directory: Self.modelsDirectoryURL)
            var url = Self.modelsDirectoryURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            self.manager = manager
        }
        loadTask = task
        // Also after a failure, so the next meeting tries again.
        defer { loadTask = nil }
        try await task.value
    }

    /// Speaker turns in time order. Consecutive segments of the same speaker are
    /// merged, and speakers are numbered by first appearance (1, 2, ...).
    func turns(in audioURL: URL) async throws -> [SpeakerTurn] {
        try await prepare()
        guard let manager else { return [] }
        let result = try await manager.process(audioURL)

        var numbers: [String: Int] = [:]
        var turns: [SpeakerTurn] = []
        for segment in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
            let number = numbers[segment.speakerId] ?? {
                let next = numbers.count + 1
                numbers[segment.speakerId] = next
                return next
            }()
            let start = TimeInterval(segment.startTimeSeconds)
            let end = TimeInterval(segment.endTimeSeconds)
            if let last = turns.last, last.speaker == number, start - last.end < 1.0 {
                turns[turns.count - 1] = SpeakerTurn(speaker: number, start: last.start, end: end)
            } else {
                turns.append(SpeakerTurn(speaker: number, start: start, end: end))
            }
        }
        return turns.filter { $0.end - $0.start >= 0.4 }
    }
}
