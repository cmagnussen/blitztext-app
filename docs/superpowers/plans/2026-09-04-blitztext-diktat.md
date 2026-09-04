# Blitztext Diktat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine Tastenkombination druecken, sprechen, loslassen, und der Transkripttext haengt als Abschnitt mit Uhrzeit an einer Tagesdatei in einem eingestellten Ordner, statt am Cursor zu landen.

**Architecture:** Ein neuer `WorkflowType.vaultDictation` benutzt die bestehende `TranscriptionWorkflow`-Klasse unveraendert. Neu ist ein deklariertes Ausgabeziel (`WorkflowOutputDestination`), auf das `AppState.handleWorkflowOutput` verzweigt: `cursor` wie bisher, `vaultInbox` in einen neuen `VaultInboxService`. Die Dokumentlogik (Tagesgrenze, Dateiname, Frontmatter, Anhaengen) liegt in einem reinen, dateisystemfreien `VaultInboxDocument` und ist damit vollstaendig testbar. Fehlgeschlagene Schreibvorgaenge landen in einem `DictationQueueStore` und werden spaeter nachgezogen.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, XCTest, XcodeGen, UserNotifications.

**Spec:** `docs/superpowers/specs/2026-09-04-blitztext-diktat-design.md`

## Global Constraints

- Zielplattform macOS 14.0, Swift 5.10, Xcode 16. Kein Windows in diesem Plan.
- Alle sichtbaren Texte sind deutsch. **Keine Gedankenstriche (—) in Texten.**
- In `Features/Settings/SettingsContentView.swift` werden Umlaute in Swift-String-Literalen als Unicode-Escape geschrieben (`\u{00FC}` fuer ue, `\u{00E4}` fuer ae, `\u{00F6}` fuer oe, `\u{00DF}` fuer sz). Das ist die dort vorhandene Konvention, siehe `SettingsContentView.swift:915`. In neuen Dateien werden Umlaute direkt geschrieben, so wie in `TranscriptionWorkflow.swift`.
- Nach dem Anlegen jeder neuen Quelldatei muss `xcodegen generate` laufen, sonst ist die Datei nicht Teil des Xcode-Projekts.
- Der Marker `<!-- diktat: offen -->` wird nur geschrieben, nie geaendert und nie entfernt.
- Der eingestellte Zielordner wird nie angelegt. Fehlt er, ist das ein Fehler.
- Ein Diktattext verlaesst die Warteschlange ausschliesslich durch erfolgreiches Schreiben.
- Feste Frontmatter-Werte, exakt: `typ: log`, `status: aktiv`, `topf: inbox`, `themen: []`, `quelle: gespräch`, `stichworte: [diktat, schnellerfassung]`, `geprüft:` leer.
- Tagesgrenze 04:00 lokale Zeit. Stunde kleiner 4 heisst Vortag.

## Zwei Abweichungen von der Spec

Beide sind Verfeinerungen, keine inhaltlichen Aenderungen:

1. **Die Spec nennt eine Datei `VaultInboxService.swift`. Der Plan teilt sie in zwei:** `VaultInboxDocument.swift` (reine Textlogik, kein Dateisystem) und `VaultInboxService.swift` (der `actor` mit den Schreibzugriffen). Grund: die reine Logik ist der riskante Teil und laesst sich so ohne Ordner, ohne Zeitabhaengigkeit und ohne App-Host pruefen.
2. **Die Spec legt `DictationSettings` in `WorkflowProtocol.swift`, der Plan legt es in `Services/DictationSettings.swift`.** Grund: `WorkflowProtocol.swift` verweist auf `LocalTranscriptionService` und damit auf WhisperKit. Eine eigene Datei bleibt Foundation-only und kann direkt in ein Testziel ohne App-Host uebersetzt werden. Das ist die Voraussetzung dafuer, dass die Tests schnell laufen und nicht die echte `settings.json` des Users anfassen.

## Dateistruktur

Neu:

| Datei | Verantwortung | Haengt ab von |
|---|---|---|
| `BlitztextMac/Services/DictationSettings.swift` | Zielordner, Frontmatter-Schalter, Sphaere | Foundation |
| `BlitztextMac/Services/VaultInboxDocument.swift` | Tagesgrenze, Dateiname, Kopf, Abschnitt, Anhaengen, Frontmatter-Datum. Reine Funktionen. | Foundation, `DictationSettings` |
| `BlitztextMac/Services/VaultInboxService.swift` | `actor`, prueft den Ordner, schreibt atomar | Foundation, `VaultInboxDocument` |
| `BlitztextMac/Services/DictationQueueStore.swift` | `actor`, haelt fehlgeschlagene Diktate, zieht nach | Foundation, `VaultInboxService` |
| `BlitztextMac/Services/UserNotificationService.swift` | Freigabe, Erfolgs- und Fehlermeldung | UserNotifications |
| `BlitztextMac/Tests/` | Testfaelle | XCTest |
| `test.sh` | Testlauf mit einem Befehl | keine |

Geaendert: `WorkflowProtocol.swift`, `AppState.swift`, `MenuBarStatusController.swift`, `HotkeyService.swift`, `AppSupportPaths.swift`, `SettingsContentView.swift`, `Resources/Info.plist`, `project.yml`, `README.md`.

---

### Task 1: Testziel und Datumslogik

Legt das erste Testziel im Repo an und prueft damit sofort die Tagesgrenze. Das Testziel hat **keinen** App-Host, es uebersetzt nur die Foundation-Dateien, die es braucht. So laeuft kein Menueleisten-Programm los und keine echte `settings.json` wird angefasst.

**Files:**
- Modify: `BlitztextMac/project.yml`
- Create: `BlitztextMac/Services/DictationSettings.swift`
- Create: `BlitztextMac/Services/VaultInboxDocument.swift`
- Create: `test.sh`
- Test: `BlitztextMac/Tests/VaultInboxDocumentDateTests.swift`

**Interfaces:**
- Consumes: nichts
- Produces:
  - `enum DictationSphere: String, Codable, CaseIterable, Identifiable { case beruf, privat }`, `var displayName: String`
  - `struct DictationSettings: Codable` mit `vaultFolderPath: String`, `writesSecondBrainFrontmatter: Bool`, `sphere: DictationSphere`
  - `enum VaultInboxDocument`, darin `static let dayStartHour = 4`, `static func effectiveDate(for now: Date, calendar: Calendar) -> Date`, `static func isoDay(_ date: Date, calendar: Calendar) -> String`, `static func headingDay(_ date: Date, calendar: Calendar) -> String`, `static func clockTime(_ date: Date, calendar: Calendar) -> String`, `static func fileName(for effectiveDate: Date, calendar: Calendar) -> String`

- [ ] **Step 1: Testziel in `project.yml` eintragen**

In `BlitztextMac/project.yml` unter `targets:` beim bestehenden Target `BlitztextMac` den Block `scheme:` ergaenzen (auf derselben Einrueckungsebene wie `settings:` und `dependencies:`), und danach das neue Target anhaengen:

```yaml
  BlitztextMac:
    # ... bestehender Inhalt unveraendert ...
    scheme:
      testTargets:
        - BlitztextMacTests

  BlitztextMacTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
      - path: Services/DictationSettings.swift
      - path: Services/VaultInboxDocument.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.blitztext.mac.tests
        GENERATE_INFOPLIST_FILE: true
        SWIFT_VERSION: "5.10"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        ONLY_ACTIVE_ARCH: YES
```

Hinweis: `sources` listet die Quelldateien einzeln, weil das Testziel bewusst nicht den ganzen `Services`-Ordner uebersetzt. In spaeteren Tasks kommen weitere Zeilen dazu.

- [ ] **Step 2: `test.sh` anlegen**

```bash
#!/usr/bin/env bash
# Fuehrt die Unit-Tests von BlitztextMac aus.
# Beispiel fuer einen einzelnen Test:
#   ./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentDateTests/testViertelVorVierGehoertZumVortag
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/BlitztextMac"

if command -v xcodegen &> /dev/null; then
    xcodegen generate > /dev/null
fi

xcodebuild test \
    -project BlitztextMac.xcodeproj \
    -scheme BlitztextMac \
    -destination 'platform=macOS' \
    -derivedDataPath "$SCRIPT_DIR/.derivedData-blitztextmac-build" \
    ONLY_ACTIVE_ARCH=YES \
    "$@"
```

Danach ausfuehrbar machen:

```bash
chmod +x test.sh
```

- [ ] **Step 3: Den fehlschlagenden Test schreiben**

`BlitztextMac/Tests/VaultInboxDocumentDateTests.swift`:

```swift
import XCTest

/// Feste Zeitzone und fester Kalender, damit die Tests nicht davon abhaengen,
/// wo und wann sie laufen.
enum TestCalendar {
    static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        calendar: Calendar = berlin
    ) -> Date {
        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year, month: month, day: day,
            hour: hour, minute: minute
        )
        return calendar.date(from: components)!
    }
}

final class VaultInboxDocumentDateTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    func testTagesgrenzeLiegtBeiVierUhr() {
        XCTAssertEqual(VaultInboxDocument.dayStartHour, 4)
    }

    func testViertelVorVierGehoertZumVortag() {
        let now = TestCalendar.date(2026, 9, 4, 3, 45)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-03")
    }

    func testVierUhrGehoertZumLaufendenTag() {
        let now = TestCalendar.date(2026, 9, 4, 4, 0)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-04")
    }

    func testZwanzigNachMitternachtGehoertZumVortag() {
        let now = TestCalendar.date(2026, 9, 4, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-03")
    }

    func testMonatswechselUmZwanzigNachMitternacht() {
        let now = TestCalendar.date(2026, 10, 1, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-09-30")
    }

    func testJahreswechselUmZwanzigNachMitternacht() {
        let now = TestCalendar.date(2027, 1, 1, 1, 5)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-12-31")
    }

    /// In der Nacht auf den 29.03.2026 wird in Europe/Berlin vorgestellt, der
    /// 29.03. hat 23 Stunden. Nur ein Schritt ueber diesen Tag entlarvt eine
    /// naive Rechnung mit 86400 Sekunden: kalendarisch ergibt sich der 29.03.,
    /// naiv der 28.03.
    func testNachDerFruehjahrsumstellungStimmtDerVortag() {
        let now = TestCalendar.date(2026, 3, 30, 1, 30)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-03-29")
    }

    /// Sichert die Datumsarithmetik ueber den 25-Stunden-Tag des 25.10.2026 ab.
    /// Unterscheidet fuer sich allein nicht zwischen kalendarischer und naiver
    /// Rechnung, ergaenzt aber die Fruehjahrsumstellung um die Gegenrichtung.
    func testHerbstumstellungZwanzigNachMitternachtGehoertZumVortag() {
        let now = TestCalendar.date(2026, 10, 26, 0, 20)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.isoDay(wirksam, calendar: calendar), "2026-10-25")
    }

    func testDateinameAusWirksamemDatum() {
        let now = TestCalendar.date(2026, 9, 4, 14, 7)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(
            VaultInboxDocument.fileName(for: wirksam, calendar: calendar),
            "2026-09-04-diktat.md"
        )
    }

    func testUeberschriftsdatumIstDeutschFormatiert() {
        let now = TestCalendar.date(2026, 9, 4, 14, 7)
        let wirksam = VaultInboxDocument.effectiveDate(for: now, calendar: calendar)
        XCTAssertEqual(VaultInboxDocument.headingDay(wirksam, calendar: calendar), "04.09.2026")
    }

    func testUhrzeitIstDieEchteUhrzeitUndNichtDieDesWirksamenTages() {
        let now = TestCalendar.date(2026, 9, 4, 0, 20)
        XCTAssertEqual(VaultInboxDocument.clockTime(now, calendar: calendar), "00:20")
    }

    func testEinstellungenHabenSinnvolleVorgaben() {
        let settings = DictationSettings()
        XCTAssertEqual(settings.vaultFolderPath, "")
        XCTAssertFalse(settings.writesSecondBrainFrontmatter)
        XCTAssertEqual(settings.sphere, .beruf)
    }
}
```

- [ ] **Step 4: Test laufen lassen und Fehlschlag bestaetigen**

Run: `./test.sh`
Expected: Uebersetzungsfehler, `cannot find 'VaultInboxDocument' in scope` und `cannot find 'DictationSettings' in scope`.

- [ ] **Step 5: `DictationSettings.swift` schreiben**

`BlitztextMac/Services/DictationSettings.swift`:

```swift
import Foundation

/// Sphäre der Tagesdatei. Vorgabe ist beruf, weil der Kanal im Arbeitsalltag
/// benutzt wird. Der Inbox-Sortierer korrigiert das je Abschnitt, wenn der
/// Inhalt privat ist. Blitztext soll das nicht erraten.
enum DictationSphere: String, Codable, CaseIterable, Identifiable {
    case beruf
    case privat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beruf: return "Beruf"
        case .privat: return "Privat"
        }
    }
}

/// Einstellungen des Diktat-Kanals. Der Zielordner ist bewusst leer
/// vorbelegt: ohne gesetzten Ordner ist der Workflow nicht verfügbar.
struct DictationSettings: Codable, Equatable {
    var vaultFolderPath: String = ""
    var writesSecondBrainFrontmatter: Bool = false
    var sphere: DictationSphere = .beruf

    init(
        vaultFolderPath: String = "",
        writesSecondBrainFrontmatter: Bool = false,
        sphere: DictationSphere = .beruf
    ) {
        self.vaultFolderPath = vaultFolderPath
        self.writesSecondBrainFrontmatter = writesSecondBrainFrontmatter
        self.sphere = sphere
    }

    enum CodingKeys: String, CodingKey {
        case vaultFolderPath
        case writesSecondBrainFrontmatter
        case sphere
    }

    /// Jedes Feld über decodeIfPresent, damit eine bestehende settings.json
    /// ohne diesen Abschnitt weiter lädt. Gleiches Muster wie AppSettings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaultFolderPath = try container.decodeIfPresent(String.self, forKey: .vaultFolderPath) ?? ""
        writesSecondBrainFrontmatter = try container.decodeIfPresent(
            Bool.self,
            forKey: .writesSecondBrainFrontmatter
        ) ?? false
        sphere = try container.decodeIfPresent(DictationSphere.self, forKey: .sphere) ?? .beruf
    }
}
```

- [ ] **Step 6: `VaultInboxDocument.swift` mit der Datumslogik schreiben**

`BlitztextMac/Services/VaultInboxDocument.swift`:

```swift
import Foundation

/// Reine Textlogik der Diktat-Tagesdatei: welcher Tag gilt, wie die Datei
/// heißt, wie ihr Kopf und ihre Abschnitte aussehen. Kein Dateisystem, keine
/// Uhr, keine Einstellungen aus der App. Alles hier ist prüfbar, ohne etwas
/// zu schreiben.
enum VaultInboxDocument {
    /// Der Tag wechselt um 04:00. Ein Diktat um 00:20 läuft in die Datei des
    /// Vortags.
    static let dayStartHour = 4

    /// Der Tag, in dessen Datei ein Diktat gehört. Liefert den Tagesbeginn.
    static func effectiveDate(for now: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let hour = calendar.component(.hour, from: now)
        guard hour < dayStartHour else { return startOfDay }
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
    }

    /// "2026-09-04". Für Dateinamen und Frontmatter.
    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "yyyy-MM-dd", calendar: calendar)
    }

    /// "04.09.2026". Für die H1.
    static func headingDay(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "dd.MM.yyyy", calendar: calendar)
    }

    /// "14:07". Die echte Uhrzeit der Aufnahme, nicht die des wirksamen Tages.
    static func clockTime(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "HH:mm", calendar: calendar)
    }

    static func fileName(for effectiveDate: Date, calendar: Calendar) -> String {
        "\(isoDay(effectiveDate, calendar: calendar))-diktat.md"
    }

    /// en_US_POSIX, damit kein Gebietsschema die Ziffern verändert.
    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 7: Test laufen lassen und Erfolg bestaetigen**

Run: `./test.sh`
Expected: PASS, 12 Tests in `VaultInboxDocumentDateTests`.

- [ ] **Step 8: Pruefen, dass der App-Build weiter laeuft**

Das neue `scheme:` in `project.yml` erzeugt ein geteiltes Schema, das `build.sh` vorher nicht hatte. Deshalb einmal absichern:

Run: `./build.sh`
Expected: Build erfolgreich, `Blitztext.app` wird gefunden.

Schlaegt es fehl, ist die Ursache das generierte Schema und nicht der neue Code. Dann `BlitztextMac/BlitztextMac.xcodeproj/xcshareddata/xcschemes/BlitztextMac.xcscheme` ansehen und pruefen, ob das App-Target dort in der Build-Aktion steht.

- [ ] **Step 9: Commit**

```bash
git add BlitztextMac/project.yml BlitztextMac/Services/DictationSettings.swift BlitztextMac/Services/VaultInboxDocument.swift BlitztextMac/Tests/VaultInboxDocumentDateTests.swift test.sh
git commit -m "Diktat: Testziel und Tagesgrenze um 04:00"
```

---

### Task 2: Kopf und Abschnitt einer neuen Tagesdatei

**Files:**
- Modify: `BlitztextMac/Services/VaultInboxDocument.swift`
- Test: `BlitztextMac/Tests/VaultInboxDocumentNewFileTests.swift`

**Interfaces:**
- Consumes: `VaultInboxDocument.effectiveDate`, `isoDay`, `headingDay`, `clockTime`, `DictationSettings`
- Produces:
  - `static func section(text: String, at time: Date, calendar: Calendar) -> String`
  - `static func newDocument(text: String, recordedAt: Date, settings: DictationSettings, calendar: Calendar) -> String`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

`BlitztextMac/Tests/VaultInboxDocumentNewFileTests.swift`:

```swift
import XCTest

final class VaultInboxDocumentNewFileTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    private var mitFrontmatter: DictationSettings {
        DictationSettings(
            vaultFolderPath: "/tmp/vault",
            writesSecondBrainFrontmatter: true,
            sphere: .beruf
        )
    }

    private var ohneFrontmatter: DictationSettings {
        DictationSettings(
            vaultFolderPath: "/tmp/vault",
            writesSecondBrainFrontmatter: false,
            sphere: .beruf
        )
    }

    func testAbschnittIstUhrzeitUndText() {
        let abschnitt = VaultInboxDocument.section(
            text: "Kunde XY nachfassen.",
            at: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )
        XCTAssertEqual(abschnitt, "## 14:07\nKunde XY nachfassen.")
    }

    func testAbschnittEntferntUmschliessendeLeerzeichen() {
        let abschnitt = VaultInboxDocument.section(
            text: "  Kunde XY nachfassen.\n\n",
            at: TestCalendar.date(2026, 9, 4, 9, 42),
            calendar: calendar
        )
        XCTAssertEqual(abschnitt, "## 09:42\nKunde XY nachfassen.")
    }

    func testNeueDateiMitFrontmatterEntsprichtDemFormatAusDerNotiz() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Roher Transkripttext, unverändert.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: mitFrontmatter,
            calendar: calendar
        )

        let erwartet = """
        ---
        typ: log
        status: aktiv
        topf: inbox
        sphaere: beruf
        themen: []
        quelle: gespräch
        stichworte: [diktat, schnellerfassung]
        erstellt: 2026-09-04
        aktualisiert: 2026-09-04
        geprüft:
        ---

        <!-- diktat: offen -->

        # Diktate 04.09.2026

        ## 09:42
        Roher Transkripttext, unverändert.

        """

        XCTAssertEqual(inhalt, erwartet)
    }

    func testNeueDateiUebernimmtDieEingestellteSphaere() {
        var settings = mitFrontmatter
        settings.sphere = .privat
        let inhalt = VaultInboxDocument.newDocument(
            text: "Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: settings,
            calendar: calendar
        )
        XCTAssertTrue(inhalt.contains("\nsphaere: privat\n"))
        XCTAssertFalse(inhalt.contains("sphaere: beruf"))
    }

    func testNeueDateiOhneFrontmatterBeginntBeiDerUeberschrift() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
            settings: ohneFrontmatter,
            calendar: calendar
        )

        let erwartet = """
        # Diktate 04.09.2026

        ## 09:42
        Gedanke.

        """

        XCTAssertEqual(inhalt, erwartet)
        XCTAssertFalse(inhalt.contains("<!-- diktat: offen -->"))
    }

    func testNeueDateiUmZwanzigNachMitternachtTraegtDasDatumDesVortags() {
        let inhalt = VaultInboxDocument.newDocument(
            text: "Spaeter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 0, 20),
            settings: mitFrontmatter,
            calendar: calendar
        )
        XCTAssertTrue(inhalt.contains("erstellt: 2026-09-03"))
        XCTAssertTrue(inhalt.contains("# Diktate 03.09.2026"))
        XCTAssertTrue(inhalt.contains("## 00:20"))
    }
}
```

- [ ] **Step 2: Test laufen lassen und Fehlschlag bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentNewFileTests`
Expected: Uebersetzungsfehler, `type 'VaultInboxDocument' has no member 'section'` und `has no member 'newDocument'`.

- [ ] **Step 3: `section` und `newDocument` ergaenzen**

In `BlitztextMac/Services/VaultInboxDocument.swift` unterhalb von `fileName` einfuegen:

```swift
    // MARK: - Bausteine

    /// Ein Abschnitt ist die Uhrzeit als H2 und darunter der rohe
    /// Transkripttext. Nichts sonst.
    static func section(text: String, at time: Date, calendar: Calendar) -> String {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "## \(clockTime(time, calendar: calendar))\n\(roh)"
    }

    /// Inhalt einer Tagesdatei, die es noch nicht gibt. Legt Frontmatter,
    /// Marker, H1 und den ersten Abschnitt an.
    static func newDocument(
        text: String,
        recordedAt: Date,
        settings: DictationSettings,
        calendar: Calendar
    ) -> String {
        let tag = effectiveDate(for: recordedAt, calendar: calendar)
        var bloecke: [String] = []

        if settings.writesSecondBrainFrontmatter {
            bloecke.append(frontmatter(day: isoDay(tag, calendar: calendar), sphere: settings.sphere))
            bloecke.append("<!-- diktat: offen -->")
        }

        bloecke.append("# Diktate \(headingDay(tag, calendar: calendar))")
        bloecke.append(section(text: text, at: recordedAt, calendar: calendar))

        return bloecke.joined(separator: "\n\n") + "\n"
    }

    /// Feste Werte laut Konzeptnotiz. Die Sphäre ist der einzige Wert, der
    /// variiert.
    private static func frontmatter(day: String, sphere: DictationSphere) -> String {
        """
        ---
        typ: log
        status: aktiv
        topf: inbox
        sphaere: \(sphere.rawValue)
        themen: []
        quelle: gespräch
        stichworte: [diktat, schnellerfassung]
        erstellt: \(day)
        aktualisiert: \(day)
        geprüft:
        ---
        """
    }
```

- [ ] **Step 4: Test laufen lassen und Erfolg bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentNewFileTests`
Expected: PASS, 6 Tests.

- [ ] **Step 5: Commit**

```bash
git add BlitztextMac/Services/VaultInboxDocument.swift BlitztextMac/Tests/VaultInboxDocumentNewFileTests.swift
git commit -m "Diktat: Kopf und Abschnitt einer neuen Tagesdatei"
```

---

### Task 3: Anhaengen und Frontmatter-Datum

Der riskanteste Teil des ganzen PR. Hier wird eine bestehende Datei angefasst, und ein Fehler zerstoert Text, den du schon gesprochen hast.

**Files:**
- Modify: `BlitztextMac/Services/VaultInboxDocument.swift`
- Test: `BlitztextMac/Tests/VaultInboxDocumentAppendTests.swift`

**Interfaces:**
- Consumes: `VaultInboxDocument.section`, `effectiveDate`, `isoDay`
- Produces:
  - `static func updatingFrontmatterDate(in content: String, to isoDay: String) -> String`
  - `static func appended(to existing: String, text: String, recordedAt: Date, calendar: Calendar) -> String`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

`BlitztextMac/Tests/VaultInboxDocumentAppendTests.swift`:

```swift
import XCTest

final class VaultInboxDocumentAppendTests: XCTestCase {
    private let calendar = TestCalendar.berlin

    private let bestehendMitFrontmatter = """
    ---
    typ: log
    status: aktiv
    topf: inbox
    sphaere: beruf
    themen: []
    quelle: gespräch
    stichworte: [diktat, schnellerfassung]
    erstellt: 2026-09-04
    aktualisiert: 2026-09-04
    geprüft:
    ---

    <!-- diktat: offen -->

    # Diktate 04.09.2026

    ## 09:42
    Erster Gedanke.

    """

    func testAnhaengenErgaenztDenZweitenAbschnitt() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasSuffix("## 09:42\nErster Gedanke.\n\n## 14:07\nZweiter Gedanke.\n"))
    }

    func testAnhaengenLaesstKopfUndMarkerUnberuehrt() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasPrefix("---\ntyp: log\n"))
        XCTAssertEqual(ergebnis.components(separatedBy: "<!-- diktat: offen -->").count - 1, 1)
        XCTAssertEqual(ergebnis.components(separatedBy: "# Diktate 04.09.2026").count - 1, 1)
        XCTAssertTrue(ergebnis.contains("stichworte: [diktat, schnellerfassung]"))
        XCTAssertTrue(ergebnis.contains("topf: inbox"))
    }

    func testAnhaengenSetztAktualisiertUndLaesstErstelltStehen() {
        let ergebnis = VaultInboxDocument.appended(
            to: bestehendMitFrontmatter,
            text: "Nachtrag am naechsten Tag.",
            recordedAt: TestCalendar.date(2026, 9, 5, 10, 0),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.contains("erstellt: 2026-09-04"))
        XCTAssertTrue(ergebnis.contains("aktualisiert: 2026-09-05"))
    }

    /// Der wichtigste Test dieses Tasks: eine Zeile im Diktattext, die wie
    /// Frontmatter aussieht, darf nicht angefasst werden.
    func testZeileImTextDieWieFrontmatterAussiehtBleibtUnberuehrt() {
        let bestehend = """
        ---
        typ: log
        aktualisiert: 2026-09-04
        ---

        # Diktate 04.09.2026

        ## 09:42
        aktualisiert: 2020-01-01 hatte im alten Vault noch gestimmt.

        """

        let ergebnis = VaultInboxDocument.appended(
            to: bestehend,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 5, 10, 0),
            calendar: calendar
        )

        // Diese Zeile beginnt mit "aktualisiert:", liegt aber ausserhalb des
        // Frontmatter-Blocks. Sie muss unangetastet bleiben.
        XCTAssertTrue(ergebnis.contains("aktualisiert: 2020-01-01 hatte im alten Vault noch gestimmt."))
        XCTAssertTrue(ergebnis.hasPrefix("---\ntyp: log\naktualisiert: 2026-09-05\n---"))
    }

    func testDateiOhneFrontmatterBekommtKeinesDazu() {
        let bestehend = """
        # Diktate 04.09.2026

        ## 09:42
        Erster Gedanke.

        """

        let ergebnis = VaultInboxDocument.appended(
            to: bestehend,
            text: "Zweiter Gedanke.",
            recordedAt: TestCalendar.date(2026, 9, 4, 14, 7),
            calendar: calendar
        )

        XCTAssertTrue(ergebnis.hasPrefix("# Diktate 04.09.2026"))
        XCTAssertFalse(ergebnis.contains("---"))
        XCTAssertTrue(ergebnis.hasSuffix("## 14:07\nZweiter Gedanke.\n"))
    }

    func testMehrfachesAnhaengenErzeugtGenauEineLeerzeileDazwischen() {
        var inhalt = VaultInboxDocument.newDocument(
            text: "Eins.",
            recordedAt: TestCalendar.date(2026, 9, 4, 9, 0),
            settings: DictationSettings(writesSecondBrainFrontmatter: true),
            calendar: calendar
        )
        inhalt = VaultInboxDocument.appended(
            to: inhalt,
            text: "Zwei.",
            recordedAt: TestCalendar.date(2026, 9, 4, 10, 0),
            calendar: calendar
        )
        inhalt = VaultInboxDocument.appended(
            to: inhalt,
            text: "Drei.",
            recordedAt: TestCalendar.date(2026, 9, 4, 11, 0),
            calendar: calendar
        )

        XCTAssertTrue(inhalt.hasSuffix("## 09:00\nEins.\n\n## 10:00\nZwei.\n\n## 11:00\nDrei.\n"))
        XCTAssertFalse(inhalt.contains("\n\n\n"))
    }

    func testFrontmatterDatumOhneAktualisiertZeileBleibtUnveraendert() {
        let bestehend = "---\ntyp: log\n---\n\n# Diktate 04.09.2026\n"
        let ergebnis = VaultInboxDocument.updatingFrontmatterDate(in: bestehend, to: "2026-09-05")
        XCTAssertEqual(ergebnis, bestehend)
    }

    func testTextOhneFrontmatterBlockBleibtUnveraendert() {
        let bestehend = "# Diktate 04.09.2026\n\n## 09:42\naktualisiert: 2020-01-01\n"
        let ergebnis = VaultInboxDocument.updatingFrontmatterDate(in: bestehend, to: "2026-09-05")
        XCTAssertEqual(ergebnis, bestehend)
    }
}
```

- [ ] **Step 2: Test laufen lassen und Fehlschlag bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentAppendTests`
Expected: Uebersetzungsfehler, `has no member 'appended'` und `has no member 'updatingFrontmatterDate'`.

