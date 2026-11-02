import AVFoundation
import Foundation

/// Dictations whose transcription failed (public issue #45). While a dictation is transcribed,
/// its recording waits here instead of the temporary folder, so an error or a crash does not
/// lose what was said. Once there is text it is deleted, as before. A failed one stays until it
/// is transcribed again, deleted by hand, or for 24 hours at most.
enum UnfinishedRecordings {
    struct Item: Identifiable, Equatable {
        let url: URL
        let recordedAt: Date
        let seconds: TimeInterval
        var id: URL { url }
    }

    static let keptFor: TimeInterval = 24 * 60 * 60
    static let notice = "Die Aufnahme ist gesichert, im Men\u{00FC} l\u{00E4}sst sie sich neu transkribieren."

    static var directoryURL: URL {
        AppSupportPaths.appSupportDirectoryURL.appendingPathComponent("Unfinished", isDirectory: true)
    }

    /// For `DictationRun`.
    @MainActor static let safekeeping = DictationRun.Safekeeping(
        secure: secure, release: release, sweep: { removeExpired() }
    )

    /// Recordings a dictation is transcribing right now; they are not unfinished (yet).
    @MainActor private static var inProgress: Set<URL> = []

    /// Moves a finished recording here before it is transcribed. Nil when that failed; the
    /// dictation then goes on with the temporary file.
    @MainActor static func secure(_ recording: URL) -> URL? {
        let folder = directoryURL
        let target = folder.appendingPathComponent("dictation-\(UUID().uuidString).wav")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: recording, to: target)
        } catch {
            return nil
        }
        inProgress.insert(target)
        return target
    }

    @MainActor static func release(_ recording: URL) {
        inProgress.remove(recording)
    }

    /// The unfinished recordings, newest first. Deletes those older than `keptFor`.
    @MainActor static func current(now: Date = Date()) -> [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "wav" && !inProgress.contains($0) }
            .compactMap { url -> Item? in
                let recordedAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
                guard !isExpired(recordedAt, now: now) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
                return Item(url: url, recordedAt: recordedAt, seconds: seconds)
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Posted when the sweep deleted a recording, so an open menu drops its row.
    static let didChange = Notification.Name("app.blitztext.unfinished-recordings-changed")

    /// Deletes recordings older than `keptFor`, without reading them.
    @MainActor static func removeExpired(now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        var removed = false
        for url in files where url.pathExtension == "wav" && !inProgress.contains(url) {
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

    /// "Diktat von 10:31 Uhr, 2 Min.", always ending with a period.
    static func label(for item: Item) -> String {
        let time = item.recordedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_DE")))
        let length = item.seconds < 60 ? "\(max(1, Int(item.seconds.rounded()))) Sek." : "\(Int((item.seconds / 60).rounded())) Min."
        return "Diktat von \(time) Uhr, \(length)"
    }
}
