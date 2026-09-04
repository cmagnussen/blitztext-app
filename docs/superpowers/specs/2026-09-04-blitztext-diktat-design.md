# Blitztext Diktat: Schnellerfassung in eine Tagesdatei

Design, Stand 2026-09-04. Umfang: `BlitztextMac`. Der Windows-Teil bleibt
außen vor und bekommt bei Bedarf einen eigenen PR.

Grundlage ist die Notiz `20 Wissen/Schnellerfassung-Konzept.md` im Second
Brain. Sie legt Bedienmuster, Ablageformat und den Zuschnitt "die App bleibt
dumm" fest. Dieses Dokument beschreibt, wie das in Blitztext gebaut wird, und
hält die vier Punkte fest, die die Notiz offen ließ.

## Ziel

Eine Tastenkombination drücken, zwei Sätze sprechen, loslassen. Der
Transkripttext wird als Abschnitt mit Uhrzeit an eine Tagesdatei in einem
eingestellten Ordner angehängt. Kein zweites Fenster, keine Rückfrage, keine
Ablageentscheidung im Moment des Sprechens.

Anders als alle bestehenden Workflows landet der Text **nicht** am Cursor.

## Entscheidungen dieses PR

Die Notiz ließ vier Punkte offen, hier sind sie entschieden:

1. **Ablageordner ist eine Einstellung**, kein fest verdrahteter Pfad. Jeder
   User setzt seinen eigenen Zielordner. Ohne gesetzten Ordner ist der Workflow
   nicht verfügbar.
2. **Kürzel fn + Shift + Option.** Liegt neben dem gewohnten fn + Shift fürs
   Einsetzen am Cursor, ein Finger mehr bedeutet "in die Inbox statt an den
   Cursor".
3. **Rückmeldung als Systembenachrichtigung** mit den ersten Wörtern des
   erkannten Textes. Der Menüleisten-Status bleibt als Rückfall.
4. **Fehlerfall: Warteschlange und Zwischenablage.** Ein fehlgeschlagenes
   Diktat wird lokal vorgehalten und später nachgezogen, der Text liegt
   zusätzlich sofort in der Zwischenablage.

Dazu kommt eine Entscheidung, die die Notiz nicht vorsah: das
Second-Brain-Frontmatter ist **abschaltbar**. Standard ist eine schlichte
Markdown-Tagesdatei. Ein Schalter erzeugt genau das Format aus der Notiz. Grund:
Blitztext ist ein öffentliches Projekt und soll nicht das Schema eines
bestimmten Vaults fest im Quellcode tragen.

## Nicht Teil dieses PR

Entsprechend "die App bleibt dumm" aus der Notiz:

- kein Klassifizieren des Gesagten, keine Auswahl per Menü
- kein Sprachmodell im Moment der Aufnahme
- kein Abschließen der Tagesdatei, der Marker wird nur geschrieben, nie
  geändert. Über das Abschließen entscheidet der Inbox-Sortierer
- keine Todoist-Anbindung, kein Daily Recap
- keine getrennten Kürzel für Notiz, Aufgabe und Entscheidung
- kein Windows, kein MCP-Eingang

## Aufbau

Gewählter Ansatz: neuer Workflow-Typ, der die bestehende
`TranscriptionWorkflow`-Klasse unverändert benutzt, mit einem deklarierten
Ausgabeziel. Verworfen wurden eine Eigenschaft `outputDestination` im
`Workflow`-Protokoll (Änderungen in allen vier Workflow-Klassen für einen
Nutzen, den es heute nicht gibt) und eine eigene Workflow-Klasse (verdoppelt
Aufnahme- und Transkriptionslogik).

### Neuer Workflow-Typ

`WorkflowType.vaultDictation` in `Features/Workflows/WorkflowProtocol.swift`:

| Feld | Wert |
|---|---|
| `displayName` | `Blitztext Notiz` |
| `subtitle` | `Gedanke rein. Inbox raus.` |
| `icon` | `tray.and.arrow.down.fill` |
| `hotkeyLabel` | `fn + Shift + Option` |
| `accentColor` | `indigo` |

