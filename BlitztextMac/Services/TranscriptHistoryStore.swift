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

/// An own mode's entry reads as Blitztext+ in builds without own modes, instead of making them
/// drop the whole history (`StoredMode`).
extension TranscriptHistoryEntry {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, workflow, customModeID, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            workflow: try StoredMode.decode(from: container, mode: .workflow, customID: .customModeID),
            text: try container.decode(String.self, forKey: .text)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try StoredMode.encode(workflow, standIn: .textImprover, into: &container, mode: .workflow, customID: .customModeID)
        try container.encode(text, forKey: .text)
    }
}

/// Recent results, stored only on this Mac and encrypted with the Keychain file key.
@Observable
@MainActor
final class TranscriptHistoryStore {
    static let maxEntries = 30

    private(set) var entries: [TranscriptHistoryEntry] = []
    private var retention: HistoryRetention
    private let isPersistent: Bool

    /// - Parameter persistent: False for snapshot and check runs: no file, no Keychain.
    init(retention: HistoryRetention, persistent: Bool = true) {
        self.retention = retention
        isPersistent = persistent
        // The save in `prune` also moves a file with a machine-derived key to the Keychain key.
        entries = persistent ? Self.load() : Self.toolRunEntries
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
        guard isPersistent else { return }
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
        guard isPersistent else { return }
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
        guard let encrypted = try? Data(contentsOf: AppSupportPaths.historyURL) else { return [] }
        guard let data = KeychainService.openData(encrypted),
              let entries = try? JSONDecoder().decode([TranscriptHistoryEntry].self, from: data) else {
            // The save on launch would delete a file this build cannot read (Keychain locked,
            // another Mac's key): keep it aside instead, like the meetings.
            moveUnreadableFileAside()
            return []
        }
        return entries
    }

    private static func moveUnreadableFileAside() {
        let url = AppSupportPaths.historyURL
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".unreadable-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: aside)
    }

    /// Samples for snapshot runs, nothing for other tool runs.
    private static var toolRunEntries: [TranscriptHistoryEntry] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "BlitztextSnapshotDir") != nil {
            return [
                TranscriptHistoryEntry(id: UUID(), createdAt: Date().addingTimeInterval(-600), workflow: .textImprover, text: "Kurze Info f\u{00FC}rs Team: Das Kick-off verschiebt sich auf Donnerstag, 10 Uhr. Agenda und Unterlagen kommen morgen."),
                // An own mode, as in `MacSnapshots.sampleCustomModes`.
                TranscriptHistoryEntry(id: UUID(), createdAt: Date().addingTimeInterval(-1800), workflow: .custom("custom-snapshot-concept"), text: "Workshop-Konzept\n- Ziel: Team arbeitet sicher mit KI-Werkzeugen\n- Idee: halber Tag, drei echte Aufgaben aus dem Alltag\n- N\u{00E4}chste Schritte: Raum buchen, Einladung bis Freitag"),
                TranscriptHistoryEntry(id: UUID(), createdAt: Date().addingTimeInterval(-3600), workflow: .tapTalk, text: "Einkaufsliste f\u{00FC}r das Wochenende: Brot, Tomaten, Kaffee."),
            ]
        }
        #endif
        return []
    }
}