- [ ] **Step 3: `updatingFrontmatterDate` und `appended` ergaenzen**

In `BlitztextMac/Services/VaultInboxDocument.swift` unterhalb von `newDocument` einfuegen, vor der privaten `frontmatter`-Funktion:

```swift
    /// Hängt einen Abschnitt an eine bestehende Tagesdatei. Berührt sonst
    /// nur das Feld `aktualisiert` im Frontmatter. H1 und Marker bleiben, wie
    /// sie sind.
    static func appended(
        to existing: String,
        text: String,
        recordedAt: Date,
        calendar: Calendar
    ) -> String {
        let tag = effectiveDate(for: recordedAt, calendar: calendar)
        let aktualisiert = updatingFrontmatterDate(
            in: existing,
            to: isoDay(tag, calendar: calendar)
        )

        var rumpf = aktualisiert
        while rumpf.hasSuffix("\n") {
            rumpf.removeLast()
        }

        let abschnitt = section(text: text, at: recordedAt, calendar: calendar)
        return "\(rumpf)\n\n\(abschnitt)\n"
    }

    /// Setzt `aktualisiert` ausschließlich innerhalb des ersten `---` bis
    /// `---` Blocks am Dateianfang. Eine Zeile im Diktattext, die wie
    /// Frontmatter aussieht, wird nicht angefasst. Fehlt der Block oder das
    /// Feld, bleibt der Inhalt unverändert.
    static func updatingFrontmatterDate(in content: String, to isoDay: String) -> String {
        var zeilen = content.components(separatedBy: "\n")
        guard zeilen.first == "---" else { return content }
        guard let ende = zeilen.dropFirst().firstIndex(of: "---") else { return content }
        guard ende > 1 else { return content }

        var geaendert = false
        for index in 1..<ende where zeilen[index].hasPrefix("aktualisiert:") {
            zeilen[index] = "aktualisiert: \(isoDay)"
            geaendert = true
        }

        guard geaendert else { return content }
        return zeilen.joined(separator: "\n")
    }
```

- [ ] **Step 4: Test laufen lassen und Erfolg bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxDocumentAppendTests`
Expected: PASS, 8 Tests.

- [ ] **Step 5: Alle bisherigen Tests laufen lassen**

Run: `./test.sh`
Expected: PASS, 26 Tests.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Services/VaultInboxDocument.swift BlitztextMac/Tests/VaultInboxDocumentAppendTests.swift
git commit -m "Diktat: Anhaengen an die Tagesdatei und Frontmatter-Datum"
```

---

### Task 4: VaultInboxService, atomares Schreiben

**Files:**
- Create: `BlitztextMac/Services/VaultInboxService.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)
- Test: `BlitztextMac/Tests/VaultInboxServiceTests.swift`

**Interfaces:**
- Consumes: `VaultInboxDocument.*`, `DictationSettings`
- Produces:
  - `enum VaultInboxError: LocalizedError, Equatable` mit `folderNotConfigured`, `folderMissing(String)`, `notWritable(String)`, `existingFileUnreadable(String)`, `writeFailed(String)`
  - `actor VaultInboxService`, `init(calendar: Calendar = .current, fileManager: FileManager = .default)`
  - `func append(text: String, recordedAt: Date, settings: DictationSettings) throws -> URL`

- [ ] **Step 1: Testziel-Quellen erweitern**

In `BlitztextMac/project.yml` beim Target `BlitztextMacTests` unter `sources:` ergaenzen:

```yaml
      - path: Services/VaultInboxService.swift
