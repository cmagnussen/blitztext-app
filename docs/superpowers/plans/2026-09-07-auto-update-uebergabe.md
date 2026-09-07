# Auto-Update: Uebergabe an den Repository-Eigentuemer

Stand 2026-09-07, Zweig `feature/auto-update`.

Der Code ist fertig und geprueft. Was hier steht, kann nur der Eigentuemer des
Repositories tun, weil es Schluesselmaterial und oeffentliche Veroeffentlichungen
betrifft. Es ersetzt Task 16 des Implementierungsplans, der bewusst nicht
ausgefuehrt wurde: Er verlangt, ein Versions-Tag zu pushen und damit oeffentliche
Releases zu erzeugen, was nach aussen wirkt und nicht zurueckzunehmen ist.

## Zustand heute, ohne weitere Schritte

- Beide Apps bauen und starten. Die macOS-Suite steht bei 82 Tests, alle gruen.
- Beide oeffentlichen Schluessel sind absichtlich leer. Die macOS-App meldet
  deshalb "kein Update-Schluessel hinterlegt" und installiert nichts. Die
  Windows-App meldet "Blitztext ist aktuell", weil noch kein Manifest existiert.
- `Scripts/check-release-version.sh v1.6.0` schlaegt heute absichtlich fehl und
  nennt beide leeren Schluessel. Das Skript laeuft nur auf Versions-Tags.
- Die Release-Workflows laufen auf `main` und in Pull Requests durch. Ohne
  Signier-Secrets wird auf diesen Wegen nicht signiert, es gibt einen Hinweis im
  Protokoll, und der Windows-Build erzeugt keine Updater-Artefakte.
- Ein Versions-Tag wuerde jetzt noch am Guard scheitern, bevor irgendetwas
  gebaut wird. Das ist die gewollte Reihenfolge.

## Schritt 1: macOS-Schluesselpaar

```bash
swift Scripts/generate-update-key.swift
```

Das Kommando gibt zwei Base64-Zeilen aus.

- Die private Haelfte als Repository-Secret `BLITZTEXT_UPDATE_PRIVATE_KEY`
  hinterlegen. Sie gehoert nirgendwo sonst hin, insbesondere nicht ins Repo.
- Die oeffentliche Haelfte in `BlitztextMac/Resources/Info.plist` als Wert von
  `BLZUpdatePublicKey` eintragen, wo jetzt ein leerer String steht.

## Schritt 2: Windows-Schluesselpaar

```bash
cd BlitztextWin
npm run tauri signer generate -- -w "$HOME/.tauri/blitztext-win.key"
```

Das Kommando fragt nach einem Passwort und gibt danach den oeffentlichen
Schluessel aus.