Er ist Teil von `mainMenuCases`, erscheint also als Zeile im Menü und lässt
sich auch per Klick starten.

`AppState.startWorkflow` erzeugt für ihn eine `TranscriptionWorkflow` mit
`type: .vaultDictation` und derselben Backend-Regel wie `.transcription`: lokal,
wenn der sichere lokale Modus an ist, sonst über den eingestellten Anbieter.
Weil im Moment der Aufnahme kein Sprachmodell gebraucht wird, funktioniert das
Diktat auch im sicheren lokalen Modus.

`AppState.isWorkflowAvailable` liefert `false`, solange kein Ordner gesetzt ist
oder der Transkriptions-Backend nicht bereit ist. Ein Klick im Menü öffnet
dann wie bei den anderen Workflows die Einstellungen.

### Ausgabeziel

```swift
enum WorkflowOutputDestination {
    case cursor
    case vaultInbox
}
```

`WorkflowType.outputDestination` liefert `.vaultInbox` für `.vaultDictation`
und `.cursor` für alle anderen. `AppState.handleWorkflowOutput` verzweigt
darauf:

- `.cursor`: unverändert `pasteAtCursor(text, target: activePasteTarget)`
- `.vaultInbox`: Schreibpfad anstoßen, **kein** `pasteAtCursor`. Es darf kein
  Text in ein fremdes Fenster rutschen.

Der bestehende Aufräumpfad (`scheduleWorkflowCleanup`, Menüleisten-Status)
gilt für beide Zweige.

Der Verlauf bekommt das Diktat ohne Zutun mit: `TranscriptionWorkflow` ruft am
Ende `recordDictationHistory` auf, der neue Typ erscheint damit im Verlauf-Tab
wie die anderen. Das ist erwünscht, denn so lässt sich die Aufnahme nachhören,
wenn eine Zeile in der Tagesdatei komisch aussieht.

### Neue Dateien

Alle in `BlitztextMac/Services/`:

| Datei | Aufgabe |
|---|---|
| `VaultInboxService.swift` | Tagesdatei bestimmen, anlegen oder anhängen, atomar schreiben |
| `DictationQueueStore.swift` | fehlgeschlagene Diktate vorhalten und nachziehen |
| `UserNotificationService.swift` | Freigabe anfragen, Erfolg und Fehler melden |

`DictationSettings` kommt zu den anderen Workflow-Einstellungen in
`WorkflowProtocol.swift`.

## VaultInboxService

Ein `actor`, damit zwei Diktate kurz hintereinander nacheinander schreiben und
sich nicht überschreiben. Keine eigene Warteschlange dafür nötig.

### Wirksames Datum

Reine Funktion, ohne Dateisystem, damit prüfbar:

```swift
static func effectiveDate(for now: Date, calendar: Calendar) -> Date
```

Stunde kleiner 4 heißt Vortag, ab 04:00 der laufende Tag, in der lokalen
Zeitzone. Ein Diktat um 00:20 landet in der Datei des Vortags. Das wirksame
Datum bestimmt Dateinamen, H1 sowie `erstellt` und `aktualisiert`.

### Dateiname

`<Ordner>/YYYY-MM-DD-diktat.md`, gebildet aus dem wirksamen Datum. Der
`DateFormatter` benutzt `Locale(identifier: "en_US_POSIX")` und die lokale
Zeitzone, damit kein Gebietsschema die Ziffern verändert.

### Abschnitt

Für beide Fälle identisch:

```markdown
## HH:MM
Roher Transkripttext, unverändert.
```

Die Uhrzeit ist die tatsächliche Uhrzeit, nicht die des wirksamen Datums.
Zwischen zwei Abschnitten steht genau eine Leerzeile.

### Fall 1: Datei nicht vorhanden

Mit eingeschaltetem Frontmatter genau die Felder aus der Notiz:

```markdown
---
typ: log
status: aktiv
topf: inbox
sphaere: <Einstellung, Vorgabe beruf>
themen: []
quelle: gespräch
stichworte: [diktat, schnellerfassung]
erstellt: <wirksames Datum>
aktualisiert: <wirksames Datum>
geprüft:
---

<!-- diktat: offen -->

# Diktate DD.MM.YYYY

## HH:MM
Text
```

