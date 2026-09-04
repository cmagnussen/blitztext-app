import Foundation

/// Ein Diktat, das noch nicht in der Tagesdatei steht.
struct QueuedDictation: Codable, Equatable {
    let recordedAt: Date
    let text: String
}

enum DictationQueueError: LocalizedError, Equatable {
    case queueFileUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .queueFileUnreadable(let pfad):
            return "Warteschlange ist nicht lesbar: \(pfad)"
        }
    }
}

/// Hält Diktate, deren Schreiben fehlgeschlagen ist, und zieht sie später
/// nach. Ein Eintrag verlässt die Warteschlange ausschließlich durch
/// erfolgreiches Schreiben. Es gibt keine Obergrenze, die still verwerfen
/// könnte.
actor DictationQueueStore {
    struct FlushResult: Equatable {
        let written: Int
        let remaining: Int
        /// Gesetzt, wenn der Durchlauf vorzeitig endete: Klartextgrund, damit die
        /// App ihn melden kann. nil heisst, es gab nichts Ungewöhnliches.
        let stoppedBecause: String?

        init(written: Int, remaining: Int, stoppedBecause: String? = nil) {
            self.written = written
            self.remaining = remaining
            self.stoppedBecause = stoppedBecause
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Verhindert zwei gleichzeitige Durchläufe. Actors sind an
    /// Suspension-Points reentrant: ohne diese Sperre könnten zwei sich
    /// überlappende `flush`-Aufrufe denselben Eintrag beide in den Vault
    /// schreiben. Wird synchron gesetzt und per `defer` zurückgesetzt, ohne
    /// `await` dazwischen, damit die Prüfung selbst nicht racy ist.
    private var isFlushing = false

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

    /// Offene Einträge, ältester zuerst. Fehlt die Datei, ist die Warteschlange
    /// leer. Ist sie da, aber nicht lesbar oder nicht dekodierbar, wird das
    /// gemeldet statt stillschweigend als leer behandelt zu werden: sonst
    /// würde der nächste `enqueue` eine beschädigte Datei mit einem einzigen
    /// neuen Eintrag überschreiben und alles andere wäre verloren.
    func pending() throws -> [QueuedDictation] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL),
              let eintraege = try? decoder.decode([QueuedDictation].self, from: data) else {
            throw DictationQueueError.queueFileUnreadable(fileURL.path)
        }
        return eintraege.sorted { $0.recordedAt < $1.recordedAt }
    }

    func enqueue(_ item: QueuedDictation) throws {
        var eintraege = try pending()
        eintraege.append(item)
        try persist(eintraege.sorted { $0.recordedAt < $1.recordedAt })
    }

    /// Schreibt die offenen Einträge, ältester zuerst.
    ///
    /// `await service.append(...)` ruft eine andere Actor-Instanz auf und ist
    /// damit ein echter Suspension-Point: Actors sind dort reentrant, ein
    /// paralleler `enqueue`-Aufruf auf diesem Actor kann währenddessen
    /// vollständig durchlaufen und die Datei ändern. Eine lokale Kopie der
    /// Warteschlange, die vor dem `await` gelesen und danach blind
    /// zurückgeschrieben würde, wäre deshalb potenziell veraltet und könnte
    /// einen frisch eingereihten Eintrag beim Zurückschreiben verwerfen.
    ///
    /// Deshalb wird nach jedem erfolgreichen Schreiben die Warteschlange neu
    /// von der Platte gelesen, der geschriebene Eintrag per Gleichheit
    /// entfernt (genau ein Vorkommen, nicht alle) und sofort persistiert.
    /// Das geschieht alles synchron, ohne weiteres `await` dazwischen, sodass
    /// zwischen Lesen und Schreiben kein weiterer Suspension-Point liegt, an
    /// dem sich wieder etwas ändern könnte. `isFlushing` verhindert
    /// zusätzlich, dass zwei überlappende Durchläufe denselben Eintrag
    /// doppelt schreiben.
    ///
    /// Scheitert entweder das Schreiben in den Vault oder das Persistieren,
    /// bricht der Durchlauf ab und lässt den Rest liegen: scheitert der
    /// Ordner, scheitern alle weiteren ohnehin, und ein Abbruch bewahrt die
    /// Reihenfolge sowie das Sicherheitsversprechen, nie einen Eintrag zu
    /// verlieren.
    func flush(using service: VaultInboxService, settings: DictationSettings) async -> FlushResult {
        guard !isFlushing else {
            let restlich = (try? pending())?.count ?? 0
            return FlushResult(
                written: 0,
                remaining: restlich,
                stoppedBecause: "Ein Nachziehen läuft bereits."
            )
        }
        isFlushing = true
        defer { isFlushing = false }

        var offen: [QueuedDictation]
        do {
            offen = try pending()
        } catch {
            return FlushResult(written: 0, remaining: 0, stoppedBecause: error.localizedDescription)
        }
        guard !offen.isEmpty else { return FlushResult(written: 0, remaining: 0) }

        var geschrieben = 0
        var abbruchgrund: String?

        while let naechster = offen.first {
            do {
                _ = try await service.append(
                    text: naechster.text,
                    recordedAt: naechster.recordedAt,
                    settings: settings
                )
            } catch {
                abbruchgrund = error.localizedDescription
                break
            }

            geschrieben += 1

            do {
                var aktuell = try pending()
                if let index = aktuell.firstIndex(of: naechster) {
                    aktuell.remove(at: index)
                }
                try persist(aktuell)
                offen = aktuell
            } catch {
                abbruchgrund = error.localizedDescription
                break
            }
        }

        return FlushResult(written: geschrieben, remaining: offen.count, stoppedBecause: abbruchgrund)
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