- Inhalt von `~/.tauri/blitztext-win.key` als Secret `TAURI_SIGNING_PRIVATE_KEY`.
- Das gewaehlte Passwort als Secret `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.
- Den oeffentlichen Schluessel in `BlitztextWin/src-tauri/tauri.conf.json` unter
  `plugins.updater.pubkey` eintragen, wo jetzt ein leerer String steht.

Dieses Schluesselpaar ist ein anderes als das der macOS-Seite und darf nie mit
ihm vermischt werden.

## Schritt 3: pruefen, bevor irgendetwas veroeffentlicht wird

```bash
Scripts/check-release-version.sh v1.6.0
```

Muss jetzt mit Exit 0 durchlaufen. Solange das nicht der Fall ist, kein Tag
setzen: Der Guard laeuft in beiden Workflows und bricht sonst dort ab.

## Schritt 4: erster Durchlauf, moeglichst auf einem Wegwerf-Tag

Das Manifest-Skript der Windows-Seite ist noch nie erfolgreich gelaufen, es gibt
auf diesem Rechner keinen Windows-Build. Sein Erfolgspfad laeuft beim ersten
echten Tag zum ersten Mal. Deshalb lohnt ein Probelauf, bevor `v1.6.0` als
offizielle Version herausgeht.

Nach dem Tag pruefen, dass das Release fuenf Dateien traegt:

- `Blitztext-macos-universal.zip`
- `Blitztext-macos-universal.zip.sig`
- das NSIS-Setup `.exe`
- die MSI
- `latest.json`

Fehlt `latest.json`, hat der Windows-Job nicht durchgelaufen. Die macOS-Seite
stoert das nicht, sie sucht sich das neueste Release mit passendem Asset. Die
Windows-Seite sieht dann aber keine Updates mehr, bis das nachgezogen ist.

## Schritt 5: macOS-Update wirklich einmal durchspielen

Nicht bei Version 1.5 anfangen. Die enthaelt keinen Updater und kann gar nicht
nach Updates suchen. Richtige Reihenfolge:

1. Die aus dem ersten Tag gebaute App nach `/Applications` legen und starten.
2. Eine Folgeversion taggen, etwa `v1.6.1`, mit einer beliebigen kleinen Aenderung.
3. In den Einstellungen unter Zugang auf "Nach Updates suchen" klicken und
   installieren lassen.

Danach pruefen:

- Die App startet neu und meldet die neue Version. **Das ist der wichtigste
  Punkt.** Der Neustart wartet eine Sekunde und startet dann die App. Braucht das
  Beenden laenger, koennte der Start ins Leere laufen und es liefe hinterher gar
  nichts mehr. Falls das passiert, ist der Neustart auf ein Warten auf die
  Prozess-ID umzustellen.
- Hotkeys funktionieren weiter, ohne die Bedienungshilfen neu zu erlauben.
- Der Schalter "Beim Anmelden" steht noch so wie vorher.
- Ein Diktat laeuft durch, der Schluessel liegt weiter im Schluesselbund.
- `~/Library/Application Support/Blitztext/updates` ist nach dem Neustart weg.

## Schritt 6: den Ablehnungsfall einmal sehen

Nicht ueber ein absichtlich kaputtes oeffentliches Release. Stattdessen lokal in
der installierten App den Wert von `BLZUpdatePublicKey` in der `Info.plist`
gegen einen anderen gueltigen Schluessel tauschen und das Update laufen lassen.
Erwartet: Abbruch mit "Die Signatur des Downloads passt nicht", die geladene
Datei wird geloescht, die Installation bleibt unveraendert.

## Schritt 7: Windows auf echter Hardware

Nicht auf dem Mac-Entwicklungsrechner. Vorherige Version ueber das NSIS-Setup
installieren, Folgeversion taggen, Update ausfuehren. Danach pruefen, dass
Autostart, Hotkeys und der im Credential Manager abgelegte Schluessel den
Installer ueberlebt haben. SmartScreen kann beim unsignierten Installer warnen,
das ist ohne Code-Signing-Zertifikat nicht zu vermeiden und steht so auch im
Hinweistext der App.

## Bekannte offene Punkte

Alle klein, keiner blockiert, in absteigender Wichtigkeit:

1. **Der Guard liest den Plist-Schluessel zeilenbasiert.** Er nimmt die Zeile
   nach `<key>BLZUpdatePublicKey</key>`. Bei der heutigen Formatierung stimmt
   das. Wuerde die Datei je anders formatiert, koennte der Guard einen leeren
   Schluessel faelschlich durchwinken. Ein falsches Bestehen ist bei einem Guard
   die unangenehme Fehlerrichtung.
2. **Der erste Windows-CI-Lauf ist zu beobachten.** Auf dem Zweig ohne
   Updater-Artefakte wird weiterhin eine leere Signiervariable gesetzt. Der
   Gegentest hatte sie stattdessen entfernt. Ein gruener Lauf klaert das.
3. **Zwischen der Sperrpruefung und dem Bundle-Tausch liegt noch das Entpacken.**
   Eine in diesem Zeitfenster gestartete Aufnahme wird weiterhin beendet. Das
   Fenster ist von Minuten auf Sekunden geschrumpft, ganz schliessen liesse es
   sich nur mit einer Sperre im Installer selbst.
4. **Release Notes werden als Rohtext angezeigt**, Markdown-Zeichen erscheinen
   woertlich. Auf 400 Zeichen begrenzt.
5. **Die Oberflaeche wurde nie im laufenden Zustand gesehen**, weil die
   Ausfuehrungsumgebung keine Bildschirmaufnahme hat. Ein Blick auf den
   Update-Abschnitt vor dem ersten Tag ist zu empfehlen.
