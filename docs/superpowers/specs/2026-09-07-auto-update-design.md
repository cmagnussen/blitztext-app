# Auto-Update: neue Versionen finden und mit einem Klick installieren

Design, Stand 2026-09-07. Umfang: `BlitztextMac` plus Release-Pipeline. Der
Windows-Teil bleibt außen vor und bekommt bei Bedarf einen eigenen PR.

Heute gibt es keinen Update-Weg. Die Settings sagen wörtlich "Diese Preview hat
keinen oeffentlichen Update-Feed" und verweisen auf `git pull` und einen
eigenen Build. Wer die App nicht selbst baut, bleibt auf der Version stehen,
die er einmal heruntergeladen hat. Gleichzeitig veröffentlicht die Pipeline
schon fertige Universal-Builds als GitHub Release. Es fehlt nur die Brücke.

## Ziel

Blitztext prüft im Hintergrund, ob eine neuere Version veröffentlicht wurde,
zeigt das dezent an und installiert sie auf Knopfdruck selbst. Kein Browser,
kein Drag-and-Drop, kein Terminal.

## Entscheidungen

1. **Ein-Klick-Update in der App**, nicht nur ein Hinweis mit Link und nicht
   vollautomatisch im Hintergrund. Der Nutzer entscheidet, die App führt aus.
2. **Nur stabile Versions-Tags.** Die rollenden `main-<sha>`-Prereleases werden
   ignoriert. Ein Update erscheint erst, wenn bewusst ein `v*`-Tag gepusht
   wurde.
3. **Ed25519-Signatur als Vertrauensanker.** Der Release-Workflow signiert die
   ZIP, die App prüft die Signatur gegen einen öffentlichen Schlüssel im
   Bundle. Kein Sparkle, aber dasselbe Prinzip.
4. **Prüfung beim Start und danach höchstens einmal pro Tag**, sichtbar als
   dezenter Punkt im Menü und als Karte in den Settings. Kein Popup, das ein
   Diktat unterbricht. Abschaltbar über einen Schalter.
5. **Atomarer Bundle-Tausch aus der App heraus** über `replaceItemAt`, kein
   abgekoppeltes Update-Skript.

### Warum die Signatur nicht optional ist

Lädt ein Browser eine Datei, setzt macOS das Quarantäne-Flag und der Gatekeeper
prüft beim ersten Start. Lädt die App die Datei selbst über URLSession, passiert
das nicht. Für den Nutzer ist das ein Vorteil: Die heutige Warnung bei der
ad-hoc signierten Preview entfällt beim In-App-Update. Für das Design heißt es,
dass keine Instanz des Systems mehr prüft, was da installiert wird. Diese
Prüfung muss die App selbst übernehmen, sonst ist der Updater ein Einfallstor.

## Nicht Teil dieses PR

- keine Delta-Updates, immer die vollständige ZIP
- kein Rollback auf eine ältere Version
- kein Beta-Kanal für die `main`-Prereleases
- keine Update-Historie
- keine Systembenachrichtigung über verfügbare Updates
- keine Developer-ID-Signatur und keine Notarisierung

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
die beiden Sperren aus dem Abschnitt Oberfläche.

### AppVersion

Reine Logik, damit sie vollständig testbar ist. `init?(string:)` toleriert ein
führendes `v`, zerlegt in numerische Komponenten und vergleicht komponentenweise.
Fehlende Komponenten zählen als Null, damit `1.5` und `1.5.0` gleich sind. Ein
nicht parsbarer String ergibt `nil` und führt nie zu einem Update-Angebot.

### UpdateFeedClient

Fragt `https://api.github.com/repos/<repo>/releases/latest` ab. Dieser Endpunkt
liefert von sich aus nur das neueste Nicht-Prerelease, damit fallen die
`main-<sha>`-Builds ohne Zusatzlogik weg. Ein Aufruf pro Tag liegt weit unter
dem Limit von 60 Anfragen pro Stunde und IP, ein Token ist nicht nötig.

