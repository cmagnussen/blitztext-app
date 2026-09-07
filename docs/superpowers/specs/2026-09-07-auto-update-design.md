# Auto-Update: neue Versionen finden und mit einem Klick installieren

Design, Stand 2026-09-07. Umfang: **beide Apps**, `BlitztextMac` und
`BlitztextWin`, plus die gemeinsame Release-Pipeline.

Heute gibt es keinen Update-Weg. Die Mac-Settings sagen wörtlich "Diese Preview
hat keinen oeffentlichen Update-Feed" und verweisen auf `git pull` und einen
eigenen Build, die Windows-App hat gar nichts. Wer die App nicht selbst baut,
bleibt auf der Version stehen, die er einmal heruntergeladen hat. Gleichzeitig
veröffentlicht die Pipeline schon fertige Builds beider Plattformen in ein
gemeinsames GitHub Release. Es fehlt nur die Brücke.

## Ziel

Blitztext prüft im Hintergrund, ob eine neuere Version veröffentlicht wurde,
zeigt das dezent an und installiert sie auf Knopfdruck selbst. Auf beiden
Plattformen, ohne Browser, ohne Drag-and-Drop, ohne Terminal.

## Entscheidungen

1. **Ein Konzept, zwei native Implementierungen.** Kein gemeinsamer Code
   zwischen Mac und Windows. Der Mac bekommt einen eigenen kleinen Updater,
   Windows nutzt das offizielle `tauri-plugin-updater`. Gemeinsam sind nur
   Versionsschema, Kanal, Rhythmus, Sperren und Wortlaut.
2. **Ein-Klick-Update in der App**, nicht nur ein Hinweis mit Link und nicht
   vollautomatisch im Hintergrund. Der Nutzer entscheidet, die App führt aus.
3. **Nur stabile Versions-Tags.** Die rollenden `main-<sha>`-Prereleases werden
   ignoriert. Ein Update erscheint erst, wenn bewusst ein `v*`-Tag gepusht
   wurde.
4. **Signatur als Vertrauensanker auf beiden Plattformen.** Mac: Ed25519 über
   CryptoKit, selbst geprüft. Windows: minisign über den Tauri-Updater. Zwei
   getrennte Schlüsselpaare.
5. **Prüfung beim Start und danach höchstens einmal pro Tag**, sichtbar als
   dezenter Hinweis im Menü und als Karte in den Einstellungen. Kein Popup, das
   ein Diktat unterbricht. Abschaltbar über einen Schalter.
6. **macOS installiert per atomarem Bundle-Tausch** über `replaceItemAt`, kein
   abgekoppeltes Update-Skript. **Windows führt den NSIS-Installer aus**, weil
   dort nichts anderes möglich ist.
7. **Gemeinsames Versions-Tag, dreistelliges Semver.** Ein Tag `v1.6.0`
   veröffentlicht beide Apps, beide tragen intern exakt `1.6.0`.

### Warum dreistellig

Der Tauri-Updater vergleicht Versionen strikt nach Semver. `1.6` ist kein
gültiges Semver, `1.6.0` schon. Da beide Apps sich ein Tag teilen, gibt das
Windows das Format vor. Für den Mac ist der Wechsel folgenlos: `AppVersion`
vergleicht komponentenweise und behandelt fehlende Komponenten als Null, `1.5`
und `1.5.0` sind identisch.

Die Windows-App springt damit von `0.1.0` auf die gemeinsame Nummer. Das ist
ein bewusster, künstlicher Sprung, der in den Release Notes erklärt gehört.

### Warum die Signatur nicht optional ist

Lädt ein Browser eine Datei, setzt macOS das Quarantäne-Flag und der Gatekeeper
prüft beim ersten Start. Lädt die App die Datei selbst über URLSession, passiert
das nicht. Für den Nutzer ist das ein Vorteil: Die heutige Warnung bei der
ad-hoc signierten Preview entfällt beim In-App-Update. Für das Design heißt es,
dass keine Instanz des Systems mehr prüft, was da installiert wird. Diese
Prüfung muss die App selbst übernehmen, sonst ist der Updater ein Einfallstor.