Mit ausgeschaltetem Frontmatter beginnt die Datei direkt bei der H1, ohne
Frontmatter und ohne Marker.

### Fall 2: Datei vorhanden

Nur zwei Dinge passieren:

1. `aktualisiert` wird auf das wirksame Datum gesetzt, **ausschließlich**
   innerhalb des ersten `---` bis `---` Blocks am Dateianfang. Eine Zeile im
   Diktattext, die wie Frontmatter aussieht, wird nicht angefasst. Fehlt der
   Block, passiert an dieser Stelle nichts.
2. Der Abschnitt wird angehängt.

H1, Marker und alle übrigen Frontmatter-Felder bleiben unberührt. Der Marker
`<!-- diktat: offen -->` wird nie entfernt, das entscheidet der Sortierer.

### Atomares Schreiben

Lesen, ergänzen, in eine Nachbardatei im selben Ordner schreiben, dann
umbenennen. Nie in die offene Datei hineinschreiben.

- Temporärer Name: `.<Dateiname>.tmp-<UUID>` im Zielordner, also auf demselben
  Volume
- Anhängen: `FileManager.replaceItemAt`
- Anlegen: `FileManager.moveItem`
- Schlägt das Umbenennen fehl, wird die temporäre Datei entfernt

Zwei Gründe, die schon lokal gelten: zwei Diktate kurz hintereinander dürfen
sich nicht überschreiben, und ein Absturz mitten im Schreiben darf keine halbe
Zeile hinterlassen.

### Fehler

```swift
enum VaultInboxError: LocalizedError {
    case folderNotConfigured
    case folderMissing(URL)
    case notWritable(URL)
    case writeFailed(underlying: Error)
}
```

Ein fehlender Zielordner wird **nicht** neu erzeugt. Ein umbenannter oder nicht
eingebundener Vault soll auffallen und nicht heimlich einen leeren Zwilling
bekommen.

## DictationQueueStore

Datei `dictation-queue.json` unter Application Support, neben `settings.json`.
Inhalt eine Liste aus Zeitstempel und Text:

```json
[
  { "recordedAt": "2026-09-04T14:07:11Z", "text": "Roher Transkripttext." }
]
```

**Hineinlegen.** Bei jedem Schreibfehler. Zusätzlich geht der Text in die
Zwischenablage und eine Fehlerbenachrichtigung nennt den Grund.

**Nachziehen.** Beim App-Start und vor jedem neuen Schreibvorgang, älteste
zuerst. Ein nachgezogener Eintrag geht in die Datei seines **eigenen**
Zeitstempels, nicht in die von heute. Sonst wandern die Gedanken von Montag in
die Datei von Mittwoch.

**Verlassen.** Ein Eintrag verlässt die Warteschlange nur durch erfolgreiches
Schreiben. Es gibt keine Obergrenze, die still verwerfen könnte. Scheitert das
Nachziehen erneut, bleibt der Eintrag liegen und der nächste Versuch folgt.

Die Warteschlangendatei wird ebenfalls atomar geschrieben.

## UserNotificationService

Dünne Hülle um `UNUserNotificationCenter`.

**Freigabe.** Wird erst beim ersten Start des Diktat-Workflows angefragt, nicht
beim App-Start. Wer den Kanal nicht benutzt, sieht kein Prompt.

**Erfolg.** Titel "Diktat gespeichert", Unterzeile der Dateiname, Text die
ersten rund 100 Zeichen des Transkripts. Damit fällt ein falsch verstandener
Satz sofort auf.

**Fehler.** Titel "Diktat nicht gespeichert", Text der Grund plus "Der Text
liegt in der Zwischenablage."

**Abgelehnte Freigabe.** Der bestehende Menüleisten-Status bleibt als
Rückfall, und in den Einstellungen steht ein Hinweis darauf. Ein stilles
Verschlucken darf es nicht geben.

## DictationSettings

