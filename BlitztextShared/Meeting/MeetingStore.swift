import Foundation
import Observation

struct MeetingTurn: Codable, Equatable, Identifiable {
    var id = UUID()
    let speaker: Int
    let start: TimeInterval
    let text: String
}

struct MeetingRecord: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        /// Audio is kept until processing succeeds, so an interrupted meeting can be retried.
        case pending
        case done
    }

    let id: UUID
    let createdAt: Date
    var title: String
    var duration: TimeInterval
    var status: Status
    var turns: [MeetingTurn] = []
    var speakerNames: [Int: String] = [:]
    var summary: String?
    /// Why the summary is missing, e.g. no language model available.
    var summaryNote: String?

    /// "Meeting am 17. Okt. 2026, 11:58": German like the rest of the app, whatever the
    /// system language.
    static func title(startedAt date: Date) -> String {
        "Meeting am " + date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "de_DE")))
    }

    /// Speaker 0 is the microphone in an online meeting, the person at this Mac.
    func name(for speaker: Int) -> String {
        let custom = speakerNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard custom.isEmpty else { return custom }
        return speaker == 0 ? "Ich" : "Person \(speaker)"
    }

    var speakers: [Int] {
        Array(Set(turns.map(\.speaker))).sorted()
    }

    /// "Name: text" per turn, the form used for the summary and for copying.
    var transcriptText: String {
        transcriptText(ownName: nil)
    }

    /// For a language model: the person at this Mac ("Ich") appears as `ownName` unless
    /// renamed, so the tasks they take on are assigned to them and not to a stranger.
    func transcriptText(ownName: String?) -> String {
        turns.map { turn in
            let renamed = !(speakerNames[turn.speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            let name = turn.speaker == 0 && !renamed ? (ownName ?? name(for: 0)) : name(for: turn.speaker)
            return "\(name): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    /// Title and transcript by person, e.g. to continue in another AI app.
    var transcriptShareText: String {
        title + "\n\n" + transcriptText
    }

    var shareText: String {
        var parts = [title]
        if let summary { parts.append(summary) }
        parts.append("Transkript\n\n" + transcriptText)
        return parts.joined(separator: "\n\n")
    }

    var audioURL: URL {
        MeetingStore.directoryURL.appendingPathComponent("\(id.uuidString).wav")
    }

    /// What the Mac played during an online meeting, i.e. the other side.
    var systemAudioURL: URL {
        MeetingStore.directoryURL.appendingPathComponent("\(id.uuidString)-system.caf")
    }
}

/// Meetings stay on the device: on the iPhone protected by iOS Data Protection, on the Mac
/// encrypted like the history, with a key derived from this Mac (`KeychainService`).
@Observable
@MainActor
final class MeetingStore {
    private(set) var meetings: [MeetingRecord] = []
    /// False for previews and snapshots: nothing is read from or written to disk.
    private let isPersistent: Bool

    nonisolated static var directoryURL: URL {
        #if os(macOS)
        AppSupportPaths.appSupportDirectoryURL.appendingPathComponent("Meetings", isDirectory: true)
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Blitztext/Meetings", isDirectory: true)
        #endif
    }

    #if os(macOS)
    nonisolated private static var fileURL: URL { directoryURL.appendingPathComponent(".meetings") }
    #else
    nonisolated private static var fileURL: URL { directoryURL.appendingPathComponent("meetings.json") }
    #endif

    init(persistent: Bool = true) {
        isPersistent = persistent
        guard persistent, FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        if let data = Self.readStoredData(),
           let meetings = try? JSONDecoder().decode([MeetingRecord].self, from: data) {
            self.meetings = meetings
        } else {
            // Never overwrite meetings that only this build cannot read (another Mac's key,
            // a later format): keep the file aside so they can still be recovered.
            Self.moveUnreadableFileAside()
        }
        migrateSpeakerLabels()
    }

    #if DEBUG
    /// The stored meetings for debug checks: reads only, never moves an unreadable file aside.
    static func readWithoutRepair() -> [MeetingRecord]? {
        guard let data = readStoredData() else { return nil }
        return try? JSONDecoder().decode([MeetingRecord].self, from: data)
    }
    #endif

    private static func moveUnreadableFileAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".unreadable-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }

    /// Summaries written before speakers became "Person N" still name them "Sprecher N".
    private func migrateSpeakerLabels() {
        var changed = false
        for index in meetings.indices {
            guard let summary = meetings[index].summary, summary.contains("Sprecher ") else { continue }
            meetings[index].summary = summary.replacingOccurrences(
                of: #"Sprecher (\d+)"#, with: "Person $1", options: .regularExpression
            )
            changed = true
        }
        if changed { save() }
    }

    func meeting(id: UUID) -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    /// Returns whether the meetings reached the disk, so audio is only deleted once its
    /// transcript is safe.
    @discardableResult
    func upsert(_ record: MeetingRecord) -> Bool {
        if let index = meetings.firstIndex(where: { $0.id == record.id }) {
            meetings[index] = record
        } else {
            meetings.insert(record, at: 0)
        }
        return save()
    }

    /// Sets only the summary of a meeting that still exists, so a delete or a rename made
    /// while the summary was being written is kept.
    func setSummary(_ summary: String?, note: String?, for id: UUID) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].summary = summary
        meetings[index].summaryNote = note
        save()
    }

    func delete(id: UUID) {
        if let record = meeting(id: id) {
            try? FileManager.default.removeItem(at: record.audioURL)
            try? FileManager.default.removeItem(at: record.systemAudioURL)
        }
        meetings.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    private func save() -> Bool {
        guard isPersistent else { return true }
        do {
            try FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(meetings)
            #if os(macOS)
            try KeychainService.sealData(data).write(to: Self.fileURL, options: .atomic)
            #else
            // "Until first unlock": processing may finish while the phone is locked.
            try data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
            return true
        } catch {
            return false
        }
    }

    private static func readStoredData() -> Data? {
        guard let stored = try? Data(contentsOf: fileURL) else { return nil }
        #if os(macOS)
        return KeychainService.openData(stored)
        #else
        return stored
        #endif
    }
}