Auf Windows gilt dasselbe Argument, dort erledigt das Plugin die Prüfung.

## Nicht Teil dieses PR

- keine Delta-Updates, immer das vollständige Artefakt
- kein Rollback auf eine ältere Version
- kein Beta-Kanal für die `main`-Prereleases
- keine Update-Historie
- keine Systembenachrichtigung über verfügbare Updates
- keine Developer-ID-Signatur, keine Notarisierung, kein
  Windows-Code-Signing-Zertifikat. SmartScreen wird beim Windows-Installer
  weiter warnen, das ist ohne Zertifikat nicht lösbar.
- keine MSI-Updates. Der Updater bedient ausschließlich den NSIS-Pfad, die MSI
  bleibt als manueller Download im Release.

---

# Teil 1: Gemeinsamer Vertrag

Was auf beiden Plattformen gleich sein muss, damit sich das Feature konsistent
anfühlt und die Pipeline nicht auseinanderläuft.

**Versionen.** Ein Tag `v<major>.<minor>.<patch>`. Die Nummer steht identisch
in drei Dateien: `BlitztextMac/project.yml` (`MARKETING_VERSION`),
`BlitztextWin/package.json` und `BlitztextWin/src-tauri/tauri.conf.json`.
`CURRENT_PROJECT_VERSION` auf der Mac-Seite bleibt eine reine Build-Nummer und
wird nicht geprüft.

**Versions-Guard.** Ein Schritt in beiden Workflows bricht ab, wenn eine dieser
drei Dateien nicht exakt zum Tag passt. Ohne diesen Guard entsteht die
unangenehmste Fehlerklasse dieses Features: Tag `v1.6.0`, im Artefakt steht
weiter die alte Nummer, die App bietet nach dem Update sofort wieder dasselbe
Update an, endlos.

**Kanal.** Nur Nicht-Prereleases. Beide Plattformen filtern das über den
GitHub-Endpunkt, nicht über eigene Logik.

**Rhythmus und Sperren.** Prüfung beim Start und danach höchstens einmal pro
Tag, abschaltbar. Kein Update während einer laufenden Aufnahme oder solange
eine Warteschlange arbeitet. Kein Update aus einem Entwicklungs-Build heraus.

**Wortlaut.** Gleiche Beschriftungen auf beiden Plattformen: "Nach Updates
suchen", "Automatisch nach Updates suchen", "Version X laden und installieren",
und der Hinweis, dass Blitztext sich dafür neu startet.

**Betriebsregel.** Beide Jobs laufen bei jedem `v*`-Tag. Schlägt der
Windows-Job fehl, fehlt das Update-Manifest im Release und Windows sieht keine
Updates mehr, bis das nachgezogen ist. Die Mac-Seite ist davon nicht betroffen,
weil sie sich das neueste Release mit passendem Asset sucht.

---

# Teil 2: macOS

## Komponenten

Neuer Ordner `BlitztextMac/Services/Update/`. Jede Einheit hat eine Aufgabe und
kennt nur ihre direkten Abhängigkeiten.

| Einheit | Aufgabe | Abhängig von |
| --- | --- | --- |
| `AppVersion` | Versionsstring parsen und vergleichen, `Comparable` | nichts |
| `UpdateRelease` | Wertetyp mit Version, Tag, Notes, ZIP-URL, Signatur-URL, Größe | nichts |
| `UpdateFeedClient` | GitHub-API abfragen, Assets auswählen, Hosts prüfen | URLSession |
| `UpdateSignatureVerifier` | Ed25519-Prüfung über die ZIP-Bytes | CryptoKit |
| `UpdateDownloader` | ZIP und Signatur mit Fortschritt laden | URLSession |
| `UpdateInstaller` | Entpacken, Bundle prüfen, tauschen, neu starten | FileManager, Process |
| `UpdateController` | Zustandsautomat für die Oberfläche | alle obigen |

### UpdateController

`@Observable @MainActor`, gehalten von `AppState`. Er ist die einzige Einheit,
die die Oberfläche kennt, und hält genau einen Zustand:

```
idle | checking | upToDate | available(UpdateRelease) | downloading(Double)
     | verifying | readyToInstall | installing | failed(String)
```

Die Oberfläche liest diesen Zustand und ruft `checkForUpdates()` und
`installAvailableUpdate()`. Sie kennt weder Feed noch Downloader noch
Installer. Der Controller entscheidet außerdem über den Tagesrhythmus und über
die beiden Sperren.

### AppVersion

Reine Logik, damit sie vollständig testbar ist. `init?(string:)` toleriert ein
führendes `v`, zerlegt in numerische Komponenten und vergleicht komponentenweise.
Fehlende Komponenten zählen als Null, damit `1.5` und `1.5.0` gleich sind. Ein
nicht parsbarer String ergibt `nil` und führt nie zu einem Update-Angebot.

### UpdateFeedClient

Fragt `https://api.github.com/repos/<repo>/releases?per_page=20` ab und nimmt
das neueste Nicht-Prerelease, **das ein macOS-Asset samt Signatur enthält**.

Bewusst nicht `releases/latest`: Dieser Endpunkt liefert genau ein Release.
Fehlt darin das Mac-Asset, weil ein Job fehlgeschlagen ist oder eine Plattform
einzeln released wurde, sähe die App nie wieder ein Update, obwohl ein
passendes Release weiter unten in der Liste liegt. Die Suche über die Liste
kostet ein paar Zeilen und ist gegen diesen Fall immun.

Ein Aufruf pro Tag liegt weit unter dem Limit von 60 Anfragen pro Stunde und
IP, ein Token ist nicht nötig.

Gesucht werden zwei Assets: `Blitztext-macos-universal.zip` und
`Blitztext-macos-universal.zip.sig`. Beide Download-URLs müssen auf
`github.com` oder `objects.githubusercontent.com` zeigen und den erwarteten
Repo-Pfad enthalten, sonst wird die Antwort verworfen.

### UpdateInstaller

Reihenfolge, und die Reihenfolge ist der Kern der Sicherheitsgarantie:

1. Signatur der geladenen ZIP prüfen. Schlägt das fehl, wird die Datei sofort
   gelöscht und nichts weiter unternommen.
2. Mit `/usr/bin/ditto -x -k` in ein Temp-Verzeichnis entpacken, das **neben
   dem Ziel-Bundle** liegt. Auf einem anderen Volume wäre `replaceItemAt` kein
   atomarer Rename mehr, sondern eine Kopie.
3. Das entpackte Bundle gegen drei Bedingungen prüfen: genau eine `.app` im
   Archiv, gleiche `CFBundleIdentifier` wie die laufende App, und eine
   tatsächlich höhere Version als die eigene.
4. `FileManager.replaceItemAt` auf das eigene Bundle. Bis zu diesem Aufruf wird
   die bestehende Installation nicht angefasst. Der Aufruf selbst ist atomar:
   Es liegt entweder die alte oder die neue App da, nie eine halbe.
5. Neustart über einen abgekoppelten `/bin/sh -c "sleep 1; open <pfad>"` und
   `NSApp.terminate`. Die laufende App überlebt Schritt 4, weil macOS ihre
   Code-Seiten über die alte Inode hält.

## Pipeline und Schlüssel

Quelle ist `geninOne/blitztext-app`, also `origin`. Ein Fork tauscht dafür zwei
Werte in der `Info.plist`, sonst nichts:

- `BLZUpdateRepository`, zum Beispiel `geninOne/blitztext-app`
- `BLZUpdatePublicKey`, der öffentliche Ed25519-Schlüssel als Base64

Dazu zwei Skripte in `.github/workflows/macos-release.yml`:

**`Scripts/generate-update-key.swift`** erzeugt einmalig lokal ein
Schlüsselpaar und gibt beide Hälften aus. Der private Teil wird als
GitHub-Secret `BLITZTEXT_UPDATE_PRIVATE_KEY` hinterlegt und sonst nirgends
gespeichert, der öffentliche wandert in die `Info.plist`.