```swift
struct DictationSettings: Codable {
    var vaultFolderPath: String = ""
    var writesSecondBrainFrontmatter: Bool = false
    var sphere: DictationSphere = .beruf
}

enum DictationSphere: String, Codable, CaseIterable, Identifiable {
    case beruf
    case privat
}
```

Aufgenommen in `SettingsContainer` und in `AppState`, mit demselben
`didSet { saveSettings() }` Muster wie die übrigen Einstellungen. Wie bei
`AppSettings` wird beim Dekodieren jedes Feld über `decodeIfPresent` mit
Vorgabewert gelesen, damit eine bestehende `settings.json` ohne diesen
Abschnitt weiter lädt.

Die Sphäre ist der einzige inhaltliche Wert. Vorgabe `beruf`, weil der Kanal im
Arbeitsalltag benutzt wird. Der Sortierer korrigiert das je Abschnitt, wenn der
Inhalt privat ist. Blitztext soll das nicht erraten.

## Einstellungen im UI

Neuer Abschnitt "Diktat" in `Features/Settings/SettingsContentView.swift`:

- Ordnerauswahl über `NSOpenPanel` mit `canChooseDirectories = true` und
  `canChooseFiles = false`, daneben die Pfadanzeige
- Schalter "Second-Brain-Frontmatter schreiben"
- Sphäre-Auswahl beruf oder privat, sichtbar nur bei eingeschaltetem Schalter
- Hinweiszeile mit dem Kürzel fn + Shift + Option
- Warten Einträge in der Warteschlange: Anzahl plus Schaltfläche "Jetzt
  nachziehen"
- Hinweis, wenn Benachrichtigungen abgelehnt sind

## Hotkey

In `Services/HotkeyService.swift` kommt die Kombi fn + Shift + Option dazu. Die
Prüfung erfolgt **vor** der Prüfung auf fn + Shift, weil die bestehende
Reihenfolge auf genaue Flag-Gleichheit arbeitet und die spezifischere Kombi
sonst nie greift. Dieselbe Vorsichtsregel gilt bereits für
fn + Shift + Control.

Belegung danach:

| Kombination | Workflow |
|---|---|
| fn + Shift | Blitztext |
| fn + Shift + Control | Blitztext Lokal |
| fn + Shift + Option | Blitztext Notiz (neu) |
| fn + Control | Blitztext+ |
| fn + Option | Blitztext $%&! |
| fn + Command | Blitztext :) |

Halten und Drücken funktionieren wie bei den anderen Workflows, der bestehende
`HotkeyMode` gilt unverändert.

## Info.plist

`NSDocumentsFolderUsageDescription` kommt dazu. Ohne diesen Text verweigert
macOS den Zugriff auf einen Ordner unter `~/Documents`, und genau dort liegt der
typische Vault. Die App ist nicht sandboxed
(`com.apple.security.app-sandbox: false`), es braucht also keine
security-scoped Bookmarks, der Pfad als Zeichenkette genügt.

## Fehlerbehandlung im Überblick

| Lage | Verhalten |
|---|---|
| Kein Ordner gesetzt | Workflow nicht verfügbar, Klick öffnet Einstellungen |
| Ordner fehlt oder nicht schreibbar | Warteschlange, Zwischenablage, Fehlerbenachrichtigung, Menüleisten-Fehlerstatus |
| Schreiben schlägt fehl | wie oben |
| Transkription schlägt fehl | bestehender Pfad, kein Vault-Schreibversuch |
| Aufnahme zu kurz oder Artefakt | bestehender Pfad, kein Vault-Schreibversuch |
| Benachrichtigungen abgelehnt | Menüleisten-Status plus Hinweis in den Einstellungen |
| Zwei Diktate kurz hintereinander | vom `actor` nacheinander abgearbeitet |
| Nachziehen scheitert erneut | Eintrag bleibt liegen, nächster Versuch beim nächsten Anlass |

## Prüfung

Im Repo gibt es bisher kein Testziel. Dieser PR legt ein Ziel
`BlitztextMacTests` in `BlitztextMac/project.yml` an und prüft damit die reine
Logik, also genau den Teil, bei dem ein Fehler Text zerstört statt nur zu
nerven:

**Wirksames Datum**
- 03:59 ergibt den Vortag, 04:00 den laufenden Tag
- Monats- und Jahreswechsel um 00:20
- Frühjahrsumstellung und Herbstumstellung, wobei der Frühjahrsfall so gewählt ist, dass eine naive Rechnung mit 86400 Sekunden auffällt

**Dateiaufbau**
- neue Datei mit Frontmatter entspricht dem Format aus der Notiz, Feld für Feld
- neue Datei ohne Frontmatter beginnt bei der H1
- Abschnittsform, eine Leerzeile zwischen zwei Abschnitten

**Anhängen**
- bestehende Datei behält H1, Marker und alle Frontmatter-Felder
- `aktualisiert` wird gesetzt, `erstellt` bleibt
- eine Zeile im Diktattext, die wie `aktualisiert: 2020-01-01` aussieht, wird
  nicht angefasst
- Datei ohne Frontmatter wird angehängt, ohne dass Frontmatter entsteht

**Atomar und gleichzeitig**
- zwei gleichzeitige Schreibvorgänge ergeben zwei Abschnitte, keiner geht
  verloren
- nach dem Schreiben liegt keine `.tmp-` Datei im Zielordner

**Warteschlange**
- Runde aus Hineinlegen, Laden und erfolgreichem Nachziehen
- ein Eintrag von gestern landet in der Datei von gestern
- gescheitertes Nachziehen lässt den Eintrag liegen

Die Tests arbeiten in einem temporären Ordner und fassen keinen echten Vault
an. Netzwerk, Audio und Benachrichtigungen bleiben außen vor.

`xcodegen generate` muss laufen, weil neue Dateien und ein neues Ziel dazukommen.

Manuell zu prüfen bleibt: Kürzel greift und kollidiert nicht mit fn + Shift,
Benachrichtigung erscheint mit den ersten Wörtern, Ordnerauswahl und
Zugriffsfreigabe unter `~/Documents`, Diktat im sicheren lokalen Modus.

## Berührte Dateien

Neu:

- `BlitztextMac/Services/VaultInboxService.swift`
- `BlitztextMac/Services/DictationQueueStore.swift`
- `BlitztextMac/Services/UserNotificationService.swift`
- `BlitztextMacTests/` mit den oben genannten Tests

Geändert:

- `BlitztextMac/Features/Workflows/WorkflowProtocol.swift`, neuer Typ,
  `WorkflowOutputDestination`, `DictationSettings`
- `BlitztextMac/App/AppState.swift`, Workflow-Erzeugung, Verfügbarkeit,
  Ausgabe-Verzweigung, Einstellungen, Nachziehen beim Start
- `BlitztextMac/Services/HotkeyService.swift`, neue Kombi
- `BlitztextMac/Services/AppSupportPaths.swift`, Pfad der Warteschlangendatei
- `BlitztextMac/Features/Settings/SettingsContentView.swift`, Abschnitt "Diktat"
- `BlitztextMac/Resources/Info.plist`, `NSDocumentsFolderUsageDescription`
- `BlitztextMac/project.yml`, Testziel
- `README.md`, kurzer Absatz zum neuen Workflow

`shared/` bleibt unberührt. Dort liegen Prompts, Gateway-Vertrag und
Konfigurationsschema, und das Diktat benutzt kein Sprachmodell und keine neue
Anbieter-Einstellung. Der Vault-Schreibvertrag für Sonorus wird erst
gemeinsame Sache, wenn er dort tatsächlich gebraucht wird, und bekommt dann
einen eigenen PR.

## Anschluss

Die Tagesdatei landet in `00 Inbox/`, weil der Inbox-Sortierer nur dort
schaut. Er entscheidet auch, wann eine Datei fertig ist: jede Diktatdatei mit
einem Datum vor heute gilt als abgeschlossen. Blitztext muss davon nichts
wissen. Die Regel steht in `90 System/workflows/inbox-sortierer.md` im Vault.

Später, nicht hier: Aufgaben nach Todoist über den Sortierer, der MCP-Server
als Eingang statt des direkten Schreibens, Daily Recap, Windows.
