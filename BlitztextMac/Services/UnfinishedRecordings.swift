import AVFoundation
import Foundation

/// Dictations whose transcription failed (public issue #45). While a dictation is transcribed,
/// a sealed copy of its recording waits here, so an error or a crash does not lose what was
/// said. Once there is text it is deleted, as before. A failed one stays until it is
/// transcribed again, deleted by hand, or for 24 hours at most.
///
/// The copy is encrypted (public issue #54): a recording of the user's voice must not lie
/// around in the clear, also with history off. Never with a Keychain question of its own: a
/// dictation must not be what first asks the Keychain in a session (a prompt mid-dictation, or
/// in a session started by the Jamf restart). So the file key when the session already has
/// it (history or meetings opened it), otherwise the machine key
/// (`KeychainService.sealDataWithoutAsking`).
/// The plain recording stays in the temporary folder only while it is transcribed; a crash
/// leaves it there and the next launch deletes it (`AudioRecorder.removeLeftoverRecordings`).
enum UnfinishedRecordings {
    struct Item: Identifiable, Equatable {
        /// The sealed file.
        let url: URL
        let recordedAt: Date
        let seconds: TimeInterval
        var id: URL { url }
    }

    static let keptFor: TimeInterval = 24 * 60 * 60
    static let notice = "Die Aufnahme ist gesichert, im Men\u{00FC} l\u{00E4}sst sie sich neu transkribieren."
    static let cannotOpenMessage = "Die gesicherte Aufnahme l\u{00E4}sst sich gerade nicht \u{00F6}ffnen, der Schl\u{00FC}sselbund gibt den Schl\u{00FC}ssel nicht frei. Sp\u{00E4}ter nochmal versuchen."

    static let sealedExtension = "sealed"

    static var directoryURL: URL {
        AppSupportPaths.appSupportDirectoryURL.appendingPathComponent("Unfinished", isDirectory: true)
    }

    /// For `DictationRun`.
    @MainActor static let safekeeping = DictationRun.Safekeeping(
        secure: { secure($0) }, release: release, sweep: { removeExpired() }
    )

    /// Kept copies of recordings a dictation is transcribing right now; they are not
    /// unfinished (yet).
    @MainActor private static var inProgress: Set<URL> = []

    /// Writes a sealed copy of a finished recording before it is transcribed; the recording
    /// itself stays where it is for the model. Nil when that failed; the dictation then goes
    /// on without a copy.
    @MainActor static func secure(_ recording: URL, seal: (Data) throws -> Data = KeychainService.sealDataWithoutAsking) -> URL? {
        let seconds = (try? AVAudioFile(forReading: recording)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        guard let target = writeSealed(contentsOf: recording, seconds: seconds, seal: seal) else { return nil }
        inProgress.insert(target)
        return target
    }

    @MainActor static func release(_ kept: URL) {
        inProgress.remove(kept)
    }

    /// The unfinished recordings, newest first. Deletes those older than `keptFor` and seals
    /// plain ones that versions 1.16.2 to 1.17 kept.
    @MainActor static func current(now: Date = Date()) -> [Item] {
        sealPlainRecordings()
        return files()
            .filter { $0.pathExtension == sealedExtension && !inProgress.contains($0) }
            .compactMap { url -> Item? in
                let recordedAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
                guard !isExpired(recordedAt, now: now) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return Item(url: url, recordedAt: recordedAt, seconds: seconds(fromName: url) ?? 0)
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Posted when the sweep deleted a recording, so an open menu drops its row.
    static let didChange = Notification.Name("app.blitztext.unfinished-recordings-changed")

    /// Deletes recordings older than `keptFor`, without reading them.
    @MainActor static func removeExpired(now: Date = Date()) {
        var removed = false
        for url in files() where [sealedExtension, "wav"].contains(url.pathExtension) && !inProgress.contains(url) {
            let recordedAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            if isExpired(recordedAt, now: now), (try? FileManager.default.removeItem(at: url)) != nil {
                removed = true
            }
        }
        if removed {
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func isExpired(_ recordedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(recordedAt) >= keptFor
    }

    static func delete(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
    }

    /// A plain copy in the temporary folder for transcribing it again; the caller deletes it,
    /// and a crash leaves nothing behind for long (`AudioRecorder.removeLeftoverRecordings`
    /// knows the prefix). Nil when the key is not available.
    ///
    /// Tries the keys this session has first. Only a copy sealed with the file key in an
    /// earlier session needs the Keychain: then `KeychainService.openData`, on the user's
    /// click, with the rules the history follows (UI only on the first question of a normal
    /// launch, never after the Jamf restart, a new key never with UI).
    static func openedCopy(
        of item: Item,
        open: (Data) -> Data? = KeychainService.openDataWithoutAsking,
        openAsking: (Data) -> Data? = KeychainService.openData
    ) -> URL? {
        guard let sealed = try? Data(contentsOf: item.url), let audio = open(sealed) ?? openAsking(sealed) else { return nil }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-import-kept-\(UUID().uuidString).wav")
        guard FileManager.default.createFile(atPath: copy.path, contents: audio, attributes: [.posixPermissions: 0o600]) else {
            return nil
        }
        return copy
    }

    /// "Diktat von 10:31 Uhr, 2 Min.", always ending with a period.
    static func label(for item: Item) -> String {
        let time = item.recordedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_DE")))
        let length = item.seconds < 60 ? "\(max(1, Int(item.seconds.rounded()))) Sek." : "\(Int((item.seconds / 60).rounded())) Min."
        return "Diktat von \(time) Uhr, \(length)"
    }

    // MARK: Files

    /// The length goes into the name, so the menu can show it without opening the file:
    /// "dictation-<id>-<tenths of a second>.sealed".
    static func fileName(seconds: TimeInterval) -> String {
        "dictation-\(UUID().uuidString)-\(max(0, Int((seconds * 10).rounded()))).\(sealedExtension)"
    }

    static func seconds(fromName url: URL) -> TimeInterval? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let tenths = name.split(separator: "-").last.flatMap({ Int($0) }) else { return nil }
        return Double(tenths) / 10
    }

    private static func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.creationDateKey])) ?? []
    }

    /// Tests pass their own folder, never Application Support.
    static func writeSealed(
        contentsOf recording: URL, seconds: TimeInterval, seal: (Data) throws -> Data,
        recordedAt: Date? = nil, in directory: URL = directoryURL
    ) -> URL? {
        var folder = directory
        let target = folder.appendingPathComponent(fileName(seconds: seconds))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Encrypted, but still the user's voice: keep it out of backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            let sealed = try seal(Data(contentsOf: recording))
            guard FileManager.default.createFile(atPath: target.path, contents: sealed, attributes: [.posixPermissions: 0o600]) else {
                return nil
            }
            // A plain recording sealed later keeps its age, so it still goes after 24 hours.
            if let recordedAt {
                try? FileManager.default.setAttributes([.creationDate: recordedAt], ofItemAtPath: target.path)
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return target
    }

    /// Versions 1.16.2 to 1.17 kept the recording as a plain WAV. Sealed like a new one,
    /// without asking the Keychain.
    @MainActor private static func sealPlainRecordings() {
        for url in files() where url.pathExtension == "wav" {
            let recordedAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            if writeSealed(contentsOf: url, seconds: seconds, seal: KeychainService.sealDataWithoutAsking, recordedAt: recordedAt) != nil {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