**`Scripts/sign-update.swift`** signiert im Workflow die gepackte ZIP und legt
`Blitztext-macos-universal.zip.sig` daneben, die als zweites Asset ins Release
geladen wird. Swift statt OpenSSL, weil der macOS-Runner CryptoKit ohnehin
mitbringt und Signieren und Prüfen so denselben Code nutzen. Signiert wird bei
jedem Build, auch bei den Prereleases: Es kostet nichts und hält einen späteren
Beta-Kanal offen.

## Oberfläche

**Menü-Footer.** Neben der Versionsnummer erscheint bei verfügbarem Update ein
dezenter farbiger Punkt. Ein Klick führt in den Update-Abschnitt der Settings.

**Settings, Abschnitt Updates.** Ersetzt den heutigen Preview-Text. Zeigt die
installierte Version, den Status, den Zeitpunkt der letzten Prüfung, einen
Button "Nach Updates suchen" und den Schalter "Automatisch nach Updates suchen",
der standardmäßig an ist. Liegt ein Update vor, kommen Versionsnummer, gekürzte
Release Notes, der Installieren-Button, ein Fortschritt und der Neustart-Hinweis
dazu.

**Zwei Sperren:**

- Läuft die App nicht aus `/Applications` oder `~/Applications`, gibt es keinen
  Installieren-Button, sondern den Hinweis auf `git pull` und einen eigenen
  Build. Sonst überschreibt der Updater ein lokales Build-Ergebnis.
  `BlitztextInstallLocationService` liefert diese Information bereits.
- Während einer laufenden Aufnahme oder solange die Diktat-Warteschlange
  arbeitet, ist der Button deaktiviert und begründet das. Ein Neustart mitten
  im Diktat wäre Datenverlust.

**Einstellungen.** `AppSettings` bekommt `automaticUpdateChecksEnabled: Bool`
mit Standard `true` und `lastUpdateCheck: Date?`. Beide über `decodeIfPresent`,
damit eine bestehende `settings.json` ohne diese Felder weiter lädt. Das ist das
Muster, das die übrigen Settings schon nutzen.

## Fehlerbehandlung

Leitlinie: Ein fehlgeschlagenes Update darf die bestehende Installation nie
beschädigen und die App nie beenden. Die Reihenfolge im Installer gibt das her,
weil vor dem atomaren Tausch nichts am alten Bundle angefasst wird.

| Fall | Verhalten |
| --- | --- |
| Netz nicht erreichbar | Auto-Check scheitert still, manueller Check zeigt den Fehler |
| Asset oder Signatur fehlt im Release | Release überspringen, weiter in der Liste suchen |
| Signatur ungültig | Harter Abbruch, Datei löschen, deutliche Warnung |
| Entpacken oder Bundle-Prüfung scheitert | Abbruch, Temp-Ordner aufräumen |
| Ziel nicht beschreibbar | Klartext-Hinweis auf die Rechte an `/Applications` |
| Tausch scheitert | Alte App bleibt unangetastet, Fehler anzeigen |

Die ungültige Signatur ist der einzige Fall, der laut sein muss. Alle anderen
Fehler bleiben im Update-Abschnitt und bieten zusätzlich einen Link zur
Release-Seite im Browser an, damit nie eine Sackgasse entsteht.

Geladene Dateien liegen in einem eigenen Update-Ordner unter Application
Support, der beim Start aufgeräumt wird. `BlitztextCleanupService` ist die
Stelle dafür.

## Tests

Ins bestehende Target `BlitztextMacTests`, mit den gleichen expliziten
Datei-Einträgen in `project.yml`, die die anderen getesteten Services schon
haben.

- `AppVersion`: Vergleiche, führendes `v`, unterschiedlich viele Komponenten
  (`1.5` gegen `1.5.1`), `1.5` gleich `1.5.0`, Müll-Eingaben ergeben `nil`
- `UpdateFeedClient`: Parsen einer echten GitHub-Release-Liste als Fixture,
  Asset-Auswahl, Überspringen eines Release ohne Mac-Asset, Prereleases werden
  ignoriert, Ablehnung fremder Download-Hosts
- `UpdateSignatureVerifier`: gültige Signatur, falscher Schlüssel, manipulierte
  Bytes
