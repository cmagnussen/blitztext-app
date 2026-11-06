import Foundation
import Observation

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

    /// Gives one part to another person (`[MeetingTurn].reassign`). A name nobody speaks under
    /// any more goes with the last part, so "Neue Person", which may get that number again,
    /// starts without a stranger's name.
    @discardableResult
    mutating func reassign(turn id: UUID, to speaker: Int) -> Bool {
        guard turns.reassign(turn: id, to: speaker) else { return false }
        let speaking = Set(turns.map(\.speaker))
        speakerNames = speakerNames.filter { speaking.contains($0.key) }
        return true
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
/// encrypted like the history, with the Keychain file key (`KeychainService`,
/// `SealedStoreFiles`).
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

    /// Keeps a recording out of Time Machine and iCloud backups: it is unencrypted and goes
    /// once the meeting is evaluated, a copy in a backup would not. Only the audio files; the
    /// encrypted meetings in the same folder stay in the backup.
    nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    #if os(macOS)
    private let files: SealedStoreFiles
    /// The stored meetings did not open because the Keychain did not give the file key: the
    /// file stays untouched, and the meetings of this session wait in the side file until the
    /// key is back (`SealedStoreFiles`). They are on disk there, so their audio may go.
    private var isLockedOut = false

    nonisolated static var files: SealedStoreFiles {
        .keychain(
            main: directoryURL.appendingPathComponent(".meetings"),
            pending: directoryURL.appendingPathComponent(".meetings-pending")
        )
    }

    /// - Parameter files: Where the meetings live; tests pass a folder of their own.
    init(persistent: Bool = true, files: SealedStoreFiles = MeetingStore.files) {
        isPersistent = persistent
        self.files = files
        guard persistent else { return }
        switch files.readMain([MeetingRecord].self) {
        case .value(let stored):
            meetings = stored
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
        // Recorded while an earlier session could not open the meetings.
        if let pending = files.readPending([MeetingRecord].self) {
            meetings = LockedOutMerge.merged(meetings, pending, date: \.createdAt)
            save()
        }
        migrateSpeakerLabels()
        // Meetings saved with a machine-derived key move to the Keychain key now, not only
        // with the next change.
        if !isLockedOut {
            files.migrateLegacy(files.mainURL)
        }
    }
    #else
    nonisolated private static var fileURL: URL { directoryURL.appendingPathComponent("meetings.json") }

    init(persistent: Bool = true) {
        isPersistent = persistent
        guard persistent, FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        if let data = try? Data(contentsOf: Self.fileURL),
           let meetings = try? JSONDecoder().decode([MeetingRecord].self, from: data) {
            self.meetings = meetings
        } else {
            // Never overwrite meetings that only this build cannot read (a later format):
            // keep the file aside so they can still be recovered.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = Self.fileURL.deletingLastPathComponent()
                .appendingPathComponent(Self.fileURL.lastPathComponent + ".unreadable-\(stamp)")
            try? FileManager.default.moveItem(at: Self.fileURL, to: aside)
        }
        migrateSpeakerLabels()
    }
    #endif

    #if DEBUG
    /// The stored meetings for debug checks: reads only, never moves an unreadable file aside.
    static func readWithoutRepair() -> [MeetingRecord]? {
        #if os(macOS)
        if case .value(let stored) = files.readMain([MeetingRecord].self) { return stored }
        return nil
        #else
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([MeetingRecord].self, from: data)
        #endif
    }
    #endif

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
        #if os(macOS)
        if isLockedOut {
            unlockIfKeyIsBack()
        }
        do {
            if isLockedOut {
                try files.writePending(meetings)
            } else {
                try files.writeMain(meetings)
                files.removePending()
            }
            return true
        } catch {
            return false
        }
        #else
        do {
            try FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(meetings)
            // "Until first unlock": processing may finish while the phone is locked.
            try data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
        #endif
    }

    #if os(macOS)
    /// The Keychain gives the key again (asked again at most every few minutes, without UI):
    /// read the main file and take over the meetings that waited in the side file.
    private func unlockIfKeyIsBack() {
        guard !files.keyIsUnavailable() else { return }
        switch files.readMain([MeetingRecord].self) {
        case .value(let stored):
            meetings = LockedOutMerge.merged(stored, meetings, date: \.createdAt)
        case .missing:
            break
        case .unreadable:
            files.moveMainAside()
        }
        isLockedOut = false
    }
    #endif
}
