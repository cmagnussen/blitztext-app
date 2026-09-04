import XCTest

final class DictationQueueStoreTests: XCTestCase {
    private let calendar = TestCalendar.berlin
    private var arbeitsordner: URL!
    private var vaultOrdner: URL!
    private var warteschlangeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        arbeitsordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("diktat-queue-\(UUID().uuidString)", isDirectory: true)
        vaultOrdner = arbeitsordner.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultOrdner, withIntermediateDirectories: true)
        warteschlangeURL = arbeitsordner.appendingPathComponent("dictation-queue.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: arbeitsordner.path
        )
        try? FileManager.default.removeItem(at: arbeitsordner)
        try super.tearDownWithError()
    }

    private var settings: DictationSettings {
        DictationSettings(
            vaultFolderPath: vaultOrdner.path,
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )
    }

    private var kaputteSettings: DictationSettings {
        DictationSettings(
            vaultFolderPath: arbeitsordner.appendingPathComponent("gibtesnicht").path,
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )
    }

    func testLeereWarteschlangeOhneDatei() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        let offen = try await store.pending()
        XCTAssertTrue(offen.isEmpty)
    }

    func testEintragUeberlebtEinenNeuenStore() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        let eintrag = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            text: "Gedanke."
        )
        try await store.enqueue(eintrag)

        let zweiterStore = DictationQueueStore(fileURL: warteschlangeURL)
        let offen = try await zweiterStore.pending()
        XCTAssertEqual(offen, [eintrag])
    }

    func testNachziehenSchreibtUndLeertDieWarteschlange() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            text: "Nachgezogener Gedanke."
        ))

        let service = VaultInboxService(calendar: calendar)
        let ergebnis = await store.flush(using: service, settings: settings)

        XCTAssertEqual(ergebnis, DictationQueueStore.FlushResult(written: 1, remaining: 0))
        let text = try String(
            contentsOf: vaultOrdner.appendingPathComponent("2026-09-04-diktat.md"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("## 14:07\nNachgezogener Gedanke."))
        let offen = try await store.pending()
        XCTAssertTrue(offen.isEmpty)
    }

    /// Der wichtigste Test dieses Tasks: ein Eintrag von gestern gehört in die
    /// Datei von gestern, nicht in die von heute.
    func testEintragVonGesternLandetInDerDateiVonGestern() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 3, 11, 15),
            text: "Gedanke von Donnerstag."
        ))
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 11, 15),
            text: "Gedanke von Freitag."
        ))

        let service = VaultInboxService(calendar: calendar)
        let ergebnis = await store.flush(using: service, settings: settings)
        XCTAssertEqual(ergebnis.written, 2)

        let donnerstag = try String(
            contentsOf: vaultOrdner.appendingPathComponent("2026-09-03-diktat.md"),
            encoding: .utf8
        )
        let freitag = try String(
            contentsOf: vaultOrdner.appendingPathComponent("2026-09-04-diktat.md"),
            encoding: .utf8
        )
        XCTAssertTrue(donnerstag.contains("Gedanke von Donnerstag."))
        XCTAssertFalse(donnerstag.contains("Gedanke von Freitag."))
        XCTAssertTrue(freitag.contains("Gedanke von Freitag."))
    }

    func testGescheitertesNachziehenLaesstDenEintragLiegen() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        let eintrag = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            text: "Gedanke."
        )
        try await store.enqueue(eintrag)

        let service = VaultInboxService(calendar: calendar)
        let ergebnis = await store.flush(using: service, settings: kaputteSettings)

        XCTAssertEqual(ergebnis.written, 0)
        XCTAssertEqual(ergebnis.remaining, 1)
        XCTAssertNotNil(ergebnis.stoppedBecause)
        let offen = try await store.pending()
        XCTAssertEqual(offen, [eintrag])
    }

    func testNachziehenArbeitetAeltesteZuerst() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 16, 0),
            text: "Später."
        ))
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 8, 0),
            text: "Früher."
        ))

        let service = VaultInboxService(calendar: calendar)
        _ = await store.flush(using: service, settings: settings)

        let text = try String(
            contentsOf: vaultOrdner.appendingPathComponent("2026-09-04-diktat.md"),
            encoding: .utf8
        )
        let indexFrueher = text.range(of: "Früher.")!.lowerBound
        let indexSpaeter = text.range(of: "Später.")!.lowerBound
        XCTAssertLessThan(indexFrueher, indexSpaeter)
    }

    func testWarteschlangeLaesstKeineTempDateiZurueck() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            text: "Gedanke."
        ))

        let dateien = try FileManager.default.contentsOfDirectory(atPath: arbeitsordner.path)
        XCTAssertEqual(dateien.filter { $0.contains(".tmp-") }, [])
    }

    func testBeschaedigteWarteschlangeWirdNichtUeberschrieben() async throws {
        let kaputt = Data("{ das ist keine Liste".utf8)
        try kaputt.write(to: warteschlangeURL)

        let store = DictationQueueStore(fileURL: warteschlangeURL)
        do {
            try await store.enqueue(QueuedDictation(
                recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
                text: "Gedanke."
            ))
            XCTFail("enqueue hätte werfen müssen")
        } catch DictationQueueError.queueFileUnreadable {
            // erwartet
        }

        let aufDerPlatte = try Data(contentsOf: warteschlangeURL)
        XCTAssertEqual(aufDerPlatte, kaputt)
    }

    func testFlushRuehrtEineBeschaedigteWarteschlangeNichtAn() async throws {
        let kaputt = Data("{ das ist keine Liste".utf8)
        try kaputt.write(to: warteschlangeURL)

        let store = DictationQueueStore(fileURL: warteschlangeURL)
        let service = VaultInboxService(calendar: calendar)
        let ergebnis = await store.flush(using: service, settings: settings)

        XCTAssertEqual(ergebnis.written, 0)
        XCTAssertNotNil(ergebnis.stoppedBecause)

        let aufDerPlatte = try Data(contentsOf: warteschlangeURL)
        XCTAssertEqual(aufDerPlatte, kaputt)

        let vaultDateien = try FileManager.default.contentsOfDirectory(atPath: vaultOrdner.path)
        XCTAssertTrue(vaultDateien.isEmpty)
    }

    func testAbbruchWennDieWarteschlangeNichtGeschriebenWerdenKann() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 3, 11, 15),
            text: "Gedanke von Donnerstag."
        ))
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 11, 15),
            text: "Gedanke von Freitag."
        ))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: arbeitsordner.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: arbeitsordner.path
            )
        }

        let service = VaultInboxService(calendar: calendar)
        let ergebnis = await store.flush(using: service, settings: settings)

        XCTAssertEqual(ergebnis.written, 1)
        XCTAssertNotNil(ergebnis.stoppedBecause)

        let freitagDatei = vaultOrdner.appendingPathComponent("2026-09-04-diktat.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: freitagDatei.path))
    }

    // MARK: - Reentrancy: flush gegen enqueue, flush gegen flush

    /// Eigener Arbeitsordner pro Durchlauf, damit viele Versuche parallel
    /// laufen können, ohne sich gegenseitig zu stören.
    private func neueUmgebung() throws -> (ordner: URL, vault: URL, warteschlange: URL) {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("diktat-race-\(UUID().uuidString)", isDirectory: true)
        let vault = ordner.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let warteschlange = ordner.appendingPathComponent("dictation-queue.json")
        return (ordner, vault, warteschlange)
    }

    private func fangeFehler(_ arbeit: () async throws -> Void) async -> Error? {
        do {
            try await arbeit()
            return nil
        } catch {
            return error
        }
    }

    /// Ein Durchlauf: ein Eintrag liegt schon in der Warteschlange und wird
    /// nachgezogen, während gleichzeitig ein zweiter Eintrag eingereiht wird.
    /// `flush` liest vor dem `await service.append(...)` eine lokale Kopie.
    /// Ohne den Fix in `DictationQueueStore.flush` würde die Actor-Reentrancy
    /// an genau dieser Stelle das gleichzeitig eingereihte `neu` verwerfen,
    /// sobald `flush` nach dem `await` seine veraltete, leere Kopie
    /// zurückschreibt.
    ///
    /// Geprüft wird die Invariante, nicht ein fester Ablauf: `flush` liest die
    /// Warteschlange nach jedem Schreiben frisch neu und kann deshalb legitim
    /// auch `neu` noch mitnehmen, falls es rechtzeitig auf der Platte landet.
    /// Das ist kein Fehler. Entscheidend ist nur, dass jeder der beiden
    /// Texte am Ende genau einmal vorkommt: entweder in der Vault-Tagesdatei
    /// oder in der Warteschlange, nie in beiden, nie in keinem von beiden.
    private func einzelDurchlaufFlushGegenEnqueue(index: Int) async throws {
        let umgebung = try neueUmgebung()
        defer { try? FileManager.default.removeItem(at: umgebung.ordner) }

        let store = DictationQueueStore(fileURL: umgebung.warteschlange)
        let vorhanden = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            text: "Vorhanden-\(index)."
        )
        try await store.enqueue(vorhanden)

        let neu = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 15, 0),
            text: "Neu-\(index)."
        )

        let service = VaultInboxService(calendar: calendar)
        let einstellungen = DictationSettings(
            vaultFolderPath: umgebung.vault.path,
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )

        async let flushErgebnis = store.flush(using: service, settings: einstellungen)
        async let enqueueFehler = fangeFehler { try await store.enqueue(neu) }
        _ = await flushErgebnis
        let fehler = await enqueueFehler
        XCTAssertNil(
            fehler,
            "Durchlauf \(index): enqueue haette nicht scheitern duerfen: \(String(describing: fehler))"
        )

        let tagesdatei = umgebung.vault.appendingPathComponent("2026-09-04-diktat.md")
        let text = (try? String(contentsOf: tagesdatei, encoding: .utf8)) ?? ""
        let offen = try await store.pending()

        for eintrag in [vorhanden, neu] {
            let vorkommenImVault = text.components(separatedBy: eintrag.text).count - 1
            let inWarteschlange = offen.contains(eintrag)
            XCTAssertLessThanOrEqual(
                vorkommenImVault,
                1,
                "Durchlauf \(index): \(eintrag.text) steht mehrfach in der Vault-Datei"
            )
            XCTAssertEqual(
                vorkommenImVault == 1,
                !inWarteschlange,
                "Durchlauf \(index): \(eintrag.text) muss entweder in der Vault-Datei oder in der Warteschlange stehen, nie beides und nie keines von beiden (im Vault: \(vorkommenImVault)x, in der Warteschlange: \(inWarteschlange))"
            )
        }
    }

    /// Viele Durchläufe gleichzeitig statt nacheinander: das setzt die
    /// begrenzte Anzahl an Kernen des kooperativen Thread-Pools unter Druck
    /// und macht es viel wahrscheinlicher, dass die Ausführung tatsächlich
    /// mitten in `await service.append(...)` unterbrochen und der
    /// gleichzeitige `enqueue` dazwischengeschoben wird. Läuft in deutlich
    /// unter einer Sekunde, weil jeder einzelne Durchlauf nur wenige, sehr
    /// kleine Dateien schreibt.
    func testFlushGegenGleichzeitigesEnqueueVerliertKeinenEintrag() async throws {
        let durchlaeufe = 150
        try await withThrowingTaskGroup(of: Void.self) { gruppe in
            for index in 0..<durchlaeufe {
                gruppe.addTask { try await self.einzelDurchlaufFlushGegenEnqueue(index: index) }
            }
            try await gruppe.waitForAll()
        }
    }

    /// Ein Durchlauf: zwei Einträge liegen in der Warteschlange, zwei
    /// gleichzeitige `flush`-Aufrufe auf demselben Store versuchen, sie
    /// nachzuziehen. Ohne die `isFlushing`-Sperre könnten beide dieselbe
    /// veraltete Kopie lesen, bevor eine von beiden etwas persistiert, und so
    /// denselben Eintrag doppelt in die Vault-Datei schreiben. Geprüft wird,
    /// dass am Ende jeder Text höchstens einmal im Vault steht und dass die
    /// Summe aus beiden Ergebnissen genau der Anzahl der Einträge entspricht.
    private func einzelDurchlaufFlushGegenFlush(index: Int) async throws {
        let umgebung = try neueUmgebung()
        defer { try? FileManager.default.removeItem(at: umgebung.ordner) }

        let store = DictationQueueStore(fileURL: umgebung.warteschlange)
        let eins = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 8, 0),
            text: "RaceEins-\(index)."
        )
        let zwei = QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 0),
            text: "RaceZwei-\(index)."
        )
        try await store.enqueue(eins)
        try await store.enqueue(zwei)

        let service = VaultInboxService(calendar: calendar)
        let einstellungen = DictationSettings(
            vaultFolderPath: umgebung.vault.path,
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )

        async let ergebnisA = store.flush(using: service, settings: einstellungen)
        async let ergebnisB = store.flush(using: service, settings: einstellungen)
        let (a, b) = await (ergebnisA, ergebnisB)

        let tagesdatei = umgebung.vault.appendingPathComponent("2026-09-04-diktat.md")
        let text = (try? String(contentsOf: tagesdatei, encoding: .utf8)) ?? ""
        let offen = try await store.pending()

        for eintrag in [eins, zwei] {
            let vorkommen = text.components(separatedBy: eintrag.text).count - 1
            XCTAssertLessThanOrEqual(
                vorkommen,
                1,
                "Durchlauf \(index): \(eintrag.text) steht mehrfach in der Vault-Datei"
            )
            XCTAssertEqual(
                vorkommen == 1,
                !offen.contains(eintrag),
                "Durchlauf \(index): \(eintrag.text) muss entweder in der Vault-Datei oder in der Warteschlange stehen, nie beides und nie keines von beiden"
            )
        }
        XCTAssertEqual(
            a.written + b.written,
            2,
            "Durchlauf \(index): zusammen muessen beide flush-Aufrufe genau 2 Eintraege geschrieben haben"
        )
    }

    func testFlushGegenGleichzeitigenFlushSchreibtJedenEintragNurEinmal() async throws {
        let durchlaeufe = 150
        try await withThrowingTaskGroup(of: Void.self) { gruppe in
            for index in 0..<durchlaeufe {
                gruppe.addTask { try await self.einzelDurchlaufFlushGegenFlush(index: index) }
            }
            try await gruppe.waitForAll()
        }
    }
}