- `UpdateController`: kein zweiter Auto-Check am selben Tag, beide Sperren,
  Zustandsübergänge

`UpdateInstaller` bleibt bewusst dünn und wird manuell verifiziert, weil er das
echte Dateisystem und einen Neustart braucht.

---

# Teil 3: Windows

Hier wird nichts selbst gebaut. `tauri-plugin-updater` ist offiziell, löst
genau dieses Problem und bringt Signaturprüfung, Download, Installation und
Neustart mit. Selbst gebaut wird nur die Oberfläche und das Manifest im
Workflow.

## Einbindung

**Rust** (`src-tauri/`): `tauri-plugin-updater` und `tauri-plugin-process` in
`Cargo.toml`, beide in `lib.rs` registriert.

**Frontend**: `@tauri-apps/plugin-updater` und `@tauri-apps/plugin-process` in
`package.json`.

**Berechtigungen** (`src-tauri/capabilities/default.json`): `updater:default`
und `process:allow-restart` ergänzen. Ohne die schlägt der Aufruf zur Laufzeit
fehl, nicht beim Bauen.

**Konfiguration** (`tauri.conf.json`):

- `bundle.createUpdaterArtifacts: true`, sonst erzeugt der Bundler keine
  signierten Update-Artefakte
- `plugins.updater.pubkey`: der öffentliche minisign-Schlüssel
- `plugins.updater.endpoints`:
  `https://github.com/geninOne/blitztext-app/releases/latest/download/latest.json`
- `plugins.updater.windows.installMode: "passive"`: der Installer läuft mit
  Fortschrittsanzeige, aber ohne Klickstrecke

Der Endpunkt zeigt bewusst auf `releases/latest/download/`. GitHub löst das auf
das neueste **Nicht-Prerelease** auf, damit sind die `main`-Builds ohne
Zusatzlogik draußen, genau wie auf der Mac-Seite.

## Schlüssel und Manifest

