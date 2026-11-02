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

/// Recent results, stored only on this Mac and encrypted with the Keychain file key
/// (`SealedStoreFiles`).
@Observable
@MainActor
final class TranscriptHistoryStore {
    static let maxEntries = 30

    private(set) var entries: [TranscriptHistoryEntry] = []
    private var retention: HistoryRetention
    private let isPersistent: Bool
    private let files: SealedStoreFiles
    /// The stored history did not open because the Keychain did not give the file key: the
    /// file stays untouched, and what this session records waits in the side file until the
    /// key is back (`SealedStoreFiles`).
    private var isLockedOut = false

    /// - Parameters:
    ///   - persistent: False for snapshot and check runs: no file, no Keychain.
    ///   - files: Where the history lives; tests pass a folder of their own.
    init(retention: HistoryRetention, persistent: Bool = true, files: SealedStoreFiles = .history) {
        self.retention = retention
        isPersistent = persistent
        self.files = files
        if persistent {
            switch files.readMain([TranscriptHistoryEntry].self) {
            case .value(let stored):
                entries = stored
            case .missing:
                break
            case .unreadable:
                // Most likely sealed with the Keychain key the Keychain did not give: leave the
                // file. Another Mac's key or a later format: keep it aside, never overwrite it.
                if files.keyIsUnavailable() {
                    isLockedOut = true
                } else {
                    files.moveMainAside()
                }
            }
            // Recorded while an earlier session could not open the history.
            if let pending = files.readPending([TranscriptHistoryEntry].self) {
                entries = LockedOutMerge.merged(entries, pending, date: \.createdAt)
            }
        } else {
            entries = Self.toolRunEntries
        }
        // The save in `prune` also merges the side file and moves a file with a
        // machine-derived key to the Keychain key.
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
        files.removeMain()
        files.removePending()
        isLockedOut = false
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

        entries = pruned(entries, maxAge: maxAge, now: now)
        save(now: now)
    }

    private func pruned(_ entries: [TranscriptHistoryEntry], maxAge: TimeInterval, now: Date) -> [TranscriptHistoryEntry] {
        Array(entries.filter { now.timeIntervalSince($0.createdAt) < maxAge }.prefix(Self.maxEntries))
    }

    private func save(now: Date = Date()) {
        guard isPersistent else { return }
        if isLockedOut {
            unlockIfKeyIsBack(now: now)
        }
        // History is a convenience; a failed write must never block pasting.
        if isLockedOut {
            // Nothing recorded now is lost: it waits in the side file until the key is back.
            if entries.isEmpty { files.removePending() } else { try? files.writePending(entries) }
            return
        }
        guard !entries.isEmpty else {
            files.removeMain()
            files.removePending()
            return
        }
        if (try? files.writeMain(entries)) != nil {
            files.removePending()
        }
    }

    /// The Keychain gives the key again (asked again at most every few minutes, without UI):
    /// read the main file and take over what waited in the side file.
    private func unlockIfKeyIsBack(now: Date) {
        guard !files.keyIsUnavailable() else { return }
        switch files.readMain([TranscriptHistoryEntry].self) {
        case .value(let stored):
            entries = LockedOutMerge.merged(stored, entries, date: \.createdAt)
            if let maxAge = retention.maxAge {
                entries = pruned(entries, maxAge: maxAge, now: now)
            }
        case .missing:
            break
        case .unreadable:
            files.moveMainAside(now: now)
        }
        isLockedOut = false
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
