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
            XCTFail("enqueue haette werfen muessen")
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
}