**Schlüsselpaar**: einmalig lokal über `npm run tauri signer generate`. Der
private Schlüssel wird als Secret `TAURI_SIGNING_PRIVATE_KEY` hinterlegt, das
zugehörige Passwort als `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. Beide werden im
Build-Schritt als Umgebungsvariablen gesetzt, dann signiert der Bundler von
selbst. Der öffentliche Schlüssel steht in `tauri.conf.json`. Er ist ein
anderer als der Mac-Schlüssel und wird nie mit ihm vermischt.

**`BlitztextWin/scripts/make-updater-manifest.mjs`**: erzeugt nach dem Build das
`latest.json`, das das Plugin erwartet:

```json
{
  "version": "1.6.0",
  "notes": "...",
  "pub_date": "2026-09-07T10:00:00Z",
  "platforms": {
    "windows-x86_64": {
      "signature": "<Inhalt der .sig-Datei>",
      "url": "https://github.com/geninOne/blitztext-app/releases/download/v1.6.0/Blitztext_1.6.0_x64-setup.exe"
    }
  }
}
```

Die Signatur ist der **Inhalt** der vom Bundler erzeugten `.sig`-Datei, nicht
ihr Pfad. `version` kommt aus `tauri.conf.json` und ist durch den Versions-Guard
garantiert identisch mit dem Tag. Das Manifest wird als weiteres Asset ins
Release geladen.

## Oberfläche

Gleiches Konzept wie auf dem Mac, in der bestehenden Popover-Oberfläche:

- Im Menü-View bei verfügbarem Update ein dezenter Punkt neben der Version
- In den Einstellungen ein Abschnitt "Updates" im Tab **Zugang**, direkt beim
  Autostart-Schalter, mit denselben Beschriftungen wie auf dem Mac
- Ablauf: `check()` liefert das Update, `downloadAndInstall()` meldet Fortschritt
  über Events, danach `relaunch()` aus `plugin-process`

**Zwei Sperren, spiegelbildlich zum Mac:**

- Im Entwicklungs-Build (`import.meta.env.DEV`) wird gar nicht erst geprüft
- Während einer laufenden Aufnahme ist der Button deaktiviert. Das
  `RecordingFlag` im Rust-Kern und der Zustand im Frontend liefern das bereits

**Einstellungen**: `automaticUpdateChecks` und `lastUpdateCheck` im bestehenden
`localStorage`-Settings-Objekt, wie die übrigen nicht-geheimen Werte.

## Fehlerbehandlung

Das Plugin wirft bei Netzfehlern, fehlendem Manifest und ungültiger Signatur.
Behandlung analog zum Mac: Auto-Check scheitert still, manueller Check zeigt
Klartext, und jeder Fehlerzustand bietet den Link zur Release-Seite an.

Ein 404 auf `latest.json` bedeutet, dass das neueste Release kein
Windows-Manifest enthält. Das ist kein Fehler des Nutzers und wird als "kein
Update verfügbar" behandelt, nicht als Störung. Siehe die Betriebsregel in
Teil 1.

Was nicht wegzudesignen ist: Der Installer ist unsigniert, SmartScreen kann
beim Ausführen warnen. Der NSIS-Installer läuft im Standard als
Benutzer-Installation, deshalb ist kein UAC-Prompt zu erwarten. Beides gehört
in den Hinweistext neben dem Installieren-Button, damit die Warnung niemanden
überrascht.

## Tests

In `BlitztextWin` gibt es heute kein Test-Setup. Wir führen dafür keins ein.
Begründung: Die Update-Logik liegt vollständig im Plugin, unser Anteil ist
Konfiguration, ein Manifest-Generator von wenigen Zeilen und Oberfläche. Ein
Test-Runner für diese Menge wäre mehr Gerüst als Nutzen.

Stattdessen manuelle Verifikation, siehe unten. Der Manifest-Generator wird im
Workflow durch einen `jq`-Schritt geprüft, der die erzeugte Datei gegen die
erwarteten Felder validiert und bei Abweichung den Build abbricht.

---

# Umsetzung

## Reihenfolge

1. Versionsschema vereinheitlichen: `MARKETING_VERSION`, `package.json` und
   `tauri.conf.json` auf dieselbe dreistellige Nummer, Versions-Guard in beide
   Workflows
2. Beide Schlüsselpaare erzeugen, Secrets hinterlegen, Signier-Schritte in
   beide Workflows, ein Test-Release als Grundlage für alles Weitere
3. macOS: `AppVersion` plus Tests, reine Logik ohne Abhängigkeiten
4. macOS: `UpdateFeedClient` und `UpdateSignatureVerifier` plus Tests
5. macOS: `UpdateDownloader` und `UpdateController` plus Tests
6. macOS: Oberfläche, Sperren, neue Settings-Felder
7. macOS: `UpdateInstaller`
8. Windows: Plugin einbinden, Konfiguration, Berechtigungen
9. Windows: Manifest-Generator und Workflow-Schritt
10. Windows: Oberfläche und Sperren
11. Beide manuell verifizieren

Nach jedem neuen Swift-Quelltext muss XcodeGen neu laufen, sonst sind die
Dateien nicht im Projekt.

## Manuelle Verifikation

**macOS**: Version 1.5.0 aus `/Applications` starten, ein Test-Release 1.6.0
veröffentlichen, installieren lassen. Prüfen, dass die App als 1.6.0 neu
startet und dass Hotkeys, Login-Start und die erteilten Berechtigungen den
Bundle-Tausch überlebt haben.

**Windows**: Auf echter Windows-Hardware, nicht auf dem Mac-Dev-Rechner. Die
alte Version über den NSIS-Installer installieren, Test-Release veröffentlichen,
Update ausführen. Prüfen, dass die App als neue Version startet und dass
Autostart, Hotkeys und der im Credential Manager abgelegte API-Schlüssel den
Installer überlebt haben.

## Was du selbst machen musst

- Beide privaten Schlüssel erzeugen und als Repo-Secrets hinterlegen. Sie
  dürfen weder ins Repo noch durch eine Konversation laufen.
- Entscheiden, welche Nummer das erste gemeinsame Release trägt, und den
  Versionssprung der Windows-App in den Release Notes erklären.