Aus der Antwort werden zwei Assets gesucht: `Blitztext-macos-universal.zip` und
`Blitztext-macos-universal.zip.sig`. Fehlt eines von beiden, gilt das Release
als unbrauchbar und es wird kein Update angeboten. Beide Download-URLs müssen
auf `github.com` oder `objects.githubusercontent.com` zeigen und den erwarteten
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

## Feed und Release-Pipeline

Quelle ist `geninOne/blitztext-app`, also `origin`. Ein Fork tauscht dafür zwei
Werte in der `Info.plist`, sonst nichts:

- `BLZUpdateRepository`, zum Beispiel `geninOne/blitztext-app`
- `BLZUpdatePublicKey`, der öffentliche Ed25519-Schlüssel als Base64

Dazu zwei Skripte und ein Guard in `.github/workflows/macos-release.yml`:

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

**Versions-Guard:** Bei einem `v*`-Tag prüft ein Schritt, dass
`MARKETING_VERSION` in `BlitztextMac/project.yml` exakt dem Tag ohne `v`
entspricht, und bricht sonst ab. Ohne diesen Guard entsteht die unangenehmste
Fehlerklasse dieses Features: Tag `v1.6`, im Bundle steht weiter `1.5`, die App
bietet nach dem Update sofort wieder dasselbe Update an, endlos.

## Oberfläche

**Menü-Footer.** Neben der Versionsnummer erscheint bei verfügbarem Update ein
dezenter farbiger Punkt. Ein Klick führt in den Update-Abschnitt der Settings.

**Settings, Abschnitt Updates.** Ersetzt den heutigen Preview-Text. Zeigt die
installierte Version, den Status, den Zeitpunkt der letzten Prüfung, einen
Button "Nach Updates suchen" und den Schalter "Automatisch nach Updates suchen",
der standardmäßig an ist.

Liegt ein Update vor, kommen dazu: Versionsnummer, gekürzte Release Notes, der
Button "Version X laden und installieren", während des Vorgangs ein Fortschritt,
und der klare Hinweis, dass Blitztext sich dafür neu startet.

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
| Asset oder Signatur fehlt im Release | Fehler anzeigen, kein Download |
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
  (`1.5` gegen `1.5.1`), Müll-Eingaben ergeben `nil`
- `UpdateFeedClient`: Parsen eines echten GitHub-Release-JSON als Fixture,
  Asset-Auswahl, fehlende Signatur, Ablehnung fremder Download-Hosts
- `UpdateSignatureVerifier`: gültige Signatur, falscher Schlüssel, manipulierte
  Bytes
- `UpdateController`: kein zweiter Auto-Check am selben Tag, beide Sperren,
  Zustandsübergänge

`UpdateInstaller` bleibt bewusst dünn und wird manuell verifiziert, weil er das
echte Dateisystem und einen Neustart braucht. Der manuelle Testfall: Version
1.5 aus `/Applications` starten, ein Test-Release 1.6 veröffentlichen,
installieren lassen, prüfen dass die App als 1.6 neu startet und dass Hotkeys,
Login-Start und Berechtigungen den Tausch überlebt haben.

## Reihenfolge der Umsetzung

1. `AppVersion` plus Tests, reine Logik ohne Abhängigkeiten
2. Schlüsselpaar erzeugen, Skripte, Workflow-Änderung inklusive Versions-Guard,
   ein Test-Release als Grundlage für alles Weitere
3. `UpdateFeedClient` und `UpdateSignatureVerifier` plus Tests
4. `UpdateDownloader` und `UpdateController` plus Tests
5. Oberfläche in Menü und Settings, Sperren, neue Settings-Felder
6. `UpdateInstaller` und der manuelle Testdurchlauf zum Schluss

Nach jedem neuen Quelltext muss XcodeGen neu laufen, sonst sind die Dateien
nicht im Projekt.