```

- [ ] **Step 2: Den fehlschlagenden Test schreiben**

`BlitztextMac/Tests/VaultInboxServiceTests.swift`:

```swift
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
            XCTFail("Es haette ein Fehler kommen muessen.")
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
            XCTFail("Es haette ein Fehler kommen muessen.")
        } catch let fehler as VaultInboxError {
            XCTAssertEqual(fehler, .folderMissing(verschwunden.path))
        } catch {
            XCTFail("Falscher Fehlertyp: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: verschwunden.path))
    }

    func testTildeImPfadWirdAufgeloest() async throws {
        let service = VaultInboxService(calendar: calendar)
        var konfiguration = settings()
        konfiguration.vaultFolderPath = "~"

        // Der Test schreibt bewusst nicht ins Home-Verzeichnis, er prueft nur,
        // dass die Tilde nicht als Ordnername missverstanden wird.
        do {
            _ = try await service.append(
                text: "Gedanke.",
                recordedAt: TestCalendar.date(2026, 9, 4, 9, 42),
                settings: konfiguration
            )
            let ziel = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("2026-09-04-diktat.md")
            try? FileManager.default.removeItem(at: ziel)
        } catch let fehler as VaultInboxError {
            XCTAssertNotEqual(fehler, .folderMissing("~"))
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
            XCTFail("Es haette ein Fehler kommen muessen.")
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
```

- [ ] **Step 3: Test laufen lassen und Fehlschlag bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxServiceTests`
Expected: Uebersetzungsfehler, `cannot find 'VaultInboxService' in scope`.

- [ ] **Step 4: `VaultInboxService.swift` schreiben**

`BlitztextMac/Services/VaultInboxService.swift`:

```swift
import Foundation

enum VaultInboxError: LocalizedError, Equatable {
    case folderNotConfigured
    case folderMissing(String)
    case notWritable(String)
    case existingFileUnreadable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotConfigured:
            return "Kein Ablageordner eingestellt."
        case .folderMissing(let pfad):
            return "Ablageordner nicht gefunden: \(pfad)"
        case .notWritable(let pfad):
            return "Ablageordner ist nicht beschreibbar: \(pfad)"
        case .existingFileUnreadable(let pfad):
            return "Bestehende Tagesdatei ist nicht lesbar: \(pfad)"
        case .writeFailed(let grund):
            return "Schreiben fehlgeschlagen: \(grund)"
        }
    }
}

/// Schreibt Diktate in die Tagesdatei des eingestellten Ordners.
///
/// Ein `actor`, damit zwei Diktate kurz hintereinander nacheinander schreiben
/// und sich nicht überschreiben. Geschrieben wird immer atomar: Inhalt in eine
/// Nachbardatei, dann umbenennen. Nie in die offene Datei hinein.
actor VaultInboxService {
    private let calendar: Calendar
    private let fileManager: FileManager

    init(calendar: Calendar = .current, fileManager: FileManager = .default) {
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// Hängt ein Diktat an die Tagesdatei seines wirksamen Datums an und
    /// liefert die geschriebene Datei zurück.
    func append(text: String, recordedAt: Date, settings: DictationSettings) throws -> URL {
        let ordner = try resolvedFolder(settings.vaultFolderPath)
        let tag = VaultInboxDocument.effectiveDate(for: recordedAt, calendar: calendar)
        let ziel = ordner.appendingPathComponent(
            VaultInboxDocument.fileName(for: tag, calendar: calendar)
        )

        let existiert = fileManager.fileExists(atPath: ziel.path)
        let inhalt: String

        if existiert {
            guard let bestehend = try? String(contentsOf: ziel, encoding: .utf8) else {
                throw VaultInboxError.existingFileUnreadable(ziel.path)
            }
            inhalt = VaultInboxDocument.appended(
                to: bestehend,
                text: text,
                recordedAt: recordedAt,
                calendar: calendar
            )
        } else {
            inhalt = VaultInboxDocument.newDocument(
                text: text,
                recordedAt: recordedAt,
                settings: settings,
                calendar: calendar
            )
        }

        try writeAtomically(inhalt, to: ziel, replacingExisting: existiert, in: ordner)
        return ziel
    }

    /// Der eingestellte Ordner wird nie angelegt. Ein umbenannter oder nicht
    /// eingebundener Vault soll auffallen und nicht heimlich einen leeren
    /// Zwilling bekommen.
    private func resolvedFolder(_ pfad: String) throws -> URL {
        let getrimmt = pfad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getrimmt.isEmpty else { throw VaultInboxError.folderNotConfigured }

        let aufgeloest = (getrimmt as NSString).expandingTildeInPath
        let ordner = URL(fileURLWithPath: aufgeloest, isDirectory: true)

        var istOrdner: ObjCBool = false
        guard fileManager.fileExists(atPath: ordner.path, isDirectory: &istOrdner),
              istOrdner.boolValue else {
            throw VaultInboxError.folderMissing(ordner.path)
        }
        guard fileManager.isWritableFile(atPath: ordner.path) else {
            throw VaultInboxError.notWritable(ordner.path)
        }
        return ordner
    }

    private func writeAtomically(
        _ inhalt: String,
        to ziel: URL,
        replacingExisting: Bool,
        in ordner: URL
    ) throws {
        let temp = ordner.appendingPathComponent(
            ".\(ziel.lastPathComponent).tmp-\(UUID().uuidString)"
        )

        do {
            try inhalt.write(to: temp, atomically: false, encoding: .utf8)
            if replacingExisting {
                _ = try fileManager.replaceItemAt(ziel, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: ziel)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw VaultInboxError.writeFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Test laufen lassen und Erfolg bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/VaultInboxServiceTests`
Expected: PASS, 9 Tests.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/project.yml BlitztextMac/Services/VaultInboxService.swift BlitztextMac/Tests/VaultInboxServiceTests.swift
git commit -m "Diktat: VaultInboxService mit atomarem Schreiben"
```

---

### Task 5: Warteschlange

**Files:**
- Create: `BlitztextMac/Services/DictationQueueStore.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)
- Modify: `BlitztextMac/Services/AppSupportPaths.swift`
- Test: `BlitztextMac/Tests/DictationQueueStoreTests.swift`

**Interfaces:**
- Consumes: `VaultInboxService.append`, `DictationSettings`
- Produces:
  - `struct QueuedDictation: Codable, Equatable` mit `recordedAt: Date`, `text: String`
  - `actor DictationQueueStore`, `init(fileURL: URL, fileManager: FileManager = .default)`
  - `func enqueue(_ item: QueuedDictation) throws`
  - `func pending() throws -> [QueuedDictation]`
  - `func flush(using service: VaultInboxService, settings: DictationSettings) async -> DictationQueueStore.FlushResult`
  - `struct FlushResult: Equatable` mit `written: Int`, `remaining: Int`, `stoppedBecause: String?` (Vorgabe nil)
  - `enum DictationQueueError: LocalizedError, Equatable` mit `queueFileUnreadable(String)`
  - `AppSupportPaths.dictationQueueURL: URL`

- [ ] **Step 1: Testziel-Quellen erweitern**

In `BlitztextMac/project.yml` beim Target `BlitztextMacTests` unter `sources:` ergaenzen:

```yaml
      - path: Services/DictationQueueStore.swift
```

`AppSupportPaths.swift` kommt bewusst **nicht** dazu. Der Store bekommt seine Datei-URL uebergeben, damit die Tests nicht in das echte Application-Support-Verzeichnis schreiben.

- [ ] **Step 2: Den fehlschlagenden Test schreiben**

`BlitztextMac/Tests/DictationQueueStoreTests.swift`:

```swift
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

    func testLeereWarteschlangeOhneDatei() async {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        let offen = await store.pending()
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
        let offen = await zweiterStore.pending()
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
        let offen = await store.pending()
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

        XCTAssertEqual(ergebnis, DictationQueueStore.FlushResult(written: 0, remaining: 1))
        let offen = await store.pending()
        XCTAssertEqual(offen, [eintrag])
    }

    func testNachziehenArbeitetAeltesteZuerst() async throws {
        let store = DictationQueueStore(fileURL: warteschlangeURL)
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 16, 0),
            text: "Spaeter."
        ))
        try await store.enqueue(QueuedDictation(
            recordedAt: TestCalendar.date(2026, 9, 4, 8, 0),
            text: "Frueher."
        ))

        let service = VaultInboxService(calendar: calendar)
        _ = await store.flush(using: service, settings: settings)

        let text = try String(
            contentsOf: vaultOrdner.appendingPathComponent("2026-09-04-diktat.md"),
            encoding: .utf8
        )
        let indexFrueher = text.range(of: "Frueher.")!.lowerBound
        let indexSpaeter = text.range(of: "Spaeter.")!.lowerBound
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
}
```

> **Nachtrag nach dem Review dieses Tasks.** Der hier abgedruckte Code hatte
> zwei Defekte, die das Review gefunden hat und die im Repo behoben sind:
>
> 1. `pending()` lieferte `[]`, wenn die Warteschlangendatei vorhanden aber
>    nicht dekodierbar war. Weil `enqueue` erst `pending()` liest und danach
>    schreibt, ersetzte der naechste Eintrag eine beschaedigte Datei durch
>    sich selbst und alle vorher gesicherten Diktate waren weg. `pending()`
>    ist jetzt `throws` und wirft in diesem Fall
>    `DictationQueueError.queueFileUnreadable`. `[]` bedeutet nur noch: es
>    gibt keine Datei.
> 2. `try? persist(offen)` am Ende von `flush` verschluckte einen Fehler.
>    Geschriebene Eintraege blieben dann als offen in der Datei stehen und
>    wurden beim naechsten Durchlauf ein zweites Mal in die Tagesdatei
>    geschrieben. Persistiert wird jetzt nach jedem einzelnen erfolgreichen
>    Schreibvorgang, und der Durchlauf bricht ab, wenn das misslingt. Das
>    Duplikatfenster sinkt damit auf hoechstens einen Eintrag. Vollstaendig
>    verhindern liesse sich Duplizierung nur mit einer Schreibmarke in der
>    Tagesdatei, was ein neues Konzept waere und nicht in der Spec steht.
>
> Dazu kam `FlushResult.stoppedBecause: String?`, damit ein vorzeitiger
> Abbruch nicht stumm bleibt. Drei Tests sichern das ab, die Klasse hat
> dadurch 10 statt 7 Tests und die Suite 45 statt 42.

> **Zweiter Nachtrag, aus dem Abschlussreview des Branches.** Auch die
> ueberarbeitete Fassung hatte noch einen Verlustpfad, den keines der neun
> Task-Reviews gesehen hat: Swift-Actors sind an Suspendierungspunkten
> reentrant. `flush` las die Liste in eine lokale Variable, wartete dann auf
> `service.append` (Wechsel in einen anderen actor, also ein echter
> Suspendierungspunkt) und persistierte danach den veralteten Schnappschuss.
> Ein `enqueue`, das waehrend dieser Suspendierung lief, wurde damit
> ueberschrieben, und sein Diktat war weg, ohne je im Vault gelandet zu sein.
> Erreichbar im Normalbetrieb, weil `AppState.init()` beim Start einen
> Durchlauf startet und `writeToVaultInbox` vor jedem Schreiben selbst einen.
>
> Behoben durch zwei Aenderungen: nach jedem erfolgreichen Schreiben wird die
> Liste neu von der Platte gelesen und der geschriebene Eintrag per Gleichheit
> statt per Index entfernt, und eine Sperre im actor verhindert ueberlappende
> Durchlaeufe. Zwei Tests mit je 150 gleichzeitigen Durchlaeufen sichern das
> ab; beide fallen unter Sabotage der alten Fassung durch. Die Suite hat
> dadurch 47 statt 45 Tests.

- [ ] **Step 3: Test laufen lassen und Fehlschlag bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/DictationQueueStoreTests`
Expected: Uebersetzungsfehler, `cannot find 'DictationQueueStore' in scope` und `cannot find 'QueuedDictation' in scope`.

- [ ] **Step 4: `DictationQueueStore.swift` schreiben**

`BlitztextMac/Services/DictationQueueStore.swift`:

```swift
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
```

- [ ] **Step 5: Pfad der Warteschlangendatei in `AppSupportPaths` ergaenzen**

In `BlitztextMac/Services/AppSupportPaths.swift` nach `settingsURL` einfuegen:

```swift
    static var dictationQueueURL: URL {
        appSupportDirectoryURL.appendingPathComponent("dictation-queue.json")
    }
```

- [ ] **Step 6: Test laufen lassen und Erfolg bestaetigen**

Run: `./test.sh -only-testing:BlitztextMacTests/DictationQueueStoreTests`
Expected: PASS, 12 Tests.

- [ ] **Step 7: Alle Tests laufen lassen**

Run: `./test.sh`
Expected: PASS, 47 Tests.

- [ ] **Step 8: Commit**

```bash
git add BlitztextMac/project.yml BlitztextMac/Services/DictationQueueStore.swift BlitztextMac/Services/AppSupportPaths.swift BlitztextMac/Tests/DictationQueueStoreTests.swift
git commit -m "Diktat: Warteschlange fuer fehlgeschlagene Schreibvorgaenge"
```

---

### Task 6: Workflow-Typ, Ausgabeziel, Hotkey, Info.plist

Ab hier gibt es keine Unit-Tests mehr, weil alles Weitere an `AppState`, AppKit und dem UI haengt. Geprueft wird mit `./build.sh` und danach von Hand.

**Files:**
- Modify: `BlitztextMac/Features/Workflows/WorkflowProtocol.swift`
- Modify: `BlitztextMac/Services/HotkeyService.swift:73-119`
- Modify: `BlitztextMac/App/MenuBarStatusController.swift` (fuenf switch-Anweisungen)
- Modify: `BlitztextMac/Resources/Info.plist`

**Interfaces:**
- Consumes: nichts
- Produces:
  - `WorkflowType.vaultDictation`
  - `enum WorkflowOutputDestination { case cursor, vaultInbox }`
  - `WorkflowType.outputDestination: WorkflowOutputDestination`

- [ ] **Step 1: `WorkflowType` erweitern**

In `BlitztextMac/Features/Workflows/WorkflowProtocol.swift` den neuen Fall in `enum WorkflowType` nach `case localTranscription` einfuegen:

```swift
    case vaultDictation
```

Und in jedem `switch` desselben Enums einen Fall ergaenzen:

```swift
    // displayName
        case .vaultDictation: return "Blitztext Notiz"

    // icon
        case .vaultDictation: return "tray.and.arrow.down.fill"

    // subtitle
        case .vaultDictation: return "Gedanke rein. Inbox raus."

    // hotkeyLabel
        case .vaultDictation: return "fn + Shift + Option"

    // accentColor
        case .vaultDictation: return "indigo"
```

`mainMenuCases` bleibt unveraendert, es filtert nur `.localTranscription` heraus, `vaultDictation` erscheint damit automatisch im Menue und in der Kuerzel-Liste der Einstellungen.

- [ ] **Step 2: Ausgabeziel ergaenzen**

Ebenfalls in `WorkflowProtocol.swift`, direkt vor `// MARK: - Workflow State`:

```swift
// MARK: - Output Destination

/// Wohin das Ergebnis eines Workflows geht. Alle bisherigen Workflows setzen
/// den Text am Cursor ein, das Diktat schreibt in die Tagesdatei im Vault.
enum WorkflowOutputDestination {
    case cursor
    case vaultInbox
}

extension WorkflowType {
    var outputDestination: WorkflowOutputDestination {
        switch self {
        case .vaultDictation: return .vaultInbox
        case .transcription, .localTranscription, .textImprover, .dampfAblassen, .emojiText:
            return .cursor
        }
    }
}
```

Der `switch` ist absichtlich ausgeschrieben und nicht mit `default` abgekuerzt: ein kuenftiger Workflow soll hier einen Uebersetzungsfehler ausloesen und eine Entscheidung erzwingen, statt still am Cursor zu landen.

- [ ] **Step 3: Hotkey ergaenzen**

In `BlitztextMac/Services/HotkeyService.swift` in `handleFlags`, **vor** dem bestehenden Block fuer `[.function, .shift]` einfuegen:

```swift
        // fn + Shift + Option -> Diktat in die Tagesdatei
        if flags == [.function, .shift, .option] {
            if activeCombo == nil {
                activeCombo = .vaultDictation
                onHotkeyEvent?(.down(.vaultDictation))
            }
            return
        }
```

Die Reihenfolge ist entscheidend: die Pruefung laeuft auf genaue Flag-Gleichheit, und die spezifischere Kombi muss zuerst geprueft werden. Dieselbe Regel gilt schon fuer fn + Shift + Control in `HotkeyService.swift:74`.

- [ ] **Step 4: `Info.plist` ergaenzen**

In `BlitztextMac/Resources/Info.plist` nach dem Block `NSMicrophoneUsageDescription` einfuegen:

```xml
	<key>NSDocumentsFolderUsageDescription</key>
	<string>Blitztext schreibt dein Diktat in den Ordner, den du dafür eingestellt hast.</string>
```

Ohne diesen Text verweigert macOS den Zugriff auf einen Ordner unter `~/Documents`, und dort liegt der typische Vault.

- [ ] **Step 5: `MenuBarStatusController` ergaenzen**

`BlitztextMac/App/MenuBarStatusController.swift` hat fuenf vollstaendige `switch`-Anweisungen ueber `WorkflowType`. Das Diktat ist eine Transkription, es bekommt deshalb dieselben Animationswerte, aber ein eigenes Symbol.

An vier Stellen wird `.vaultDictation` in die bestehende Gruppe aufgenommen:

- `MenuBarStatusController.swift:184` und `:198` (die beiden Bloecke innerhalb von `switch phase`)
- in `recordingAlphaValues(for:frame:)`
- in `processingAlphaValues(for:frame:)`

Jeweils aus

```swift
            case .transcription, .localTranscription:
```

wird

```swift
            case .transcription, .localTranscription, .vaultDictation:
```

Und in `badgeSymbol(for:)` kommt ein eigener Fall dazu, damit in der Menueleiste zu sehen ist, dass in die Inbox geschrieben wird:

```swift
        case .vaultDictation:
            return "tray.and.arrow.down.fill"
```

- [ ] **Step 6: Bauen und Vollstaendigkeit der switch-Anweisungen pruefen**

Run: `./build.sh`
Expected: Build erfolgreich. Kommen Fehler der Form `switch must be exhaustive`, fehlt in `AppState.swift` oder `SettingsContentView.swift` ein Fall fuer `.vaultDictation`. Diese Stellen bekommen in Task 7 und Task 9 ihren Inhalt; damit der Build jetzt durchlaeuft, dort vorlaeufig denselben Zweig wie `.transcription` benutzen und in Task 7 ersetzen.

- [ ] **Step 7: Tests laufen lassen, damit nichts zurueckgefallen ist**

Run: `./test.sh`
Expected: PASS, 47 Tests.

- [ ] **Step 8: Commit**

```bash
git add BlitztextMac/Features/Workflows/WorkflowProtocol.swift BlitztextMac/Services/HotkeyService.swift BlitztextMac/App/MenuBarStatusController.swift BlitztextMac/Resources/Info.plist BlitztextMac/App/AppState.swift BlitztextMac/Features/Settings/SettingsContentView.swift
git commit -m "Diktat: Workflow-Typ, Ausgabeziel und Kuerzel fn+Shift+Option"
```

---

### Task 7: AppState verdrahten

**Files:**
- Modify: `BlitztextMac/App/AppState.swift`

**Interfaces:**
- Consumes: `DictationSettings`, `VaultInboxService`, `DictationQueueStore`, `QueuedDictation`, `AppSupportPaths.dictationQueueURL`, `WorkflowType.outputDestination`
- Produces:
  - `AppState.dictationSettings: DictationSettings`
  - `AppState.dictationQueueCount: Int`
  - `AppState.vaultFolderConfigured: Bool`
  - `AppState.flushDictationQueue()`
  - `AppState.setVaultFolder(_ url: URL)`

- [ ] **Step 1: Einstellungen aufnehmen und laden**

In `BlitztextMac/App/AppState.swift`:

Bei den persistierten Einstellungen, nach `emojiTextSettings`:

```swift
    var dictationSettings: DictationSettings {
        didSet { saveSettings() }
    }
```

In `init()` nach `self.emojiTextSettings = Self.loadEmojiTextSettings()`:

```swift
        self.dictationSettings = Self.loadDictationSettings()
```

Bei den Ladefunktionen, nach `loadEmojiTextSettings`:

```swift
    private static func loadDictationSettings() -> DictationSettings {
        loadContainer()?.dictation ?? DictationSettings()
    }
```

In `saveSettings()` den Container erweitern:

```swift
        let container = SettingsContainer(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            dampfAblassen: dampfAblassenSettings,
            emojiText: emojiTextSettings,
            dictation: dictationSettings
        )
```

Und `SettingsContainer` in `AppState.swift:621` erweitern:

```swift
private struct SettingsContainer: Codable {
    var app: AppSettings?
    var transcription: TranscriptionSettings
    var textImprovement: TextImprovementSettings
    var dampfAblassen: DampfAblassenSettings?
    var emojiText: EmojiTextSettings?
    var dictation: DictationSettings?
}
```

Das Feld ist optional, damit eine bestehende `settings.json` ohne diesen Abschnitt weiter laedt.

- [ ] **Step 2: Dienste und Zaehler anlegen**

Bei den Eigenschaften von `AppState`, nach `let hotkeyService = HotkeyService()`:

```swift
    // Diktat
    private let vaultInboxService = VaultInboxService()
    private let dictationQueue = DictationQueueStore(fileURL: AppSupportPaths.dictationQueueURL)
    var dictationQueueCount = 0
```

- [ ] **Step 3: Verfuegbarkeit ergaenzen**

In `isWorkflowAvailable` den vorlaeufigen Zweig aus Task 6 ersetzen:

```swift
        case .vaultDictation:
            guard vaultFolderConfigured else { return false }
            return appSettings.secureLocalModeEnabled
                ? selectedLocalModelIsInstalled
                : remoteProviderConfigured
```

Und bei den berechneten Eigenschaften:

```swift
    var vaultFolderConfigured: Bool {
        !dictationSettings.vaultFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
```

- [ ] **Step 4: Workflow erzeugen**

In `startWorkflow` den vorlaeufigen Zweig aus Task 6 ersetzen:

```swift
        case .vaultDictation:
            let workflow = TranscriptionWorkflow(
                type: .vaultDictation,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: appSettings.secureLocalModeEnabled ? .local : .remote,
                localModelName: selectedLocalModelName,
                apiConfiguration: apiConfiguration
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()
```

- [ ] **Step 5: Untertitel im Menue ergaenzen**

In `workflowSubtitle(for:)` einen Fall ergaenzen, damit die Menuezeile sagt, wohin geschrieben wird:

```swift
        case .vaultDictation:
            guard vaultFolderConfigured else {
                return "Kein Ablageordner eingestellt."
            }
            let ordner = URL(fileURLWithPath: dictationSettings.vaultFolderPath).lastPathComponent
            return "In die Tagesdatei in \(ordner)."
```

- [ ] **Step 6: Ausgabe verzweigen**

`handleWorkflowOutput` ersetzen:

```swift
    private func handleWorkflowOutput(_ text: String) {
        let destination = activeWorkflow?.type.outputDestination ?? .cursor

        switch destination {
        case .cursor:
            pasteAtCursor(text, target: activePasteTarget)
        case .vaultInbox:
            // Bewusst kein pasteAtCursor: es darf kein Text in ein fremdes
            // Fenster rutschen.
            writeToVaultInbox(text)
        }

        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
        scheduleWorkflowCleanup(after: 1.05)
    }
```

- [ ] **Step 7: Schreibpfad und Fehlerbehandlung ergaenzen**

Neuer Abschnitt in `AppState`, direkt unter `handleWorkflowOutput`:

```swift
    // MARK: - Diktat in den Vault

    private func writeToVaultInbox(_ text: String) {
        let settings = dictationSettings
        let recordedAt = Date()

        Task { [weak self] in
            guard let self else { return }

            // Vor jedem neuen Schreiben nachziehen, damit die Reihenfolge
            // stimmt und liegengebliebene Gedanken nicht verhungern.
            let vorlauf = await self.dictationQueue.flush(
                using: self.vaultInboxService,
                settings: settings
            )

            do {
                let ziel = try await self.vaultInboxService.append(
                    text: text,
                    recordedAt: recordedAt,
                    settings: settings
                )
                await self.finishVaultWrite(
                    text: text,
                    fileName: ziel.lastPathComponent,
                    queueRemaining: vorlauf.remaining
                )
            } catch {
                await self.handleVaultWriteFailure(
                    text: text,
                    recordedAt: recordedAt,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func finishVaultWrite(text: String, fileName: String, queueRemaining: Int) async {
        dictationQueueCount = queueRemaining
        UserNotificationService.notifyDictationSaved(preview: text, fileName: fileName)
    }

    private func handleVaultWriteFailure(text: String, recordedAt: Date, reason: String) async {
        // Zwischenablage zuerst: sie ist sofort greifbar, auch wenn das
        // Ablegen in die Warteschlange scheitert.
        copyToClipboard(text)

        try? await dictationQueue.enqueue(
            QueuedDictation(recordedAt: recordedAt, text: text)
        )
        dictationQueueCount = (try? await dictationQueue.pending())?.count ?? dictationQueueCount

        menuBarStatus = .error(.vaultDictation)
        UserNotificationService.notifyDictationFailed(reason: reason)
    }

    /// Zieht liegengebliebene Diktate nach. Aufgerufen beim Start und von der
    /// Schaltfläche in den Einstellungen.
    func flushDictationQueue() {
        let settings = dictationSettings
        Task { [weak self] in
            guard let self else { return }
            let ergebnis = await self.dictationQueue.flush(
                using: self.vaultInboxService,
                settings: settings
            )
            self.dictationQueueCount = ergebnis.remaining
        }
    }

    func refreshDictationQueueCount() {
        Task { [weak self] in
            guard let self else { return }
            // Ist die Warteschlangendatei beschaedigt, bleibt der letzte
            // bekannte Zaehler stehen. Ein stilles 0 waere die falsche
            // Auskunft, denn die Eintraege sind ja noch da.
            if let offen = try? await self.dictationQueue.pending() {
                self.dictationQueueCount = offen.count
            }
        }
    }

    func setVaultFolder(_ url: URL) {
        dictationSettings.vaultFolderPath = url.path
    }
```

- [ ] **Step 8: Beim Start nachziehen**

Am Ende von `init()`:

```swift
        if !dictationSettings.vaultFolderPath.isEmpty {
            flushDictationQueue()
        } else {
            refreshDictationQueueCount()
        }
```

- [ ] **Step 9: Bauen**

Run: `./build.sh`
Expected: Build erfolgreich. `UserNotificationService` fehlt noch, deshalb bricht der Build mit `cannot find 'UserNotificationService' in scope` ab. Das ist erwartet, Task 8 legt die Datei an. Um diesen Task einzeln abzuschliessen, die beiden `UserNotificationService`-Zeilen vorlaeufig auskommentieren, bauen, und in Task 8 wieder einsetzen.

- [ ] **Step 10: Tests laufen lassen**

Run: `./test.sh`
Expected: PASS, 47 Tests.

- [ ] **Step 11: Commit**

```bash
git add BlitztextMac/App/AppState.swift
git commit -m "Diktat: AppState verdrahtet Ausgabeziel, Einstellungen und Warteschlange"
```

---

### Task 8: Benachrichtigungen

**Files:**
- Create: `BlitztextMac/Services/UserNotificationService.swift`
- Modify: `BlitztextMac/App/AppState.swift`

**Interfaces:**
- Consumes: nichts
- Produces:
  - `enum UserNotificationService` mit `static func requestAuthorizationIfNeeded() async -> Bool`, `static func authorizationDenied() async -> Bool`, `static func notifyDictationSaved(preview: String, fileName: String)`, `static func notifyDictationFailed(reason: String)`
  - `AppState.notificationsDenied: Bool`

- [ ] **Step 1: `UserNotificationService.swift` schreiben**

`BlitztextMac/Services/UserNotificationService.swift`:

```swift
import Foundation
import UserNotifications
import OSLog

private let notificationLogger = Logger(subsystem: "app.blitztext.mac", category: "Notifications")

/// Rückmeldung nach einem Diktat. Ohne sichtbare Bestätigung weiß niemand, ob
/// die Zeile angekommen ist, und ein stilles Verschlucken darf es nicht geben.
enum UserNotificationService {
    private static let previewLength = 100

    /// Wird erst beim ersten Diktat aufgerufen, nicht beim App-Start. Wer den
    /// Kanal nicht benutzt, sieht kein Prompt.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                notificationLogger.error(
                    "Benachrichtigungsfreigabe fehlgeschlagen: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        case .denied:
            return false
        default:
            return true
        }
    }

    static func authorizationDenied() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    static func notifyDictationSaved(preview: String, fileName: String) {
        post(
            title: "Diktat gespeichert",
            subtitle: fileName,
            body: shortened(preview)
        )
    }

    static func notifyDictationFailed(reason: String) {
        post(
            title: "Diktat nicht gespeichert",
            subtitle: nil,
            body: "\(reason) Der Text liegt in der Zwischenablage."
        )
    }

    private static func shortened(_ text: String) -> String {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard roh.count > previewLength else { return roh }
        return String(roh.prefix(previewLength)) + " ..."
    }

    private static func post(title: String, subtitle: String?, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                notificationLogger.error(
                    "Benachrichtigung konnte nicht gezeigt werden: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
```

- [ ] **Step 2: Freigabe beim Start des Diktats anfragen**

In `BlitztextMac/App/AppState.swift` in `startWorkflow`, im Zweig `case .vaultDictation`, direkt vor `workflow.start()`:

```swift
            Task { await UserNotificationService.requestAuthorizationIfNeeded() }
```

- [ ] **Step 3: Zustand fuer den Hinweis in den Einstellungen ergaenzen**

Bei den Eigenschaften von `AppState`:

```swift
    var notificationsDenied = false
```

Und eine Funktion neben `refreshDictationQueueCount`:

```swift
    func refreshNotificationPermission() {
        Task { [weak self] in
            guard let self else { return }
            self.notificationsDenied = await UserNotificationService.authorizationDenied()
        }
    }
```

- [ ] **Step 4: Die in Task 7 auskommentierten Aufrufe wieder einsetzen**

In `finishVaultWrite` und `handleVaultWriteFailure` die Zeilen mit `UserNotificationService.notifyDictationSaved` beziehungsweise `notifyDictationFailed` aktivieren.

- [ ] **Step 5: Bauen**

Run: `./build.sh`
Expected: Build erfolgreich, keine Warnungen zu `UserNotificationService`.

- [ ] **Step 6: Von Hand pruefen**

```bash
./build.sh --install --run
```

Dann in den Einstellungen einen Ordner setzen (siehe Task 9, bis dahin ersatzweise in `~/Library/Application Support/Blitztext/settings.json` unter `dictation.vaultFolderPath` eintragen und die App neu starten), fn + Shift + Option halten, einen Satz sprechen, loslassen.

Expected: einmalig die Freigabefrage fuer Benachrichtigungen, danach eine Benachrichtigung "Diktat gespeichert" mit Dateinamen und den ersten Woertern, und die Tagesdatei liegt im Ordner.

- [ ] **Step 7: Commit**

```bash
git add BlitztextMac/Services/UserNotificationService.swift BlitztextMac/App/AppState.swift
git commit -m "Diktat: Systembenachrichtigung fuer Erfolg und Fehler"
```

---

### Task 9: Einstellungen im UI

**Files:**
- Modify: `BlitztextMac/Features/Settings/SettingsContentView.swift`

**Interfaces:**
- Consumes: `AppState.dictationSettings`, `vaultFolderConfigured`, `dictationQueueCount`, `notificationsDenied`, `flushDictationQueue()`, `setVaultFolder(_:)`, `refreshNotificationPermission()`, `DictationSphere`
- Produces: nichts

Umlaute in diesem File als Unicode-Escape, entsprechend der dort vorhandenen Konvention.

- [ ] **Step 1: Abschnitt "Diktat" in `CustomizeSettingsView` einfuegen**

In `BlitztextMac/Features/Settings/SettingsContentView.swift` in `CustomizeSettingsView.body`, nach dem Abschnitt `// MARK: Tastenkuerzel` und vor `// MARK: Blitztext+`:

```swift
            // MARK: Diktat
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Diktat")

                Text("fn + Shift + Option h\u{00E4}lt einen Gedanken in einer Tagesdatei fest, statt ihn am Cursor einzusetzen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ablageordner")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(appState.vaultFolderConfigured
                             ? appState.dictationSettings.vaultFolderPath
                             : "Kein Ordner gew\u{00E4}hlt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(appState.vaultFolderConfigured ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Ordner w\u{00E4}hlen") {
                            chooseVaultFolder()
                        }
                        .font(.system(size: 11))
                    }
                }

                Toggle("Second-Brain-Frontmatter schreiben", isOn: $appState.dictationSettings.writesSecondBrainFrontmatter)
                    .toggleStyle(.switch)
                    .font(.system(size: 11.5))

                if appState.dictationSettings.writesSecondBrainFrontmatter {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sph\u{00E4}re")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $appState.dictationSettings.sphere) {
                            ForEach(DictationSphere.allCases) { sphere in
                                Text(sphere.displayName).tag(sphere)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if appState.dictationQueueCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(appState.dictationQueueCount == 1
                             ? "1 Diktat wartet auf die Ablage."
                             : "\(appState.dictationQueueCount) Diktate warten auf die Ablage.")
                            .font(.system(size: 11))
                        Spacer()
                        Button("Jetzt nachziehen") {
                            appState.flushDictationQueue()
                        }
                        .font(.system(size: 11))
                    }
                }

                if appState.notificationsDenied {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Benachrichtigungen sind aus. Die Best\u{00E4}tigung erscheint dann nur im Men\u{00FC}leisten-Symbol.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
```

- [ ] **Step 2: Ordnerauswahl ergaenzen**

Am Ende von `struct CustomizeSettingsView`, nach `body`:

```swift
    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ausw\u{00E4}hlen"
        panel.message = "Ordner f\u{00FC}r die Diktat-Tagesdateien w\u{00E4}hlen"

        if appState.vaultFolderConfigured {
            panel.directoryURL = URL(fileURLWithPath: appState.dictationSettings.vaultFolderPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setVaultFolder(url)
        appState.flushDictationQueue()
    }
```

Steht `import AppKit` in dieser Datei noch nicht, ergaenzen. `NSOpenPanel` kommt aus AppKit.

- [ ] **Step 3: Berechtigungsstand beim Oeffnen der Einstellungen aktualisieren**

An `CustomizeSettingsView.body` den Modifier anhaengen, hinter dem aeussersten `VStack`:

```swift
        .onAppear {
            appState.refreshNotificationPermission()
            appState.refreshDictationQueueCount()
        }
```

- [ ] **Step 4: Bauen**

Run: `./build.sh`
Expected: Build erfolgreich.

- [ ] **Step 5: Von Hand pruefen**

```bash
./build.sh --install --run
```

Durchgehen:
1. Einstellungen, Tab "Anpassen", Abschnitt "Diktat" ist da.
2. "Ordner waehlen" auf einen Ordner unter `~/Documents` zeigen. macOS fragt einmalig nach Zugriff, die Meldung nennt den Text aus `Info.plist`.
3. Schalter "Second-Brain-Frontmatter schreiben" an, Sphaere erscheint.
4. Popover schliessen, fn + Shift + Option halten, sprechen, loslassen. Benachrichtigung kommt, Datei liegt im Ordner mit Frontmatter.
5. Zweites Diktat: derselbe Tag, zweiter Abschnitt, `aktualisiert` gesetzt, H1 und Marker nur einmal vorhanden.
6. Ordner im Finder umbenennen, nochmal diktieren: Fehlerbenachrichtigung, Text in der Zwischenablage, in den Einstellungen steht "1 Diktat wartet".
7. Ordner zurueckbenennen, "Jetzt nachziehen" druecken: Zeile ist in der Tagesdatei, Hinweis verschwindet.
8. fn + Shift halten und sprechen: Text landet weiter am Cursor und **nicht** im Vault.
9. Sicheren lokalen Modus einschalten, diktieren: funktioniert ebenfalls.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Features/Settings/SettingsContentView.swift
git commit -m "Diktat: Einstellungen fuer Ablageordner, Frontmatter und Sphaere"
```

---

### Task 10: Dokumentation und Gesamtpruefung

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README ergaenzen**

In `README.md` in der Liste unter `## What It Does` nach der Zeile zu `Blitztext :)` ergaenzen:

```markdown
- **Blitztext Notiz**: record a short thought and append it to a dated Markdown file in a folder you choose, instead of pasting at the cursor. Optional Second-Brain-style frontmatter.
```

Und unter `## Important Preview Notes` ergaenzen:

```markdown
- **Blitztext Notiz** needs a target folder in Settings before it becomes available. Files are named `YYYY-MM-DD-diktat.md`, and the day rolls over at 04:00 local time.
```

- [ ] **Step 2: Alle Tests laufen lassen**

Run: `./test.sh`
Expected: PASS, 47 Tests, keine Fehlschlaege.

- [ ] **Step 3: Sauberen Build pruefen**

Run: `./build.sh`
Expected: Build erfolgreich, universelle App wird verifiziert.

- [ ] **Step 4: Nichts Unbeabsichtigtes im Diff**

```bash
git status --short
git diff main --stat
```

Expected: nur die in diesem Plan genannten Dateien. Insbesondere darf `BlitztextMac/BlitztextMac.xcodeproj/` nur so weit geaendert sein, wie `xcodegen generate` es erzeugt, und `.derivedData-blitztextmac-build/` darf nicht auftauchen. Taucht es auf, in `.gitignore` pruefen.

- [ ] **Step 5: Commit und Push**

```bash
git add README.md
git commit -m "Diktat: README um Blitztext Notiz ergaenzt"
git push -u origin feature/diktat-vault-inbox
```

- [ ] **Step 6: Pull Request eröffnen**

```bash
gh pr create --title "Blitztext Notiz: Diktat in eine Tagesdatei" --body "Setzt docs/superpowers/specs/2026-09-04-blitztext-diktat-design.md um. Neuer Workflow fn+Shift+Option schreibt das Transkript als Abschnitt mit Uhrzeit in eine Tagesdatei im eingestellten Ordner, statt es am Cursor einzusetzen. Enthaelt das erste Testziel des Repos.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Selbstpruefung des Plans

**Spec-Abdeckung.** Jede Anforderung der Spec hat einen Task: neuer Workflow-Typ und Ausgabeziel Task 6, Backend-Regel und Verfuegbarkeit Task 7, wirksames Datum und Dateiname Task 1, Abschnitt und neue Datei Task 2, Anhaengen und Frontmatter-Datum Task 3, atomares Schreiben und Fehlertypen Task 4, Warteschlange Task 5, Benachrichtigungen Task 8, `DictationSettings` Task 1 und Task 7, Einstellungs-UI Task 9, Hotkey und `Info.plist` Task 6, Testfaelle Tasks 1 bis 5, README Task 10.

**Nachtrag aus der Selbstpruefung.** `MenuBarStatusController.swift` hat fuenf vollstaendige `switch`-Anweisungen ueber `WorkflowType`, die die Spec nicht erwaehnt. Ohne sie uebersetzt der neue Fall nicht. Sie sind jetzt Task 6 Step 5.

**Nicht abgedeckt und bewusst so:** der Verlauf-Tab braucht keine Aenderung, weil `TranscriptionWorkflow` bereits `recordDictationHistory` aufruft und der neue Typ dort automatisch erscheint.

**Reihenfolge-Warnung fuer die Umsetzung.** Task 6 und Task 7 haengen zusammen: Task 6 macht die `switch`-Anweisungen in `AppState` unvollstaendig, Task 7 fuellt sie. Task 7 verweist auf `UserNotificationService` aus Task 8. Beide Stellen sind in den Steps benannt und mit einem Zwischenschritt versehen, damit jeder Task fuer sich baubar bleibt. Wer die Tasks in einer Sitzung durchzieht, kann Task 6 bis 8 auch in einem Rutsch bauen.
