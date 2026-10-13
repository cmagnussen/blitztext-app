import Foundation
import Observation

enum HistoryRetention: String, Codable, CaseIterable, Identifiable {
    case off
    case day
    case week

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Aus"
        case .day: return "24 Std."
        case .week: return "7 Tage"
        }
    }

    var maxAge: TimeInterval? {
        switch self {
        case .off: return nil
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        }
    }
}

struct TranscriptHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let workflow: WorkflowType
    let text: String
}

/// Recent results, stored only on this Mac and encrypted with the device-bound key.
@Observable
@MainActor
final class TranscriptHistoryStore {
    static let maxEntries = 30

    private(set) var entries: [TranscriptHistoryEntry] = []
    private var retention: HistoryRetention

    init(retention: HistoryRetention) {
        self.retention = retention
        entries = Self.load()
        prune()
    }

    func add(_ text: String, workflow: WorkflowType) {
        guard retention != .off else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries.insert(
            TranscriptHistoryEntry(id: UUID(), createdAt: Date(), workflow: workflow, text: trimmed),
            at: 0
        )
        prune()
    }

    func remove(_ entry: TranscriptHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: AppSupportPaths.historyURL)
    }

    func updateRetention(_ newRetention: HistoryRetention) {
        retention = newRetention
        prune()
    }

    /// Drops expired entries. Called on launch, on every change and when the popover opens.
    func prune(now: Date = Date()) {
        guard let maxAge = retention.maxAge else {
            clear()
            return
        }

        let pruned = Array(entries.filter { now.timeIntervalSince($0.createdAt) < maxAge }.prefix(Self.maxEntries))
        if pruned != entries {
            entries = pruned
        }
        save()
    }

    private func save() {
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: AppSupportPaths.historyURL)
            return
        }

        do {
            try AppSupportPaths.ensureAppSupportDirectoryExists()
            let data = try JSONEncoder().encode(entries)
            try KeychainService.sealData(data).write(to: AppSupportPaths.historyURL, options: .atomic)
        } catch {
            // History is a convenience; a failed write must never block pasting.
        }
    }

    private static func load() -> [TranscriptHistoryEntry] {
        guard let encrypted = try? Data(contentsOf: AppSupportPaths.historyURL),
              let data = KeychainService.openData(encrypted),
              let entries = try? JSONDecoder().decode([TranscriptHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
