import Foundation

/// Ein Diktat, das noch nicht in der Tagesdatei steht.
struct QueuedDictation: Codable, Equatable {
    let recordedAt: Date
    let text: String
}

/// Hält Diktate, deren Schreiben fehlgeschlagen ist, und zieht sie später
/// nach. Ein Eintrag verlässt die Warteschlange ausschließlich durch
/// erfolgreiches Schreiben. Es gibt keine Obergrenze, die still verwerfen
/// könnte.
actor DictationQueueStore {
    struct FlushResult: Equatable {
        let written: Int
        let remaining: Int
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Offene Einträge, ältester zuerst.
    func pending() -> [QueuedDictation] {
        guard let data = try? Data(contentsOf: fileURL),
              let eintraege = try? decoder.decode([QueuedDictation].self, from: data) else {
            return []
        }
        return eintraege.sorted { $0.recordedAt < $1.recordedAt }
    }

    func enqueue(_ item: QueuedDictation) throws {
        var eintraege = pending()
        eintraege.append(item)
        try persist(eintraege.sorted { $0.recordedAt < $1.recordedAt })
    }

    /// Schreibt die offenen Einträge, ältester zuerst. Beim ersten Fehler
    /// bricht sie ab und lässt den Rest liegen: scheitert der Ordner, scheitern
    /// alle weiteren ohnehin, und ein Abbruch bewahrt die Reihenfolge.
    func flush(using service: VaultInboxService, settings: DictationSettings) async -> FlushResult {
        var offen = pending()
        guard !offen.isEmpty else { return FlushResult(written: 0, remaining: 0) }

        var geschrieben = 0
        while let naechster = offen.first {
            do {
                _ = try await service.append(
                    text: naechster.text,
                    recordedAt: naechster.recordedAt,
                    settings: settings
                )
                offen.removeFirst()
                geschrieben += 1
            } catch {
                break
            }
        }

        try? persist(offen)
        return FlushResult(written: geschrieben, remaining: offen.count)
    }

    /// Auch die Warteschlange wird atomar geschrieben. Ein Absturz mitten im
    /// Schreiben darf keine halbe Liste hinterlassen.
    private func persist(_ eintraege: [QueuedDictation]) throws {
        let ordner = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: ordner, withIntermediateDirectories: true)

        if eintraege.isEmpty {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        let data = try encoder.encode(eintraege)
        let temp = ordner.appendingPathComponent(
            ".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)"
        )

        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }
}
