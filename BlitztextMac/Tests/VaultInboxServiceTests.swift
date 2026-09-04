import XCTest

final class VaultInboxServiceTests: XCTestCase {
    private let calendar = TestCalendar.berlin
    private var ordner: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("diktat-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
        try super.tearDownWithError()
    }

    private func settings(frontmatter: Bool = true) -> DictationSettings {
        DictationSettings(
            vaultFolderPath: ordner.path,
            writesSecondBrainFrontmatter: frontmatter,
            sphere: .beruf
        )
    }

    private func inhalt(of name: String) throws -> String {
        try String(contentsOf: ordner.appendingPathComponent(name), encoding: .utf8)
    }

    private var uebrigeDateien: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
    }

    func testErstesDiktatLegtDieTagesdateiAn() async throws {
        let service = VaultInboxService(calendar: calendar)
        let ziel = try await service.append(
            text: "Erster Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings()
        )

        XCTAssertEqual(ziel.lastPathComponent, "2026-09-04-diktat.md")
        let text = try inhalt(of: "2026-09-04-diktat.md")
        XCTAssertTrue(text.hasPrefix("---\ntyp: log\n"))
        XCTAssertTrue(text.contains("## 09:42\nErster Gedanke."))
    }

    func testZweitesDiktatHaengtAnStattZuUeberschreiben() async throws {
        let service = VaultInboxService(calendar: calendar)
        _ = try await service.append(
            text: "Erster Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings()
        )
        _ = try await service.append(
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            settings: settings()
        )

        let text = try inhalt(of: "2026-09-04-diktat.md")
        XCTAssertTrue(text.contains("## 09:42\nErster Gedanke."))
        XCTAssertTrue(text.contains("## 14:07\nZweiter Gedanke."))
        XCTAssertEqual(text.components(separatedBy: "# Diktate").count - 1, 1)
    }

    func testDiktateAnVerschiedenenTagenGehenInVerschiedeneDateien() async throws {
        let service = VaultInboxService(calendar: calendar)
        _ = try await service.append(
            text: "Montag.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings()
        )
        _ = try await service.append(
            text: "Dienstag.",
            recordedAt: TestCalendar.date(2026, 9, 5, 9, 42),
            settings: settings()
        )

        XCTAssertTrue(uebrigeDateien.contains("2026-09-04-diktat.md"))
        XCTAssertTrue(uebrigeDateien.contains("2026-09-05-diktat.md"))
    }

    func testNachDemSchreibenLiegtKeineTempDateiHerum() async throws {
        let service = VaultInboxService(calendar: calendar)
        _ = try await service.append(
            text: "Erster Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings()
        )
        _ = try await service.append(
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            settings: settings()
        )

        XCTAssertEqual(uebrigeDateien, ["2026-09-04-diktat.md"])
    }

    /// Der actor serialisiert. Fünf gleichzeitige Diktate müssen fünf
    /// Abschnitte ergeben, keiner darf verloren gehen.
    func testFuenfGleichzeitigeDiktateGehenNichtVerloren() async throws {
        let service = VaultInboxService(calendar: calendar)
        let konfiguration = settings()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for minute in 0..<5 {
                group.addTask {
                    _ = try await service.append(
                        text: "Gedanke \(minute).",
                        recordedAt: TestCalendar.date(2026, 9, 4, 10, minute),
                        settings: konfiguration
                    )
                }
            }
            try await group.waitForAll()
        }

        let text = try inhalt(of: "2026-09-04-diktat.md")
        for minute in 0..<5 {
            XCTAssertTrue(text.contains("Gedanke \(minute)."), "Gedanke \(minute) fehlt")
        }
        XCTAssertEqual(text.components(separatedBy: "## 10:").count - 1, 5)
        XCTAssertEqual(uebrigeDateien, ["2026-09-04-diktat.md"])
    }

    func testOhneOrdnerEinstellungGibtEsEinenKlarenFehler() async {
        let service = VaultInboxService(calendar: calendar)
        do {
            _ = try await service.append(
                text: "Gedanke.",
                recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
                settings: DictationSettings()
            )
            XCTFail("Es hätte ein Fehler kommen müssen.")
        } catch let fehler as VaultInboxError {
            XCTAssertEqual(fehler, .folderNotConfigured)
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testFehlenderOrdnerWirdNichtAngelegt() async {
        let service = VaultInboxService(calendar: calendar)
        let verschwunden = ordner.appendingPathComponent("weg", isDirectory: true)
        var konfiguration = settings()
        konfiguration.vaultFolderPath = verschwunden.path

        do {
            _ = try await service.append(
                text: "Gedanke.",
                recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
                settings: konfiguration
            )
            XCTFail("Es hätte ein Fehler kommen müssen.")
        } catch let fehler as VaultInboxError {
            XCTAssertEqual(fehler, .folderMissing(verschwunden.path))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: verschwunden.path))
    }

    func testTildeImPfadWirdZuEinemAbsolutenPfadAufgeloest() async {
        let service = VaultInboxService(calendar: calendar)
        let name = "blitztext-gibtesnicht-\(UUID().uuidString)"
        var konfiguration = settings()
        konfiguration.vaultFolderPath = "~/\(name)"

        // Die Tilde-Auflösung lässt sich am geworfenen Pfad ablesen, ohne
        // irgendwo außerhalb des Temp-Ordners zu schreiben: Der Ordner
        // existiert garantiert nicht, also nimmt append() deterministisch den
        // folderMissing-Fehlerpfad, und der darin enthaltene Pfad ist genau
        // der aufgelöste, den der Service tatsächlich geprüft hat.
        do {
            _ = try await service.append(
                text: "Gedanke.",
                recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
                settings: konfiguration
            )
            XCTFail("Es hätte ein Fehler kommen müssen.")
        } catch let fehler as VaultInboxError {
            guard case .folderMissing(let pfad) = fehler else {
                XCTFail("Falscher Fehlerfall: \(fehler)")
                return
            }
            XCTAssertFalse(pfad.contains("~"))
            XCTAssertTrue(pfad.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
            XCTAssertTrue(pfad.hasSuffix(name))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }
    }

    func testUnlesbareBestehendeDateiWirdNichtUeberschrieben() async throws {
        let ziel = ordner.appendingPathComponent("2026-09-04-diktat.md")
        // Ein Ordner an der Stelle der Datei laesst sich nicht als Text lesen.
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)

        let service = VaultInboxService(calendar: calendar)
        do {
            _ = try await service.append(
                text: "Gedanke.",
                recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
                settings: settings()
            )
            XCTFail("Es hätte ein Fehler kommen müssen.")
        } catch let fehler as VaultInboxError {
            XCTAssertEqual(fehler, .existingFileUnreadable(ziel.path))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }

        var istOrdner: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: ziel.path, isDirectory: &istOrdner))
        XCTAssertTrue(istOrdner.boolValue)
    }
}
