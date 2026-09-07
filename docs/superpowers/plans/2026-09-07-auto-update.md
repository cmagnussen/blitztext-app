# Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beide Blitztext-Apps finden neue Versionen im GitHub Release, prüfen deren Signatur und installieren sie auf Knopfdruck selbst.

**Architecture:** Ein Konzept, zwei native Implementierungen. macOS bekommt einen eigenen kleinen Updater aus sieben Einheiten, der die GitHub-API liest, eine Ed25519-Signatur prüft und das App-Bundle atomar über `FileManager.replaceItemAt` tauscht. Windows nutzt das offizielle `tauri-plugin-updater` mit minisign und einem `latest.json` im Release. Gemeinsam sind nur Versionsschema, Kanal, Rhythmus, Sperren und Wortlaut.

**Tech Stack:** Swift 5.10, SwiftUI, CryptoKit, XCTest, XcodeGen. Tauri v2, Rust, TypeScript, Vite. GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-07-auto-update-design.md`

## Global Constraints

- **Sprache:** Alle nutzersichtbaren Texte, Kommentare und Testnamen sind deutsch. Testnamen im Stil des Bestands, zum Beispiel `testFehlendeKomponenteZaehltAlsNull`.
- **Keine Gedankenstriche** in Texten, weder im Code noch in Commit-Nachrichten.
- **Zielversion dieses Releases:** `1.6.0`. Sie steht identisch in `BlitztextMac/project.yml`, `BlitztextWin/package.json` und `BlitztextWin/src-tauri/tauri.conf.json`.
- **Repository für den Feed:** `geninOne/blitztext-app`.
- **Plattform:** macOS 14, Swift 5.10, Xcode 16. Windows über Tauri v2.
- **Nach jeder neuen Swift-Datei** muss `xcodegen generate` in `BlitztextMac/` laufen, sonst ist die Datei nicht im Projekt. `./test.sh` macht das von selbst.
- **Tests laufen mit** `./test.sh` aus dem Repo-Wurzelverzeichnis.
- **Commit-Präfix** für diese Arbeit: `Update:`. Jede Commit-Nachricht endet mit `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Asset-Namen im Release:** `Blitztext-macos-universal.zip`, `Blitztext-macos-universal.zip.sig`, `latest.json`.
- **Info.plist-Schlüssel:** `BLZUpdateRepository`, `BLZUpdatePublicKey`.
- **Secrets:** `BLITZTEXT_UPDATE_PRIVATE_KEY` (macOS, Ed25519 roh als Base64), `TAURI_SIGNING_PRIVATE_KEY` und `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` (Windows, minisign).

## Abweichungen von der Spec

Zwei bewusste Präzisierungen, die beim Ausformulieren entstanden sind:

1. **Kein Zustand `readyToInstall`.** Die Spec listet ihn auf, aber Download, Prüfung und Installation laufen in einer einzigen Nutzeraktion durch. Ein eigener Wartezustand dazwischen hätte keinen Auslöser. Der Automat kommt mit `downloading`, `verifying` und `installing` aus.
2. **Host-Prüfung strenger als beschrieben.** Geprüft wird nur die `browser_download_url` aus der API, und die muss auf `github.com` mit dem erwarteten Repo-Pfad zeigen. `objects.githubusercontent.com` taucht nur als Weiterleitungsziel auf, das URLSession intern auflöst. Das ist strikter als in der Spec und damit unproblematisch.

## Meilensteine

- **Tasks 1 bis 12** ergeben eine vollständig funktionierende macOS-Lösung. Nach Task 12 ist der Mac-Teil auslieferbar.
- **Tasks 13 bis 15** ergänzen Windows.
- **Task 16** ist die manuelle Verifikation beider Plattformen.

---

### Task 1: Versionsschema vereinheitlichen und Versions-Guard

Beide Apps teilen sich ein Tag. Der Guard verhindert die schlimmste Fehlerklasse dieses Features: ein Release, dessen Artefakte eine andere Nummer tragen als das Tag, wodurch die App nach dem Update endlos dasselbe Update anbietet.

**Files:**
- Create: `Scripts/check-release-version.sh`
- Modify: `BlitztextMac/project.yml:12` (`MARKETING_VERSION`)
- Modify: `BlitztextWin/package.json:4` (`version`)
- Modify: `BlitztextWin/src-tauri/tauri.conf.json:4` (`version`)
- Modify: `.github/workflows/macos-release.yml`
- Modify: `.github/workflows/windows-release.yml`

**Interfaces:**
- Consumes: nichts
- Produces: `Scripts/check-release-version.sh <tag>`, Exit 0 bei Übereinstimmung, Exit 1 mit Klartext auf stderr sonst.

- [ ] **Step 1: Guard-Skript schreiben**

Create `Scripts/check-release-version.sh`:

```bash
#!/usr/bin/env bash
# Prueft, dass alle Versionsnummern im Repo exakt zum Release-Tag passen.
# Nutzung: Scripts/check-release-version.sh v1.6.0
set -euo pipefail

TAG="${1:?Tag erwartet, zum Beispiel v1.6.0}"
EXPECTED="${TAG#v}"

if ! [[ "$EXPECTED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Tag '$TAG' ist kein dreistelliges Semver. Erwartet wird vX.Y.Z." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mac_version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' BlitztextMac/project.yml | head -1)"
win_package="$(node -p "require('./BlitztextWin/package.json').version")"
win_tauri="$(node -p "require('./BlitztextWin/src-tauri/tauri.conf.json').version")"

status=0
check() {
    local datei="$1"
    local wert="$2"
    if [ "$wert" != "$EXPECTED" ]; then
        echo "$datei steht auf '$wert', erwartet wird '$EXPECTED'." >&2
        status=1
    fi
}

check "BlitztextMac/project.yml (MARKETING_VERSION)" "$mac_version"
check "BlitztextWin/package.json (version)" "$win_package"
check "BlitztextWin/src-tauri/tauri.conf.json (version)" "$win_tauri"

if [ "$status" -eq 0 ]; then
    echo "Alle Versionsnummern stimmen mit $TAG ueberein."
fi
exit "$status"
```

Ausführbar machen: `chmod +x Scripts/check-release-version.sh`

- [ ] **Step 2: Guard gegen den heutigen Stand laufen lassen, er muss scheitern**

Run: `Scripts/check-release-version.sh v1.6.0`
Expected: Exit 1, drei Meldungen. `project.yml` steht auf `1.5`, beide Windows-Dateien auf `0.1.0`.

- [ ] **Step 3: Versionsnummern auf 1.6.0 setzen**

In `BlitztextMac/project.yml` unter `settings.base`:

```yaml
    MARKETING_VERSION: "1.6.0"
    CURRENT_PROJECT_VERSION: "16"
```

In `BlitztextWin/package.json`:

```json
  "version": "1.6.0",
```

In `BlitztextWin/src-tauri/tauri.conf.json`:

```json
  "version": "1.6.0",
```

Zur Ordnung auch `BlitztextWin/src-tauri/Cargo.toml` auf `version = "1.6.0"` setzen. Der Guard prüft die Datei nicht, weil `tauri.conf.json` für die App maßgeblich ist.

- [ ] **Step 4: Guard erneut laufen lassen, er muss bestehen**

Run: `Scripts/check-release-version.sh v1.6.0`
Expected: Exit 0, Ausgabe "Alle Versionsnummern stimmen mit v1.6.0 ueberein."

- [ ] **Step 5: Guard in beide Workflows einhängen**

In `.github/workflows/macos-release.yml` direkt nach dem Schritt `Show Xcode version` einfügen:

```yaml
      - name: Verify versions match the tag
        if: startsWith(github.ref, 'refs/tags/v')
        run: bash Scripts/check-release-version.sh "$GITHUB_REF_NAME"
```

In `.github/workflows/windows-release.yml` direkt nach dem Schritt `Setup Node` einfügen. Achtung: Der Job hat `working-directory: BlitztextWin`, deshalb muss der Schritt das überschreiben:

```yaml
      - name: Verify versions match the tag
        if: startsWith(github.ref, 'refs/tags/v')
        shell: bash
        working-directory: ${{ github.workspace }}
        run: bash Scripts/check-release-version.sh "$GITHUB_REF_NAME"
```

- [ ] **Step 6: Commit**

```bash
git add Scripts/check-release-version.sh BlitztextMac/project.yml BlitztextWin/package.json BlitztextWin/src-tauri/tauri.conf.json BlitztextWin/src-tauri/Cargo.toml .github/workflows/macos-release.yml .github/workflows/windows-release.yml
git commit -m "$(cat <<'MSG'
Update: gemeinsames Versionsschema und Versions-Guard

Beide Apps tragen ab jetzt dieselbe dreistellige Nummer. Ein Guard in
beiden Workflows bricht ab, wenn eine Datei nicht zum Tag passt.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: AppVersion

Reine Vergleichslogik ohne Abhängigkeiten. Sie ist die Grundlage für jede Entscheidung "ist das ein Update".

**Files:**
- Create: `BlitztextMac/Services/Update/AppVersion.swift`
- Create: `BlitztextMac/Tests/AppVersionTests.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)

**Interfaces:**
- Consumes: nichts
- Produces: `struct AppVersion: Equatable, Comparable, CustomStringConvertible` mit `init?(string: String)`, `var components: [Int]`, `var description: String`, `static var current: AppVersion?`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

Create `BlitztextMac/Tests/AppVersionTests.swift`:

```swift
import XCTest

final class AppVersionTests: XCTestCase {
    func testFuehrendesVWirdIgnoriert() {
        XCTAssertEqual(AppVersion(string: "v1.6.0"), AppVersion(string: "1.6.0"))
    }

    func testFehlendeKomponenteZaehltAlsNull() {
        XCTAssertEqual(AppVersion(string: "1.5"), AppVersion(string: "1.5.0"))
    }

    func testNeuereVersionIstGroesser() {
        let alt = AppVersion(string: "1.5.9")!
        let neu = AppVersion(string: "1.6.0")!
        XCTAssertTrue(neu > alt)
        XCTAssertFalse(alt > neu)
    }

    func testDritteKomponenteEntscheidet() {
        XCTAssertTrue(AppVersion(string: "1.5.1")! > AppVersion(string: "1.5")!)
    }

    func testZweistelligeZahlenWerdenNumerischVerglichen() {
        XCTAssertTrue(AppVersion(string: "1.10.0")! > AppVersion(string: "1.9.0")!)
    }

    func testLeerraumWirdEntfernt() {
        XCTAssertEqual(AppVersion(string: "  v1.6.0  "), AppVersion(string: "1.6.0"))
    }

    func testMuellErgibtNil() {
        XCTAssertNil(AppVersion(string: "beta"))
        XCTAssertNil(AppVersion(string: "1.x.0"))
        XCTAssertNil(AppVersion(string: ""))
        XCTAssertNil(AppVersion(string: "v"))
        XCTAssertNil(AppVersion(string: "1..0"))
    }

    func testBeschreibungGibtDieKomponentenZurueck() {
        XCTAssertEqual(AppVersion(string: "v1.6.0")?.description, "1.6.0")
    }
}
```

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `./test.sh -only-testing:BlitztextMacTests/AppVersionTests`
Expected: Übersetzungsfehler, `cannot find 'AppVersion' in scope`.

- [ ] **Step 3: Implementierung schreiben**

Create `BlitztextMac/Services/Update/AppVersion.swift`:

```swift
import Foundation

/// Vergleichbare Programmversion. Toleriert ein fuehrendes "v" und
/// unterschiedlich viele Komponenten: 1.5 und 1.5.0 sind dieselbe Version.
/// Nicht parsbare Eingaben ergeben nil und fuehren nie zu einem Update-Angebot.
struct AppVersion: Equatable, Comparable, CustomStringConvertible {
    let components: [Int]

    init?(string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var parsed: [Int] = []
        for teil in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let wert = Int(teil), wert >= 0 else { return nil }
            parsed.append(wert)
        }
        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Die Version der laufenden App aus dem Bundle.
    static var current: AppVersion? {
        guard let roh = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }
        return AppVersion(string: roh)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let anzahl = max(lhs.components.count, rhs.components.count)
        for index in 0..<anzahl {
            let links = index < lhs.components.count ? lhs.components[index] : 0
            let rechts = index < rhs.components.count ? rhs.components[index] : 0
            if links != rechts { return links < rechts }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
```

- [ ] **Step 4: Datei ins Testziel aufnehmen**

In `BlitztextMac/project.yml` beim Ziel `BlitztextMacTests` unter `sources` ergänzen:

```yaml
      - path: Services/Update/AppVersion.swift
```

- [ ] **Step 5: Test laufen lassen, er muss bestehen**

Run: `./test.sh -only-testing:BlitztextMacTests/AppVersionTests`
Expected: alle acht Tests bestehen.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Services/Update/AppVersion.swift BlitztextMac/Tests/AppVersionTests.swift BlitztextMac/project.yml
git commit -m "$(cat <<'MSG'
Update: AppVersion fuer den Versionsvergleich

Toleriert ein fuehrendes v und behandelt 1.5 und 1.5.0 als gleich.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: UpdateRelease und UpdateFeedClient

Liest die GitHub-API und sucht das neueste Nicht-Prerelease, das beide Assets mitbringt. Bewusst nicht `releases/latest`, weil dieser Endpunkt nur ein einziges Release liefert und die App dauerhaft blind wäre, wenn darin das Mac-Asset fehlt.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdateRelease.swift`
- Create: `BlitztextMac/Services/Update/UpdateFeedClient.swift`
- Create: `BlitztextMac/Tests/UpdateFeedClientTests.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)

**Interfaces:**
- Consumes: `AppVersion` aus Task 2
- Produces:
  - `struct UpdateRelease: Equatable` mit `version: AppVersion`, `tagName: String`, `releaseNotes: String`, `archiveURL: URL`, `signatureURL: URL`, `archiveSize: Int`
  - `struct UpdateFeedClient` mit `init(repository: String, session: URLSession = .shared)`, `func fetchNewestRelease() async throws -> UpdateRelease?`
  - `static func selectRelease(from payload: Data, repository: String) throws -> UpdateRelease?`
  - `enum UpdateFeedError: LocalizedError { case serverAntwortet(Int), antwortUnlesbar }`
  - Konstanten `UpdateFeedClient.archiveAssetName`, `UpdateFeedClient.signatureAssetName`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

Create `BlitztextMac/Tests/UpdateFeedClientTests.swift`:

```swift
import XCTest

final class UpdateFeedClientTests: XCTestCase {
    private let repository = "geninOne/blitztext-app"

    private func release(
        tag: String,
        prerelease: Bool = false,
        draft: Bool = false,
        assets: [String] = [
            "Blitztext-macos-universal.zip",
            "Blitztext-macos-universal.zip.sig"
        ],
        host: String = "github.com"
    ) -> String {
        let assetJSON = assets.map { name in
            """
            {
              "name": "\(name)",
              "size": 4711,
              "browser_download_url": "https://\(host)/\(repository)/releases/download/\(tag)/\(name)"
            }
            """
        }.joined(separator: ",")

        return """
        {
          "tag_name": "\(tag)",
          "body": "Notizen zu \(tag)",
          "prerelease": \(prerelease),
          "draft": \(draft),
          "assets": [\(assetJSON)]
        }
        """
    }

    private func liste(_ eintraege: String...) -> Data {
        Data("[\(eintraege.joined(separator: ","))]".utf8)
    }

    func testNimmtDasNeuesteVollwertigeRelease() throws {
        let daten = liste(release(tag: "v1.6.0"), release(tag: "v1.5.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.6.0")
        XCTAssertEqual(treffer?.version, AppVersion(string: "1.6.0"))
        XCTAssertEqual(treffer?.releaseNotes, "Notizen zu v1.6.0")
        XCTAssertEqual(treffer?.archiveSize, 4711)
    }

    func testUeberspringtPrereleases() throws {
        let daten = liste(release(tag: "main-abc1234", prerelease: true), release(tag: "v1.5.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testUeberspringtEntwuerfe() throws {
        let daten = liste(release(tag: "v1.7.0", draft: true), release(tag: "v1.5.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testUeberspringtReleaseOhneMacArchiv() throws {
        let daten = liste(
            release(tag: "v1.6.0", assets: ["Blitztext_1.6.0_x64-setup.exe"]),
            release(tag: "v1.5.0")
        )
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testUeberspringtReleaseOhneSignatur() throws {
        let daten = liste(
            release(tag: "v1.6.0", assets: ["Blitztext-macos-universal.zip"]),
            release(tag: "v1.5.0")
        )
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testLehntFremdenHostAb() throws {
        let daten = liste(release(tag: "v1.6.0", host: "beispiel.invalid"), release(tag: "v1.5.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testLehntFremdesRepositoryAb() throws {
        let daten = liste(release(tag: "v1.6.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: "jemand/anders")
        XCTAssertNil(treffer)
    }

    func testUeberspringtUnleserlichesTag() throws {
        let daten = liste(release(tag: "release-final"), release(tag: "v1.5.0"))
        let treffer = try UpdateFeedClient.selectRelease(from: daten, repository: repository)
        XCTAssertEqual(treffer?.tagName, "v1.5.0")
    }

    func testLeereListeErgibtNil() throws {
        XCTAssertNil(try UpdateFeedClient.selectRelease(from: Data("[]".utf8), repository: repository))
    }
}
```

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdateFeedClientTests`
Expected: Übersetzungsfehler, `cannot find 'UpdateFeedClient' in scope`.

- [ ] **Step 3: UpdateRelease schreiben**

Create `BlitztextMac/Services/Update/UpdateRelease.swift`:

```swift
import Foundation

/// Ein veroeffentlichtes Release, das als Update in Frage kommt.
struct UpdateRelease: Equatable {
    let version: AppVersion
    let tagName: String
    let releaseNotes: String
    let archiveURL: URL
    let signatureURL: URL
    let archiveSize: Int
}
```

- [ ] **Step 4: UpdateFeedClient schreiben**

Create `BlitztextMac/Services/Update/UpdateFeedClient.swift`:

```swift
import Foundation

enum UpdateFeedError: LocalizedError {
    case serverAntwortet(Int)
    case antwortUnlesbar

    var errorDescription: String? {
        switch self {
        case .serverAntwortet(let code):
            return "GitHub hat mit Status \(code) geantwortet."
        case .antwortUnlesbar:
            return "Die Antwort von GitHub war nicht lesbar."
        }
    }
}

/// Liest die Release-Liste des Repositories und sucht das neueste
/// Nicht-Prerelease, das ein macOS-Archiv samt Signatur mitbringt.
///
/// Bewusst nicht `releases/latest`: Dieser Endpunkt liefert genau ein Release.
/// Fehlt darin das Mac-Archiv, weil ein Job fehlgeschlagen ist oder eine
/// Plattform einzeln released wurde, saehe die App nie wieder ein Update.
struct UpdateFeedClient {
    static let archiveAssetName = "Blitztext-macos-universal.zip"
    static let signatureAssetName = "Blitztext-macos-universal.zip.sig"

    let repository: String
    let session: URLSession

    init(repository: String, session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    func fetchNewestRelease() async throws -> UpdateRelease? {
        guard let url = URL(
            string: "https://api.github.com/repos/\(repository)/releases?per_page=20"
        ) else {
            throw UpdateFeedError.antwortUnlesbar
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Blitztext", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (daten, antwort) = try await session.data(for: request)
        guard let http = antwort as? HTTPURLResponse else {
            throw UpdateFeedError.antwortUnlesbar
        }
        guard http.statusCode == 200 else {
            throw UpdateFeedError.serverAntwortet(http.statusCode)
        }
        return try Self.selectRelease(from: daten, repository: repository)
    }

    /// Reine Auswahl-Logik ohne Netz. Die API liefert die Liste absteigend
    /// nach Erstellungsdatum, der erste Treffer ist also der neueste.
    static func selectRelease(from payload: Data, repository: String) throws -> UpdateRelease? {
        let eintraege: [GitHubRelease]
        do {
            eintraege = try JSONDecoder().decode([GitHubRelease].self, from: payload)
        } catch {
            throw UpdateFeedError.antwortUnlesbar
        }

        for eintrag in eintraege {
            guard !eintrag.prerelease, !eintrag.draft else { continue }
            guard let version = AppVersion(string: eintrag.tagName) else { continue }
            guard let archiv = eintrag.assets.first(where: { $0.name == archiveAssetName }),
                  let signatur = eintrag.assets.first(where: { $0.name == signatureAssetName })
            else { continue }
            guard let archivURL = validatedURL(archiv.browserDownloadURL, repository: repository),
                  let signaturURL = validatedURL(signatur.browserDownloadURL, repository: repository)
            else { continue }

            return UpdateRelease(
                version: version,
                tagName: eintrag.tagName,
                releaseNotes: eintrag.body ?? "",
                archiveURL: archivURL,
                signatureURL: signaturURL,
                archiveSize: archiv.size
            )
        }
        return nil
    }

    /// Akzeptiert nur HTTPS-Downloads von github.com im erwarteten Repo-Pfad.
    /// Die Weiterleitung auf objects.githubusercontent.com loest URLSession
    /// intern auf, den eigentlichen Inhalt sichert die Signatur.
    static func validatedURL(_ raw: String, repository: String) -> URL? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com",
              url.path.hasPrefix("/\(repository)/releases/download/")
        else { return nil }
        return url
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case prerelease
        case draft
        case assets
    }
}
```

- [ ] **Step 5: Dateien ins Testziel aufnehmen**

In `BlitztextMac/project.yml` beim Ziel `BlitztextMacTests` unter `sources` ergänzen:

```yaml
      - path: Services/Update/UpdateRelease.swift
      - path: Services/Update/UpdateFeedClient.swift
```

- [ ] **Step 6: Test laufen lassen, er muss bestehen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdateFeedClientTests`
Expected: alle neun Tests bestehen.

- [ ] **Step 7: Commit**

```bash
git add BlitztextMac/Services/Update/UpdateRelease.swift BlitztextMac/Services/Update/UpdateFeedClient.swift BlitztextMac/Tests/UpdateFeedClientTests.swift BlitztextMac/project.yml
git commit -m "$(cat <<'MSG'
Update: Feed-Client fuer die GitHub Releases

Sucht das neueste Nicht-Prerelease mit Mac-Archiv und Signatur statt
blind releases/latest zu nehmen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: UpdateSignatureVerifier

Der Vertrauensanker. Ohne ihn prüft niemand mehr, was installiert wird, weil ein selbst geladenes Archiv kein Quarantäne-Flag bekommt und der Gatekeeper deshalb nicht eingreift.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdateSignatureVerifier.swift`
- Create: `BlitztextMac/Tests/UpdateSignatureVerifierTests.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)

**Interfaces:**
- Consumes: nichts
- Produces: `enum UpdateSignatureVerifier` mit `static func isValid(signature: Data, for payload: Data, publicKeyBase64: String) -> Bool` und `static func signature(fromFileContents data: Data) -> Data?`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

Create `BlitztextMac/Tests/UpdateSignatureVerifierTests.swift`:

```swift
import XCTest
import CryptoKit

final class UpdateSignatureVerifierTests: XCTestCase {
    private let inhalt = Data("Blitztext 1.6.0".utf8)

    func testGueltigeSignaturWirdAkzeptiert() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertTrue(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: schluessel.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testFalscherSchluesselWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let fremder = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: fremder.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testManipulierterInhaltWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: Data("Blitztext 1.6.1".utf8),
            publicKeyBase64: schluessel.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testUnbrauchbarerSchluesselWirdAbgelehnt() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)

        XCTAssertFalse(UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: "kein base64 schluessel"
        ))
    }

    func testSignaturdateiWirdAusBase64Gelesen() throws {
        let schluessel = Curve25519.Signing.PrivateKey()
        let signatur = try schluessel.signature(for: inhalt)
        let dateiInhalt = Data((signatur.base64EncodedString() + "\n").utf8)

        XCTAssertEqual(UpdateSignatureVerifier.signature(fromFileContents: dateiInhalt), signatur)
    }

    func testUnleserlicheSignaturdateiErgibtNil() {
        XCTAssertNil(UpdateSignatureVerifier.signature(fromFileContents: Data("!!!".utf8)))
    }
}
```

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdateSignatureVerifierTests`
Expected: Übersetzungsfehler, `cannot find 'UpdateSignatureVerifier' in scope`.

- [ ] **Step 3: Implementierung schreiben**

Create `BlitztextMac/Services/Update/UpdateSignatureVerifier.swift`:

```swift
import CryptoKit
import Foundation

/// Prueft die Ed25519-Signatur eines Update-Archivs.
///
/// Ein von der App selbst geladenes Archiv bekommt kein Quarantaene-Flag,
/// deshalb prueft der Gatekeeper es nie. Diese Pruefung ist der einzige
/// Schutz davor, ein fremdes Bundle zu installieren.
enum UpdateSignatureVerifier {
    static func isValid(signature: Data, for payload: Data, publicKeyBase64: String) -> Bool {
        guard let schluesselDaten = Data(base64Encoded: publicKeyBase64),
              let schluessel = try? Curve25519.Signing.PublicKey(
                  rawRepresentation: schluesselDaten
              )
        else { return false }

        return schluessel.isValidSignature(signature, for: payload)
    }

    /// Die .sig-Datei enthaelt die Signatur als Base64-Text, moeglicherweise
    /// mit abschliessendem Zeilenumbruch.
    static func signature(fromFileContents data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
```

- [ ] **Step 4: Datei ins Testziel aufnehmen**

In `BlitztextMac/project.yml` beim Ziel `BlitztextMacTests` unter `sources` ergänzen:

```yaml
      - path: Services/Update/UpdateSignatureVerifier.swift
```

- [ ] **Step 5: Test laufen lassen, er muss bestehen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdateSignatureVerifierTests`
Expected: alle sechs Tests bestehen.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Services/Update/UpdateSignatureVerifier.swift BlitztextMac/Tests/UpdateSignatureVerifierTests.swift BlitztextMac/project.yml
git commit -m "$(cat <<'MSG'
Update: Ed25519-Pruefung fuer geladene Archive

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Schlüsselpaar, Signier-Skript und macOS-Workflow

Ab hier erzeugt die Pipeline signierte Releases. Ohne diesen Schritt findet die App nie eine gültige Signatur.

**Files:**
- Create: `Scripts/generate-update-key.swift`
- Create: `Scripts/sign-update.swift`
- Create: `BlitztextMac/Services/Update/UpdateConfiguration.swift`
- Modify: `BlitztextMac/Resources/Info.plist`
- Modify: `.github/workflows/macos-release.yml`

**Interfaces:**
- Consumes: nichts
- Produces: `enum UpdateConfiguration` mit `static var repository: String?`, `static var publicKey: String?`, `static var releasesPageURL: URL?`

- [ ] **Step 1: Schlüsselgenerator schreiben**

Create `Scripts/generate-update-key.swift`:

```swift
#!/usr/bin/env swift
// Erzeugt einmalig ein Ed25519-Schluesselpaar fuer die macOS-Update-Signatur.
// Nutzung: swift Scripts/generate-update-key.swift
//
// Der private Teil gehoert als Repo-Secret BLITZTEXT_UPDATE_PRIVATE_KEY
// hinterlegt und sonst nirgendwohin. Der oeffentliche Teil gehoert als
// BLZUpdatePublicKey in BlitztextMac/Resources/Info.plist.
import CryptoKit
import Foundation

let schluessel = Curve25519.Signing.PrivateKey()
print("Privat  (Secret BLITZTEXT_UPDATE_PRIVATE_KEY):")
print(schluessel.rawRepresentation.base64EncodedString())
print("")
print("Oeffentlich (Info.plist BLZUpdatePublicKey):")
print(schluessel.publicKey.rawRepresentation.base64EncodedString())
```

- [ ] **Step 2: Signier-Skript schreiben**

Create `Scripts/sign-update.swift`:

```swift
#!/usr/bin/env swift
// Signiert eine Datei mit dem Ed25519-Schluessel aus der Umgebung.
// Nutzung: swift Scripts/sign-update.swift <eingabe> <ausgabe.sig>
//
// Der private Schluessel kommt base64-kodiert aus der Umgebungsvariablen
// BLITZTEXT_UPDATE_PRIVATE_KEY. Geschrieben wird die Signatur als Base64-Text.
import CryptoKit
import Foundation

func abbrechen(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

let argumente = CommandLine.arguments
guard argumente.count == 3 else {
    abbrechen("Nutzung: swift Scripts/sign-update.swift <eingabe> <ausgabe.sig>")
}

guard let rohSchluessel = ProcessInfo.processInfo.environment["BLITZTEXT_UPDATE_PRIVATE_KEY"],
      let schluesselDaten = Data(base64Encoded: rohSchluessel.trimmingCharacters(in: .whitespacesAndNewlines))
else {
    abbrechen("BLITZTEXT_UPDATE_PRIVATE_KEY fehlt oder ist kein Base64.")
}

do {
    let schluessel = try Curve25519.Signing.PrivateKey(rawRepresentation: schluesselDaten)
    let inhalt = try Data(contentsOf: URL(fileURLWithPath: argumente[1]))
    let signatur = try schluessel.signature(for: inhalt)
    try Data(signatur.base64EncodedString().utf8)
        .write(to: URL(fileURLWithPath: argumente[2]))
    print("Signatur geschrieben: \(argumente[2])")
} catch {
    abbrechen("Signieren fehlgeschlagen: \(error.localizedDescription)")
}
```

- [ ] **Step 3: Schlüsselpaar erzeugen und beide Hälften einsetzen**

Run: `swift Scripts/generate-update-key.swift`

Den privaten Teil als Repo-Secret `BLITZTEXT_UPDATE_PRIVATE_KEY` hinterlegen (GitHub, Settings, Secrets and variables, Actions). Er darf nicht ins Repo und nicht in eine Konversation.

Den öffentlichen Teil in `BlitztextMac/Resources/Info.plist` eintragen, direkt vor `</dict>`:

```xml
	<key>BLZUpdateRepository</key>
	<string>geninOne/blitztext-app</string>
	<key>BLZUpdatePublicKey</key>
	<string>HIER_DEN_AUSGEGEBENEN_OEFFENTLICHEN_SCHLUESSEL_EINSETZEN</string>
```

- [ ] **Step 4: Signier-Schritt lokal prüfen**

```bash
export BLITZTEXT_UPDATE_PRIVATE_KEY="<privater schluessel aus schritt 3>"
echo "testinhalt" > /tmp/blitztext-signaturtest.txt
swift Scripts/sign-update.swift /tmp/blitztext-signaturtest.txt /tmp/blitztext-signaturtest.sig
cat /tmp/blitztext-signaturtest.sig
unset BLITZTEXT_UPDATE_PRIVATE_KEY
```

Expected: Eine Base64-Zeile wird ausgegeben, kein Fehler.

- [ ] **Step 5: UpdateConfiguration schreiben**

Create `BlitztextMac/Services/Update/UpdateConfiguration.swift`:

```swift
import Foundation

/// Update-Einstellungen aus dem Bundle. Ein Fork tauscht diese beiden Werte
/// in der Info.plist und muss sonst nichts am Code aendern.
enum UpdateConfiguration {
    static var repository: String? {
        wert(fuer: "BLZUpdateRepository")
    }

    static var publicKey: String? {
        wert(fuer: "BLZUpdatePublicKey")
    }

    /// Fallback fuer jeden Fehlerfall: die Release-Seite im Browser.
    static var releasesPageURL: URL? {
        guard let repository else { return nil }
        return URL(string: "https://github.com/\(repository)/releases/latest")
    }

    private static func wert(fuer schluessel: String) -> String? {
        guard let roh = Bundle.main.object(forInfoDictionaryKey: schluessel) as? String else {
            return nil
        }
        let bereinigt = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        return bereinigt.isEmpty ? nil : bereinigt
    }
}
```

- [ ] **Step 6: Workflow um Signatur erweitern**

In `.github/workflows/macos-release.yml` nach dem Schritt `Package app as zip` einfügen:

```yaml
      - name: Sign update archive
        if: github.event_name != 'pull_request'
        env:
          BLITZTEXT_UPDATE_PRIVATE_KEY: ${{ secrets.BLITZTEXT_UPDATE_PRIVATE_KEY }}
        run: |
          if [ -z "$BLITZTEXT_UPDATE_PRIVATE_KEY" ]; then
            echo "::error::Secret BLITZTEXT_UPDATE_PRIVATE_KEY fehlt, ohne Signatur kein Update-Asset."
            exit 1
          fi
          swift Scripts/sign-update.swift \
            Blitztext-macos-universal.zip \
            Blitztext-macos-universal.zip.sig
          ls -lh Blitztext-macos-universal.zip.sig
```

In beiden Veröffentlichungsschritten (`Publish prerelease (push to main)` und `Publish release (version tag)`) die Signatur mit hochladen. Aus

```
            Blitztext-macos-universal.zip \
```

wird jeweils

```
            Blitztext-macos-universal.zip \
            Blitztext-macos-universal.zip.sig \
```

und im jeweiligen `gh release upload`-Rückfall aus

```
          || gh release upload "$TAG" Blitztext-macos-universal.zip --clobber
```

wird

```
          || gh release upload "$TAG" Blitztext-macos-universal.zip Blitztext-macos-universal.zip.sig --clobber
```

Dasselbe für `$GITHUB_REF_NAME` im Tag-Schritt.

- [ ] **Step 7: XcodeGen laufen lassen und übersetzen**

Run: `./test.sh`
Expected: Projekt übersetzt, alle bestehenden Tests laufen weiter durch.

- [ ] **Step 8: Commit**

```bash
git add Scripts/generate-update-key.swift Scripts/sign-update.swift BlitztextMac/Services/Update/UpdateConfiguration.swift BlitztextMac/Resources/Info.plist .github/workflows/macos-release.yml
git commit -m "$(cat <<'MSG'
Update: Release-Archive werden signiert

Signier-Skript im Workflow, oeffentlicher Schluessel und Repository in
der Info.plist.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: UpdatePolicy

Rhythmus und Sperren als reine Funktionen, damit sie ohne Netz, Dateisystem und Oberfläche testbar sind. Der Controller aus Task 10 ruft sie nur auf.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdatePolicy.swift`
- Create: `BlitztextMac/Tests/UpdatePolicyTests.swift`
- Modify: `BlitztextMac/project.yml` (Testziel-Quellen)

**Interfaces:**
- Consumes: nichts
- Produces:
  - `enum UpdatePolicy`
  - `static func shouldRunAutomaticCheck(now: Date, lastCheck: Date?, automaticChecksEnabled: Bool, calendar: Calendar) -> Bool`
  - `enum InstallBlock: Equatable { case entwicklungsBuild, beschaeftigt }` mit `var hinweis: String`
  - `static func installBlock(isInApplicationsFolder: Bool, isBusy: Bool) -> InstallBlock?`

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

Create `BlitztextMac/Tests/UpdatePolicyTests.swift`:

```swift
import XCTest

final class UpdatePolicyTests: XCTestCase {
    private var kalender: Calendar = {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return kalender
    }()

    private func zeitpunkt(_ tag: Int, _ stunde: Int) -> Date {
        var komponenten = DateComponents()
        komponenten.year = 2026
        komponenten.month = 9
        komponenten.day = tag
        komponenten.hour = stunde
        return kalender.date(from: komponenten)!
    }

    func testOhneVorherigePruefungWirdGeprueft() {
        XCTAssertTrue(UpdatePolicy.shouldRunAutomaticCheck(
            now: zeitpunkt(7, 9),
            lastCheck: nil,
            automaticChecksEnabled: true,
            calendar: kalender
        ))
    }

    func testKeinZweiterCheckAmSelbenTag() {
        XCTAssertFalse(UpdatePolicy.shouldRunAutomaticCheck(
            now: zeitpunkt(7, 18),
            lastCheck: zeitpunkt(7, 9),
            automaticChecksEnabled: true,
            calendar: kalender
        ))
    }

    func testAmNaechstenTagWirdWiederGeprueft() {
        XCTAssertTrue(UpdatePolicy.shouldRunAutomaticCheck(
            now: zeitpunkt(8, 7),
            lastCheck: zeitpunkt(7, 23),
            automaticChecksEnabled: true,
            calendar: kalender
        ))
    }

    func testAbgeschalteterAutomatikPruefungUnterbleibt() {
        XCTAssertFalse(UpdatePolicy.shouldRunAutomaticCheck(
            now: zeitpunkt(8, 7),
            lastCheck: nil,
            automaticChecksEnabled: false,
            calendar: kalender
        ))
    }

    func testEntwicklungsBuildSperrtDieInstallation() {
        XCTAssertEqual(
            UpdatePolicy.installBlock(isInApplicationsFolder: false, isBusy: false),
            .entwicklungsBuild
        )
    }

    func testLaufendeArbeitSperrtDieInstallation() {
        XCTAssertEqual(
            UpdatePolicy.installBlock(isInApplicationsFolder: true, isBusy: true),
            .beschaeftigt
        )
    }

    func testEntwicklungsBuildSchlaegtBeschaeftigtSperreVor() {
        XCTAssertEqual(
            UpdatePolicy.installBlock(isInApplicationsFolder: false, isBusy: true),
            .entwicklungsBuild
        )
    }

    func testOhneSperreDarfInstalliertWerden() {
        XCTAssertNil(UpdatePolicy.installBlock(isInApplicationsFolder: true, isBusy: false))
    }

    func testJedeSperreHatEinenHinweis() {
        XCTAssertFalse(UpdatePolicy.InstallBlock.entwicklungsBuild.hinweis.isEmpty)
        XCTAssertFalse(UpdatePolicy.InstallBlock.beschaeftigt.hinweis.isEmpty)
    }
}
```

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdatePolicyTests`
Expected: Übersetzungsfehler, `cannot find 'UpdatePolicy' in scope`.

- [ ] **Step 3: Implementierung schreiben**

Create `BlitztextMac/Services/Update/UpdatePolicy.swift`:

```swift
import Foundation

/// Entscheidungen rund um Updates, bewusst als reine Funktionen ohne Netz,
/// Dateisystem und Oberflaeche, damit sie vollstaendig testbar sind.
enum UpdatePolicy {
    /// Beim Start und danach hoechstens einmal pro Kalendertag.
    static func shouldRunAutomaticCheck(
        now: Date,
        lastCheck: Date?,
        automaticChecksEnabled: Bool,
        calendar: Calendar
    ) -> Bool {
        guard automaticChecksEnabled else { return false }
        guard let lastCheck else { return true }
        return !calendar.isDate(lastCheck, inSameDayAs: now)
    }

    enum InstallBlock: Equatable {
        case entwicklungsBuild
        case beschaeftigt

        var hinweis: String {
            switch self {
            case .entwicklungsBuild:
                return "Dieser Build laeuft nicht aus dem Programme-Ordner. "
                    + "Aktualisiere ihn mit git pull und einem eigenen Build."
            case .beschaeftigt:
                return "Blitztext arbeitet gerade. Das Update laeuft, "
                    + "sobald Aufnahme und Warteschlange fertig sind."
            }
        }
    }

    /// Der Entwicklungs-Build wiegt schwerer: Dort gibt es gar keinen Button,
    /// waehrend die Beschaeftigt-Sperre nur voruebergehend ist.
    static func installBlock(isInApplicationsFolder: Bool, isBusy: Bool) -> InstallBlock? {
        if !isInApplicationsFolder { return .entwicklungsBuild }
        if isBusy { return .beschaeftigt }
        return nil
    }
}
```

- [ ] **Step 4: Datei ins Testziel aufnehmen**

In `BlitztextMac/project.yml` beim Ziel `BlitztextMacTests` unter `sources` ergänzen:

```yaml
      - path: Services/Update/UpdatePolicy.swift
```

- [ ] **Step 5: Test laufen lassen, er muss bestehen**

Run: `./test.sh -only-testing:BlitztextMacTests/UpdatePolicyTests`
Expected: alle neun Tests bestehen.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Services/Update/UpdatePolicy.swift BlitztextMac/Tests/UpdatePolicyTests.swift BlitztextMac/project.yml
git commit -m "$(cat <<'MSG'
Update: Rhythmus und Sperren als reine Funktionen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Neue Felder in AppSettings

Zwei persistierte Werte für Automatik und letzten Prüfzeitpunkt. Ohne Test, weil `AppSettings` in `WorkflowProtocol.swift` liegt und dessen Abhängigkeiten (`LocalTranscriptionService`) das Testziel unnötig aufblähen würden. Abgesichert wird das Muster durch `decodeIfPresent`, das im Bestand für jedes Feld schon so gehandhabt wird, und durch den manuellen Durchlauf in Task 16.

**Files:**
- Modify: `BlitztextMac/Features/Workflows/WorkflowProtocol.swift:160-232`

**Interfaces:**
- Consumes: nichts
- Produces: `AppSettings.automaticUpdateChecksEnabled: Bool` (Standard `true`), `AppSettings.lastUpdateCheck: Date?` (Standard `nil`)

- [ ] **Step 1: Gespeicherte Einstellungen sichern**

```bash
cp ~/Library/Application\ Support/Blitztext/settings.json /tmp/blitztext-settings-vorher.json 2>/dev/null || echo "Noch keine settings.json vorhanden."
```

- [ ] **Step 2: Felder ergänzen**

In `BlitztextMac/Features/Workflows/WorkflowProtocol.swift` bei `struct AppSettings` an vier Stellen ergänzen.

Nach `var liteLLMTranscriptionModel: String = "whisper-1"`:

```swift

    // Automatische Update-Pruefung, hoechstens einmal pro Kalendertag.
    var automaticUpdateChecksEnabled: Bool = true
    var lastUpdateCheck: Date?
```

In der Parameterliste von `init(...)` nach `liteLLMTranscriptionModel: String = "whisper-1"`:

```swift
,
        automaticUpdateChecksEnabled: Bool = true,
        lastUpdateCheck: Date? = nil
```

Im Rumpf von `init(...)` nach `self.liteLLMTranscriptionModel = liteLLMTranscriptionModel`:

```swift
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.lastUpdateCheck = lastUpdateCheck
```

In `enum CodingKeys` nach `case liteLLMTranscriptionModel`:

```swift
        case automaticUpdateChecksEnabled
        case lastUpdateCheck
```

In `init(from decoder:)` nach der Zuweisung von `liteLLMTranscriptionModel`:

```swift
        automaticUpdateChecksEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdateChecksEnabled
        ) ?? true
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
```

- [ ] **Step 3: Übersetzen und bestehende Tests laufen lassen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 4: Commit**

```bash
git add BlitztextMac/Features/Workflows/WorkflowProtocol.swift
git commit -m "$(cat <<'MSG'
Update: Einstellungen fuer die automatische Pruefung

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8: UpdateDownloader

Lädt Signatur und Archiv. Kein Unit-Test, weil die Einheit ausschließlich Netz und Dateisystem koppelt. Verifiziert wird sie im Durchlauf aus Task 16.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdateDownloader.swift`

**Interfaces:**
- Consumes: `UpdateRelease`, `UpdateFeedClient.archiveAssetName`, `UpdateSignatureVerifier.signature(fromFileContents:)`
- Produces: `final class UpdateDownloader` mit `func download(_ release: UpdateRelease, into ordner: URL, fortschritt: @escaping (Double) -> Void) async throws -> UpdateDownloader.Ergebnis`, `struct Ergebnis { let archivURL: URL; let signatur: Data }`, `enum UpdateDownloadError: LocalizedError`

- [ ] **Step 1: Implementierung schreiben**

Create `BlitztextMac/Services/Update/UpdateDownloader.swift`:

```swift
import Foundation

enum UpdateDownloadError: LocalizedError {
    case serverAntwortet(Int)
    case signaturFehlt
    case abgebrochen

    var errorDescription: String? {
        switch self {
        case .serverAntwortet(let code):
            return "Der Download endete mit Status \(code)."
        case .signaturFehlt:
            return "Zum Archiv gibt es keine lesbare Signatur."
        case .abgebrochen:
            return "Der Download wurde abgebrochen."
        }
    }
}

/// Laedt Signatur und Archiv eines Release in einen Zielordner.
///
/// Der Fortschritt kommt ueber den Delegate der klassischen Download-API.
/// Die async-Variante von URLSession meldet keinen Fortschritt, und ein
/// byteweises AsyncSequence waere bei einem Archiv dieser Groesse zu langsam.
final class UpdateDownloader: NSObject, @unchecked Sendable {
    struct Ergebnis {
        let archivURL: URL
        let signatur: Data
    }

    private var session: URLSession!
    private var fortschritt: ((Double) -> Void)?
    private var weiter: CheckedContinuation<URL, Error>?
    private var zielURL: URL?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func download(
        _ release: UpdateRelease,
        into ordner: URL,
        fortschritt: @escaping (Double) -> Void
    ) async throws -> Ergebnis {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        // Erst die Signatur, sie ist klein. Fehlt sie, sparen wir das Archiv.
        let signaturDaten = try await ladeKleineDatei(release.signatureURL)
        guard let signatur = UpdateSignatureVerifier.signature(fromFileContents: signaturDaten) else {
            throw UpdateDownloadError.signaturFehlt
        }

        let ziel = ordner.appendingPathComponent(UpdateFeedClient.archiveAssetName)
        try? FileManager.default.removeItem(at: ziel)

        self.fortschritt = fortschritt
        self.zielURL = ziel

        let archiv: URL = try await withCheckedThrowingContinuation { weiter in
            self.weiter = weiter
            session.downloadTask(with: release.archiveURL).resume()
        }
        return Ergebnis(archivURL: archiv, signatur: signatur)
    }

    private func ladeKleineDatei(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (daten, antwort) = try await URLSession.shared.data(for: request)
        guard let http = antwort as? HTTPURLResponse else {
            throw UpdateDownloadError.abgebrochen
        }
        guard http.statusCode == 200 else {
            throw UpdateDownloadError.serverAntwortet(http.statusCode)
        }
        return daten
    }
}

extension UpdateDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let anteil = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)
        fortschritt?(anteil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Die Datei an location verschwindet, sobald diese Methode zurueckkehrt.
        guard let ziel = zielURL else {
            beende(mit: .failure(UpdateDownloadError.abgebrochen))
            return
        }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateDownloadError.serverAntwortet(http.statusCode)
            }
            try FileManager.default.moveItem(at: location, to: ziel)
            beende(mit: .success(ziel))
        } catch {
            beende(mit: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        beende(mit: .failure(error))
    }

    private func beende(mit ergebnis: Result<URL, Error>) {
        guard let weiter else { return }
        self.weiter = nil
        switch ergebnis {
        case .success(let url): weiter.resume(returning: url)
        case .failure(let fehler): weiter.resume(throwing: fehler)
        }
    }
}
```

- [ ] **Step 2: Übersetzen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 3: Commit**

```bash
git add BlitztextMac/Services/Update/UpdateDownloader.swift
git commit -m "$(cat <<'MSG'
Update: Downloader fuer Archiv und Signatur

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 9: UpdateInstaller

Die riskanteste Einheit. Die Reihenfolge der Schritte ist die eigentliche Sicherheitsgarantie: Bis zum atomaren Tausch wird die bestehende Installation nicht angefasst.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdateInstaller.swift`

**Interfaces:**
- Consumes: `AppVersion`, `UpdateSignatureVerifier`, `BlitztextInstallLocationService.bundleURL`
- Produces: `enum UpdateInstaller` mit `static func verify(archiv: URL, signatur: Data, publicKeyBase64: String) throws` und `static func install(archiv: URL, erwarteteVersion: AppVersion) throws`, `enum UpdateInstallError: LocalizedError`

Die beiden Schritte sind getrennt, damit die Oberflaeche "pruefe Signatur" und "installiere" als eigene Zustaende zeigen kann und beide abseits des Hauptthreads laufen. Das Entpacken eines Archivs dieser Groesse auf dem Hauptthread wuerde die App sichtbar einfrieren.

- [ ] **Step 1: Implementierung schreiben**

Create `BlitztextMac/Services/Update/UpdateInstaller.swift`:

```swift
import AppKit
import Foundation

enum UpdateInstallError: LocalizedError {
    case signaturUngueltig
    case zielNichtBeschreibbar
    case entpackenFehlgeschlagen(String)
    case keinBundleImArchiv
    case fremdesBundle
    case nichtNeuer
    case tauschFehlgeschlagen(String)

    var errorDescription: String? {
        switch self {
        case .signaturUngueltig:
            return "Die Signatur des Downloads passt nicht. "
                + "Das Update wurde verworfen und nicht installiert."
        case .zielNichtBeschreibbar:
            return "Der Ordner mit der Blitztext-Installation ist nicht beschreibbar. "
                + "Pruefe die Rechte an /Applications."
        case .entpackenFehlgeschlagen(let text):
            return "Das Archiv liess sich nicht entpacken. \(text)"
        case .keinBundleImArchiv:
            return "Im Archiv steckt nicht genau eine App."
        case .fremdesBundle:
            return "Die App im Archiv gehoert nicht zu Blitztext."
        case .nichtNeuer:
            return "Die App im Archiv ist nicht neuer als die installierte Version."
        case .tauschFehlgeschlagen(let text):
            return "Der Austausch ist fehlgeschlagen, die bisherige Version "
                + "ist unveraendert. \(text)"
        }
    }
}

/// Tauscht das eigene App-Bundle gegen ein geprueftes Update.
///
/// Reihenfolge ist Absicht: Signatur, Entpacken neben dem Ziel, Bundle pruefen,
/// erst dann der atomare Tausch. Bis dahin bleibt die bestehende Installation
/// unangetastet, ein Abbruch kann sie also nicht beschaedigen.
enum UpdateInstaller {
    /// Schritt 1: Signatur pruefen. Schlaegt sie fehl, fliegt die Datei
    /// sofort raus und nichts weiter passiert.
    static func verify(archiv: URL, signatur: Data, publicKeyBase64: String) throws {
        let inhalt = try Data(contentsOf: archiv, options: .mappedIfSafe)
        guard UpdateSignatureVerifier.isValid(
            signature: signatur,
            for: inhalt,
            publicKeyBase64: publicKeyBase64
        ) else {
            try? FileManager.default.removeItem(at: archiv)
            throw UpdateInstallError.signaturUngueltig
        }
    }

    /// Schritte 2 bis 5. Setzt eine bestandene Pruefung voraus und beendet
    /// die App im Erfolgsfall, damit sie neu startet.
    static func install(archiv: URL, erwarteteVersion: AppVersion) throws {
        let eigenesBundle = BlitztextInstallLocationService.bundleURL
        let elternordner = eigenesBundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: elternordner.path) else {
            throw UpdateInstallError.zielNichtBeschreibbar
        }

        // 2. Entpacken neben das Ziel-Bundle. Gleiches Volume ist Pflicht,
        //    sonst ist replaceItemAt kein atomarer Rename mehr.
        let arbeitsordner = elternordner
            .appendingPathComponent(".blitztext-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: arbeitsordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: arbeitsordner) }

        try entpacke(archiv, nach: arbeitsordner)

        // 3. Pruefen, was da wirklich entpackt wurde.
        let neuesBundle = try pruefeBundle(in: arbeitsordner, erwarteteVersion: erwarteteVersion)

        // 4. Atomarer Tausch.
        do {
            _ = try FileManager.default.replaceItemAt(eigenesBundle, withItemAt: neuesBundle)
        } catch {
            throw UpdateInstallError.tauschFehlgeschlagen(error.localizedDescription)
        }

        // 5. Neustart.
        starteNeu(bundle: eigenesBundle)
    }

    private static func entpacke(_ archiv: URL, nach ordner: URL) throws {
        let prozess = Process()
        prozess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        prozess.arguments = ["-x", "-k", archiv.path, ordner.path]

        let fehlerkanal = Pipe()
        prozess.standardError = fehlerkanal
        try prozess.run()

        // Erst lesen, dann warten: readDataToEndOfFile blockiert bis das
        // Programm endet, umgekehrt koennte ein voller Puffer blockieren.
        let fehlertext = String(
            data: fehlerkanal.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        prozess.waitUntilExit()

        guard prozess.terminationStatus == 0 else {
            throw UpdateInstallError.entpackenFehlgeschlagen(fehlertext)
        }
    }

    private static func pruefeBundle(in ordner: URL, erwarteteVersion: AppVersion) throws -> URL {
        let inhalte = try FileManager.default.contentsOfDirectory(
            at: ordner,
            includingPropertiesForKeys: nil
        )
        let apps = inhalte.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let neu = apps.first else {
            throw UpdateInstallError.keinBundleImArchiv
        }

        guard let bundle = Bundle(url: neu),
              let identifier = bundle.bundleIdentifier,
              identifier == Bundle.main.bundleIdentifier
        else {
            throw UpdateInstallError.fremdesBundle
        }

        guard let roh = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(string: roh),
              let aktuell = AppVersion.current,
              version > aktuell,
              version == erwarteteVersion
        else {
            throw UpdateInstallError.nichtNeuer
        }
        return neu
    }

    private static func starteNeu(bundle: URL) {
        let prozess = Process()
        prozess.executableURL = URL(fileURLWithPath: "/bin/sh")
        prozess.arguments = ["-c", "sleep 1; /usr/bin/open \"\(bundle.path)\""]
        try? prozess.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Übersetzen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 3: Commit**

```bash
git add BlitztextMac/Services/Update/UpdateInstaller.swift
git commit -m "$(cat <<'MSG'
Update: atomarer Bundle-Tausch mit Vorpruefung

Signatur, Entpacken neben dem Ziel, Bundle-Pruefung, dann replaceItemAt.
Bis zum Tausch bleibt die bestehende Installation unangetastet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 10: UpdateController und Verdrahtung

Der Zustandsautomat, den die Oberfläche beobachtet, plus die Anbindung an `AppState` und den Start der automatischen Prüfung.

**Files:**
- Create: `BlitztextMac/Services/Update/UpdateController.swift`
- Modify: `BlitztextMac/Services/AppSupportPaths.swift`
- Modify: `BlitztextMac/App/AppState.swift`
- Modify: `BlitztextMac/App/BlitztextMacApp.swift`

**Interfaces:**
- Consumes: `UpdateConfiguration`, `UpdateFeedClient`, `UpdateDownloader`, `UpdateInstaller`, `UpdatePolicy`, `AppVersion`, `AppSettings.automaticUpdateChecksEnabled`, `AppSettings.lastUpdateCheck`
- Produces:
  - `AppSupportPaths.updatesDirectoryURL: URL`
  - `@MainActor @Observable final class UpdateController` mit `enum State`, `var state: State`, `var hasAvailableUpdate: Bool`, `var availableRelease: UpdateRelease?`, `var currentInstallBlock: UpdatePolicy.InstallBlock?`, `func checkForUpdates(manuell: Bool)`, `func startAutomaticCheckIfNeeded()`, `func installAvailableUpdate()`
  - `AppState.updateController: UpdateController`

- [ ] **Step 1: Update-Ordner in AppSupportPaths ergänzen**

In `BlitztextMac/Services/AppSupportPaths.swift` nach `dictationQueueURL` einfügen:

```swift
    static var updatesDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("updates", isDirectory: true)
    }
```

- [ ] **Step 2: UpdateController schreiben**

Create `BlitztextMac/Services/Update/UpdateController.swift`:

```swift
import Foundation
import Observation

/// Zustandsautomat fuer Updates. Die einzige Einheit, die die Oberflaeche
/// kennt. Sie liest nur `state` und ruft die drei Methoden auf.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading(Double)
        case verifying
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    var automaticChecksEnabled: Bool {
        didSet { onSettingsChange(automaticChecksEnabled, lastCheck) }
    }

    private let repository: String?
    private let publicKey: String?
    private let isBusy: @MainActor () -> Bool
    private let onSettingsChange: @MainActor (Bool, Date?) -> Void
    private var laufenderVorgang = false

    init(
        automaticChecksEnabled: Bool,
        lastCheck: Date?,
        repository: String? = UpdateConfiguration.repository,
        publicKey: String? = UpdateConfiguration.publicKey,
        isBusy: @escaping @MainActor () -> Bool,
        onSettingsChange: @escaping @MainActor (Bool, Date?) -> Void
    ) {
        self.automaticChecksEnabled = automaticChecksEnabled
        self.lastCheck = lastCheck
        self.repository = repository
        self.publicKey = publicKey
        self.isBusy = isBusy
        self.onSettingsChange = onSettingsChange
    }

    var availableRelease: UpdateRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var hasAvailableUpdate: Bool {
        availableRelease != nil
    }

    var currentInstallBlock: UpdatePolicy.InstallBlock? {
        UpdatePolicy.installBlock(
            isInApplicationsFolder: BlitztextInstallLocationService
                .currentInstallLocation
                .isInApplicationsFolder,
            isBusy: isBusy()
        )
    }

    /// Beim Programmstart aufrufen. Prueft nur, wenn die Automatik an ist und
    /// heute noch nicht geprueft wurde.
    func startAutomaticCheckIfNeeded() {
        guard UpdatePolicy.shouldRunAutomaticCheck(
            now: Date(),
            lastCheck: lastCheck,
            automaticChecksEnabled: automaticChecksEnabled,
            calendar: Calendar.current
        ) else { return }
        checkForUpdates(manuell: false)
    }

    func checkForUpdates(manuell: Bool) {
        guard !laufenderVorgang else { return }
        guard let repository else {
            if manuell { state = .failed("In dieser App ist kein Update-Repository hinterlegt.") }
            return
        }

        laufenderVorgang = true
        state = .checking

        Task { [weak self] in
            guard let self else { return }
            defer { self.laufenderVorgang = false }
            do {
                let client = UpdateFeedClient(repository: repository)
                let treffer = try await client.fetchNewestRelease()
                self.merkePruefzeitpunkt()

                guard let treffer, let aktuell = AppVersion.current, treffer.version > aktuell else {
                    self.state = .upToDate
                    return
                }
                self.state = .available(treffer)
            } catch {
                // Der automatische Check scheitert still, damit ein fehlendes
                // Netz beim Start niemanden stoert.
                self.state = manuell ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available(let release) = state, !laufenderVorgang else { return }
        if let sperre = currentInstallBlock {
            state = .failed(sperre.hinweis)
            return
        }
        guard let publicKey else {
            state = .failed("In dieser App ist kein Update-Schluessel hinterlegt.")
            return
        }

        laufenderVorgang = true
        state = .downloading(0)

        Task { [weak self] in
            guard let self else { return }
            defer { self.laufenderVorgang = false }
            do {
                let downloader = UpdateDownloader()
                let ergebnis = try await downloader.download(
                    release,
                    into: AppSupportPaths.updatesDirectoryURL
                ) { anteil in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(anteil)
                    }
                }

                // Beide Schritte abseits des Hauptthreads, sonst friert die
                // Oberflaeche waehrend des Entpackens ein.
                self.state = .verifying
                try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.verify(
                        archiv: ergebnis.archivURL,
                        signatur: ergebnis.signatur,
                        publicKeyBase64: publicKey
                    )
                }.value

                self.state = .installing
                try await Task.detached(priority: .userInitiated) {
                    // Beendet die App im Erfolgsfall, damit sie neu startet.
                    try UpdateInstaller.install(
                        archiv: ergebnis.archivURL,
                        erwarteteVersion: release.version
                    )
                }.value
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func merkePruefzeitpunkt() {
        lastCheck = Date()
        onSettingsChange(automaticChecksEnabled, lastCheck)
    }
}
```

- [ ] **Step 3: Controller in AppState halten**

In `BlitztextMac/App/AppState.swift` nach der Zeile `var dictationQueueCount = 0` (Zeile 67) einfügen:

```swift
    private(set) lazy var updateController: UpdateController = {
        UpdateController(
            automaticChecksEnabled: appSettings.automaticUpdateChecksEnabled,
            lastCheck: appSettings.lastUpdateCheck,
            isBusy: { [weak self] in
                guard let self else { return false }
                return (self.activeWorkflow?.phase.isActive ?? false) || self.dictationQueueCount > 0
            },
            onSettingsChange: { [weak self] automatik, zeitpunkt in
                guard let self else { return }
                self.appSettings.automaticUpdateChecksEnabled = automatik
                self.appSettings.lastUpdateCheck = zeitpunkt
            }
        )
    }()
```

- [ ] **Step 4: Automatische Prüfung beim Start auslösen**

In `BlitztextMac/App/BlitztextMacApp.swift` in `applicationDidFinishLaunching`, direkt vor dem abschließenden `DispatchQueue.main.async` Block mit `showOnboardingIfNeeded`:

```swift
        appState.updateController.startAutomaticCheckIfNeeded()
```

- [ ] **Step 5: Übersetzen und Tests laufen lassen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Services/Update/UpdateController.swift BlitztextMac/Services/AppSupportPaths.swift BlitztextMac/App/AppState.swift BlitztextMac/App/BlitztextMacApp.swift
git commit -m "$(cat <<'MSG'
Update: Zustandsautomat und Verdrahtung im AppState

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 11: Oberfläche in Settings und Menüleiste

**Files:**
- Modify: `BlitztextMac/Features/Settings/SettingsContentView.swift:328-357`
- Modify: `BlitztextMac/Features/MenuBar/MenuBarView.swift:636-648`

**Interfaces:**
- Consumes: `AppState.updateController`
- Produces: nichts für spätere Tasks

- [ ] **Step 1: Update-Abschnitt in den Settings ersetzen**

In `BlitztextMac/Features/Settings/SettingsContentView.swift` den kompletten Block ersetzen, der mit `SectionLabel(text: "Updates")` beginnt und mit dem `else`-Zweig zu `Text("Updates sind in dieser Preview manuell: pull, build, starten.")` endet. Neuer Block:

```swift
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Updates")

                Text("Installiert: Version \(Self.installierteVersion)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                switch appState.updateController.state {
                case .idle:
                    Text(letztePruefungText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .checking:
                    Text("Suche nach Updates ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .upToDate:
                    Text("Blitztext ist aktuell. \(letztePruefungText)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .available(let release):
                    Text("Version \(release.version.description) ist verfuegbar.")
                        .font(.system(size: 11, weight: .medium))

                    if !release.releaseNotes.isEmpty {
                        Text(release.releaseNotes.prefix(400))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sperre = appState.updateController.currentInstallBlock {
                        Text(sperre.hinweis)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button("Version \(release.version.description) laden und installieren") {
                            appState.updateController.installAvailableUpdate()
                        }
                        .buttonStyle(SubtleButtonStyle())

                        Text("Blitztext startet sich fuer das Update neu.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                case .downloading(let anteil):
                    Text("Lade Update ... \(Int(anteil * 100)) Prozent")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .verifying:
                    Text("Pruefe die Signatur ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .installing:
                    Text("Installiere und starte neu ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                case .failed(let text):
                    Text(text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("Nach Updates suchen") {
                        appState.updateController.checkForUpdates(manuell: true)
                    }
                    .buttonStyle(SubtleButtonStyle())

                    if let seite = UpdateConfiguration.releasesPageURL {
                        Button("Releases im Browser") {
                            NSWorkspace.shared.open(seite)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                Toggle("Automatisch nach Updates suchen", isOn: Binding(
                    get: { appState.updateController.automaticChecksEnabled },
                    set: { appState.updateController.automaticChecksEnabled = $0 }
                ))
                .toggleStyle(.switch)

                if !currentInstallLocation.isCanonicalInstall {
                    Text("Hotkeys und Login-Start laufen am stabilsten, "
                        + "wenn Blitztext aus /Applications gestartet wird.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
```

- [ ] **Step 2: Zwei Hilfen für den Abschnitt ergänzen**

In `struct AccessSettingsView` unterhalb von `var body: some View { ... }`, also als weitere Member der Struktur, einfügen:

```swift
    private static let installierteVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    private var letztePruefungText: String {
        guard let zeitpunkt = appState.updateController.lastCheck else {
            return "Noch nicht nach Updates gesucht."
        }
        let formatierer = DateFormatter()
        formatierer.dateStyle = .medium
        formatierer.timeStyle = .short
        return "Zuletzt geprueft: \(formatierer.string(from: zeitpunkt))"
    }
```

- [ ] **Step 3: Punkt in den Menüleisten-Footer setzen**

In `BlitztextMac/Features/MenuBar/MenuBarView.swift` im `appFooter` den `.overlay(alignment: .trailing)`-Block ersetzen durch:

```swift
        .overlay(alignment: .trailing) {
            Button {
                appState.page = .settings
            } label: {
                HStack(spacing: 4) {
                    if appState.updateController.hasAvailableUpdate {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                    Text("v\(Self.appVersion)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            }
            .buttonStyle(.plain)
            .help(appState.updateController.hasAvailableUpdate
                ? "Ein Update ist verfuegbar"
                : "Einstellungen oeffnen")
            .padding(.trailing, 12)
        }
```

- [ ] **Step 4: Übersetzen und Tests laufen lassen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 5: App starten und den Abschnitt ansehen**

Run: `./build.sh --run`
Expected: In den Einstellungen unter Zugang steht der neue Update-Abschnitt mit installierter Version, dem Knopf "Nach Updates suchen" und dem Schalter. Ein Klick auf den Knopf endet je nach Release-Lage in "Blitztext ist aktuell" oder in einem Update-Angebot.

- [ ] **Step 6: Commit**

```bash
git add BlitztextMac/Features/Settings/SettingsContentView.swift BlitztextMac/Features/MenuBar/MenuBarView.swift
git commit -m "$(cat <<'MSG'
Update: Oberflaeche in Einstellungen und Menueleiste

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 12: Update-Ordner beim Start aufräumen

Ein abgebrochener Download darf nicht dauerhaft Platz belegen.

**Files:**
- Modify: `BlitztextMac/Services/BlitztextCleanupService.swift`
- Modify: `BlitztextMac/App/BlitztextMacApp.swift`

**Interfaces:**
- Consumes: `AppSupportPaths.updatesDirectoryURL`
- Produces: `BlitztextCleanupService.removeStaleUpdateDownloads()`

- [ ] **Step 1: Aufräumfunktion ergänzen**

In `BlitztextMac/Services/BlitztextCleanupService.swift` innerhalb von `enum BlitztextCleanupService` als weitere statische Funktion einfügen:

```swift
    /// Loescht Reste abgebrochener Update-Downloads. Wird beim Start gerufen,
    /// dann laeuft garantiert kein Download.
    static func removeStaleUpdateDownloads() {
        try? FileManager.default.removeItem(at: AppSupportPaths.updatesDirectoryURL)
    }
```

- [ ] **Step 2: Beim Start aufrufen**

In `BlitztextMac/App/BlitztextMacApp.swift` in `applicationDidFinishLaunching` direkt vor der Zeile `appState.updateController.startAutomaticCheckIfNeeded()`:

```swift
        BlitztextCleanupService.removeStaleUpdateDownloads()
```

- [ ] **Step 3: Übersetzen und Tests laufen lassen**

Run: `./test.sh`
Expected: Übersetzung ohne Fehler, alle bisherigen Tests bestehen.

- [ ] **Step 4: Commit**

```bash
git add BlitztextMac/Services/BlitztextCleanupService.swift BlitztextMac/App/BlitztextMacApp.swift
git commit -m "$(cat <<'MSG'
Update: Reste abgebrochener Downloads beim Start entfernen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

**Ab hier ist der macOS-Teil vollständig. Die folgenden Tasks ergänzen Windows.**

---

### Task 13: Tauri-Updater einbinden

Hier wird nichts selbst gebaut. Das offizielle Plugin bringt Signaturprüfung, Download, Installation und Neustart mit.

**Files:**
- Modify: `BlitztextWin/package.json`
- Modify: `BlitztextWin/src-tauri/Cargo.toml`
- Modify: `BlitztextWin/src-tauri/src/lib.rs`
- Modify: `BlitztextWin/src-tauri/capabilities/default.json`
- Modify: `BlitztextWin/src-tauri/tauri.conf.json`

**Interfaces:**
- Consumes: nichts
- Produces: die Tauri-Kommandos des Plugins, im Frontend über `@tauri-apps/plugin-updater` (`check`) und `@tauri-apps/plugin-process` (`relaunch`) erreichbar

- [ ] **Step 1: Pakete installieren**

```bash
cd BlitztextWin
npm install @tauri-apps/plugin-updater @tauri-apps/plugin-process
```

- [ ] **Step 2: Rust-Abhängigkeiten ergänzen**

In `BlitztextWin/src-tauri/Cargo.toml` bei den `tauri-plugin-*`-Einträgen ergänzen:

```toml
tauri-plugin-updater = "2"
tauri-plugin-process = "2"
```

- [ ] **Step 3: Plugins registrieren**

In `BlitztextWin/src-tauri/src/lib.rs` in der Builder-Kette, direkt bei den anderen `.plugin(...)`-Aufrufen:

```rust
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
```

- [ ] **Step 4: Berechtigungen ergänzen**

In `BlitztextWin/src-tauri/capabilities/default.json` die Liste `permissions` erweitern:

```json
  "permissions": [
    "core:default",
    "opener:default",
    "updater:default",
    "process:allow-restart"
  ]
```

Ohne diese Einträge scheitert der Aufruf erst zur Laufzeit, nicht beim Bauen.

- [ ] **Step 5: Schlüsselpaar erzeugen**

```bash
cd BlitztextWin
npm run tauri signer generate -- -w "$HOME/.tauri/blitztext-win.key"
```

Das Kommando fragt nach einem Passwort und gibt anschließend den öffentlichen Schlüssel aus. Drei Dinge daraus:

- Inhalt von `~/.tauri/blitztext-win.key` als Repo-Secret `TAURI_SIGNING_PRIVATE_KEY`
- das gewählte Passwort als Repo-Secret `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`
- den öffentlichen Schlüssel für den nächsten Schritt

Der private Schlüssel darf nicht ins Repo. Er ist ein anderer als der macOS-Schlüssel und wird nie mit ihm vermischt.

- [ ] **Step 6: Tauri-Konfiguration ergänzen**

In `BlitztextWin/src-tauri/tauri.conf.json` im `bundle`-Block ergänzen:

```json
    "createUpdaterArtifacts": true,
```

Und auf oberster Ebene, neben `app` und `bundle`, einen neuen `plugins`-Block:

```json
  "plugins": {
    "updater": {
      "pubkey": "HIER_DEN_OEFFENTLICHEN_TAURI_SCHLUESSEL_EINSETZEN",
      "endpoints": [
        "https://github.com/geninOne/blitztext-app/releases/latest/download/latest.json"
      ],
      "windows": {
        "installMode": "passive"
      }
    }
  }
```

Der Endpunkt zeigt auf `releases/latest/download/`. GitHub löst das auf das neueste Nicht-Prerelease auf, damit sind die `main`-Builds ohne Zusatzlogik draußen, genau wie auf der Mac-Seite.

- [ ] **Step 7: Bauen und prüfen**

```bash
cd BlitztextWin
npm run tauri build
```

Expected: Der Build läuft durch. Ohne gesetzte Signier-Umgebung warnt Tauri, dass keine Update-Artefakte signiert werden. Das ist an dieser Stelle in Ordnung, der Workflow setzt die Variablen in Task 14.

- [ ] **Step 8: Commit**

```bash
cd ..
git add BlitztextWin/package.json BlitztextWin/package-lock.json BlitztextWin/src-tauri/Cargo.toml BlitztextWin/src-tauri/Cargo.lock BlitztextWin/src-tauri/src/lib.rs BlitztextWin/src-tauri/capabilities/default.json BlitztextWin/src-tauri/tauri.conf.json
git commit -m "$(cat <<'MSG'
Update: tauri-plugin-updater eingebunden

Plugin, Berechtigungen, oeffentlicher Schluessel und Endpunkt auf das
latest.json im GitHub Release.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 14: Update-Manifest und Windows-Workflow

Das Plugin erwartet ein eigenes JSON-Format, das die GitHub-API nicht liefert. Der Workflow erzeugt es nach dem Build.

**Files:**
- Create: `BlitztextWin/scripts/make-updater-manifest.mjs`
- Modify: `.github/workflows/windows-release.yml`

**Interfaces:**
- Consumes: `BlitztextWin/src-tauri/tauri.conf.json` (Feld `version`), die vom Bundler erzeugten NSIS-Artefakte
- Produces: `latest.json` als Release-Asset

- [ ] **Step 1: Manifest-Generator schreiben**

Create `BlitztextWin/scripts/make-updater-manifest.mjs`:

```js
// Erzeugt das latest.json, das tauri-plugin-updater erwartet.
// Nutzung: node scripts/make-updater-manifest.mjs <tag> <ausgabedatei>
//
// Die Signatur ist der Inhalt der vom Bundler erzeugten .sig-Datei, nicht
// ihr Pfad. Die Version kommt aus tauri.conf.json und ist durch den
// Versions-Guard garantiert identisch mit dem Tag.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const REPOSITORY = "geninOne/blitztext-app";
const NSIS_ORDNER = "src-tauri/target/release/bundle/nsis";

const [, , tag, ausgabe] = process.argv;
if (!tag || !ausgabe) {
  console.error("Nutzung: node scripts/make-updater-manifest.mjs <tag> <ausgabedatei>");
  process.exit(2);
}

const dateien = readdirSync(NSIS_ORDNER);
const setup = dateien.find((name) => name.endsWith("-setup.exe"));
const signaturDatei = dateien.find((name) => name.endsWith("-setup.exe.sig"));

if (!setup || !signaturDatei) {
  console.error(
    `Kein signiertes NSIS-Setup in ${NSIS_ORDNER}. Gefunden: ${dateien.join(", ") || "nichts"}`
  );
  process.exit(1);
}

const version = JSON.parse(readFileSync("src-tauri/tauri.conf.json", "utf8")).version;
const signature = readFileSync(join(NSIS_ORDNER, signaturDatei), "utf8").trim();

const manifest = {
  version,
  notes: `Blitztext ${tag}`,
  pub_date: new Date().toISOString(),
  platforms: {
    "windows-x86_64": {
      signature,
      url: `https://github.com/${REPOSITORY}/releases/download/${tag}/${setup}`,
    },
  },
};

writeFileSync(ausgabe, JSON.stringify(manifest, null, 2));
console.log(`Manifest geschrieben: ${ausgabe}`);
console.log(JSON.stringify(manifest, null, 2));
```

- [ ] **Step 2: Signieren im Build-Schritt aktivieren**

In `.github/workflows/windows-release.yml` den Schritt `Build Tauri app (Release)` um die Umgebung erweitern:

```yaml
      - name: Build Tauri app (Release)
        env:
          TAURI_SIGNING_PRIVATE_KEY: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
          TAURI_SIGNING_PRIVATE_KEY_PASSWORD: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY_PASSWORD }}
        run: npm run tauri build
```

- [ ] **Step 3: Manifest erzeugen und prüfen**

In `.github/workflows/windows-release.yml` nach dem Schritt `Collect installers` einfügen:

```yaml
      - name: Build updater manifest
        if: startsWith(github.ref, 'refs/tags/v')
        shell: bash
        run: node scripts/make-updater-manifest.mjs "$GITHUB_REF_NAME" "$GITHUB_WORKSPACE/dist-installers/latest.json"

      - name: Validate updater manifest
        if: startsWith(github.ref, 'refs/tags/v')
        shell: bash
        working-directory: ${{ github.workspace }}
        run: |
          jq -e '.version
            and .platforms["windows-x86_64"].signature
            and (.platforms["windows-x86_64"].url | startswith("https://github.com/"))' \
            dist-installers/latest.json > /dev/null
          echo "Manifest ist vollstaendig."
```

Das Manifest landet in `dist-installers/`, deshalb lädt der bestehende Schritt `Publish release (version tag)` es über `dist-installers/*` ohne weitere Änderung mit hoch.

- [ ] **Step 4: Generator lokal prüfen**

Der Generator braucht einen fertigen Build. Falls Task 13 Step 7 schon gelaufen ist:

```bash
cd BlitztextWin
node scripts/make-updater-manifest.mjs v1.6.0 /tmp/blitztext-latest.json
cat /tmp/blitztext-latest.json
```

Expected: Ohne signierten Build bricht das Skript mit der Meldung ab, dass kein `-setup.exe.sig` gefunden wurde. Das ist das richtige Verhalten. Mit gesetzten Signier-Variablen und einem frischen Build entsteht ein Manifest mit `version`, `signature` und einer `github.com`-URL.

- [ ] **Step 5: Commit**

```bash
cd ..
git add BlitztextWin/scripts/make-updater-manifest.mjs .github/workflows/windows-release.yml
git commit -m "$(cat <<'MSG'
Update: latest.json fuer den Windows-Updater im Release

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 15: Windows-Oberfläche und Sperren

Gleiches Konzept und gleicher Wortlaut wie auf dem Mac, in der bestehenden Popover-Oberfläche.

**Files:**
- Modify: `BlitztextWin/src/config.ts`
- Modify: `BlitztextWin/index.html:319-325`
- Modify: `BlitztextWin/src/popover.ts`

**Interfaces:**
- Consumes: `check` aus `@tauri-apps/plugin-updater`, `relaunch` aus `@tauri-apps/plugin-process`
- Produces: `Settings.automaticUpdateChecks: boolean`, `Settings.lastUpdateCheck: string | null`

- [ ] **Step 1: Einstellungen erweitern**

In `BlitztextWin/src/config.ts` im `interface Settings` nach `hotkeyMode: HotkeyMode;` einfügen:

```ts
  // Automatische Update-Pruefung, hoechstens einmal pro Kalendertag.
  automaticUpdateChecks: boolean;
  // ISO-Zeitstempel der letzten Pruefung, null wenn noch nie geprueft.
  lastUpdateCheck: string | null;
```

In `defaultSettings` nach `hotkeyMode: "hold",`:

```ts
  automaticUpdateChecks: true,
  lastUpdateCheck: null,
```

Der bestehende `...parsed`-Spread in `loadSettings` übernimmt beide Felder automatisch, alte gespeicherte Einstellungen fallen auf die Standardwerte zurück.

- [ ] **Step 2: Markup ergänzen**

In `BlitztextWin/index.html` direkt nach dem Abschnitt "Beim Anmelden" (nach dessen schließendem `</div>`) einfügen:

```html
            <div class="section">
              <div class="section-label">Updates</div>
              <p id="update-installed" class="field-status"></p>
              <p id="update-status" class="field-status"></p>
              <div class="actions">
                <button type="button" id="update-check">Nach Updates suchen</button>
                <button type="button" id="update-install" hidden>Installieren</button>
              </div>
              <label class="switch-row">
                <input type="checkbox" id="update-automatic" />
                Automatisch nach Updates suchen
              </label>
            </div>
```

- [ ] **Step 3: Logik ergänzen**

In `BlitztextWin/src/popover.ts` bei den übrigen Importen ergänzen:

```ts
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import { getVersion } from "@tauri-apps/api/app";
```

Und nach dem Autostart-Block (um Zeile 426) den folgenden Abschnitt einfügen. Die beiden Zustandsvariablen `recording` und `busy` sind in `popover.ts:151-152` bereits vorhanden und liegen im selben Gültigkeitsbereich.

```ts
  // Updates
  const updateInstalledEl = el<HTMLParagraphElement>("update-installed");
  const updateStatusEl = el<HTMLParagraphElement>("update-status");
  const updateCheckEl = el<HTMLButtonElement>("update-check");
  const updateInstallEl = el<HTMLButtonElement>("update-install");
  const updateAutomaticEl = el<HTMLInputElement>("update-automatic");

  let verfuegbaresUpdate: Update | null = null;

  getVersion().then((version) => {
    updateInstalledEl.textContent = `Installiert: Version ${version}`;
  });

  updateAutomaticEl.checked = settings.automaticUpdateChecks;
  updateAutomaticEl.addEventListener("change", () => {
    settings.automaticUpdateChecks = updateAutomaticEl.checked;
    saveSettings(settings);
  });

  function letztePruefungText(): string {
    if (!settings.lastUpdateCheck) return "Noch nicht nach Updates gesucht.";
    return `Zuletzt geprueft: ${new Date(settings.lastUpdateCheck).toLocaleString("de-DE")}`;
  }

  function amSelbenTag(a: Date, b: Date): boolean {
    return a.toDateString() === b.toDateString();
  }

  async function pruefeAufUpdates(manuell: boolean): Promise<void> {
    // Im Entwicklungs-Build gibt es kein Release, gegen das geprueft wuerde.
    if (import.meta.env.DEV) {
      if (manuell) {
        updateStatusEl.textContent =
          "Entwicklungs-Build. Updates kommen ueber einen eigenen Build.";
      }
      return;
    }

    updateStatusEl.textContent = "Suche nach Updates ...";
    try {
      const treffer = await check();
      settings.lastUpdateCheck = new Date().toISOString();
      saveSettings(settings);

      if (!treffer) {
        verfuegbaresUpdate = null;
        updateInstallEl.hidden = true;
        updateStatusEl.textContent = `Blitztext ist aktuell. ${letztePruefungText()}`;
        return;
      }

      verfuegbaresUpdate = treffer;
      updateInstallEl.hidden = false;
      updateInstallEl.textContent = `Version ${treffer.version} laden und installieren`;
      updateStatusEl.textContent = `Version ${treffer.version} ist verfuegbar. `
        + "Blitztext startet sich fuer das Update neu.";
    } catch (error) {
      verfuegbaresUpdate = null;
      updateInstallEl.hidden = true;
      // Der automatische Check scheitert still, damit ein fehlendes Netz
      // beim Start niemanden stoert. Ein 404 heisst nur, dass das neueste
      // Release kein Windows-Manifest enthaelt.
      updateStatusEl.textContent = manuell ? `Update-Pruefung fehlgeschlagen: ${error}` : "";
    }
  }

  updateCheckEl.addEventListener("click", () => {
    void pruefeAufUpdates(true);
  });

  updateInstallEl.addEventListener("click", async () => {
    if (!verfuegbaresUpdate) return;
    if (recording || busy) {
      updateStatusEl.textContent =
        "Blitztext nimmt gerade auf. Das Update laeuft, sobald die Aufnahme fertig ist.";
      return;
    }

    updateInstallEl.disabled = true;
    try {
      await verfuegbaresUpdate.downloadAndInstall((fortschritt) => {
        if (fortschritt.event === "Progress") {
          updateStatusEl.textContent = "Lade Update ...";
        }
        if (fortschritt.event === "Finished") {
          updateStatusEl.textContent = "Installiere und starte neu ...";
        }
      });
      await relaunch();
    } catch (error) {
      updateStatusEl.textContent = `Installation fehlgeschlagen: ${error}`;
      updateInstallEl.disabled = false;
    }
  });

  updateStatusEl.textContent = letztePruefungText();

  // Beim Start pruefen, danach hoechstens einmal pro Kalendertag.
  const letzte = settings.lastUpdateCheck ? new Date(settings.lastUpdateCheck) : null;
  if (settings.automaticUpdateChecks && (!letzte || !amSelbenTag(letzte, new Date()))) {
    void pruefeAufUpdates(false);
  }
```

- [ ] **Step 4: Hinweis zum unsignierten Installer ergänzen**

In `BlitztextWin/index.html` innerhalb des neuen Update-Abschnitts, direkt vor dem schließenden `</div>`:

```html
              <p class="field-status">
                Der Installer ist nicht signiert. Windows SmartScreen kann beim
                Ausfuehren einmal warnen.
              </p>
```

- [ ] **Step 5: Punkt im Menü-View setzen**

Der Menü-View zeigt keine Versionsnummer, deshalb sitzt der Hinweis am Zahnrad im Kopf des Menü-Views (`index.html:180`). In `BlitztextWin/src/popover.ts` neben den übrigen Update-Funktionen ergänzen:

```ts
  function zeigeUpdateHinweis(sichtbar: boolean): void {
    const gear = el<HTMLButtonElement>("gear");
    gear.textContent = sichtbar ? "⚙•" : "⚙";
    gear.title = sichtbar ? "Ein Update ist verfuegbar" : "Einstellungen";
  }
```

Und in `pruefeAufUpdates` nach jedem Setzen von `verfuegbaresUpdate` aufrufen: `zeigeUpdateHinweis(verfuegbaresUpdate !== null);`

- [ ] **Step 6: Übersetzen und starten**

```bash
cd BlitztextWin
npm run build
npm run tauri dev
```

Expected: TypeScript übersetzt ohne Fehler. In den Einstellungen unter Zugang steht der Update-Abschnitt. Im Entwicklungs-Build meldet "Nach Updates suchen" den Entwicklungs-Hinweis.

- [ ] **Step 7: Commit**

```bash
cd ..
git add BlitztextWin/src/config.ts BlitztextWin/index.html BlitztextWin/src/popover.ts
git commit -m "$(cat <<'MSG'
Update: Update-Abschnitt in der Windows-Oberflaeche

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 16: Manuelle Verifikation beider Plattformen

Der Installer beider Apps lässt sich nicht sinnvoll automatisiert testen: Er braucht ein echtes Release, das echte Dateisystem und einen Neustart. Dieser Durchlauf ist die Abnahme.

**Files:**
- Keine Änderungen, außer den Korrekturen, die sich aus dem Durchlauf ergeben.

**Interfaces:**
- Consumes: alles aus Tasks 1 bis 15
- Produces: nichts

- [ ] **Step 1: Zweig zusammenführen und Tag setzen**

Voraussetzung: Alle vorherigen Tasks sind gemerged und beide Secrets-Paare sind hinterlegt.

```bash
git checkout main
git pull
git tag v1.6.0
git push origin v1.6.0
```

Expected: Beide Workflows laufen. Der Versions-Guard besteht. Das Release `v1.6.0` enthält am Ende fünf Assets: `Blitztext-macos-universal.zip`, `Blitztext-macos-universal.zip.sig`, das NSIS-Setup, die MSI und `latest.json`.

- [ ] **Step 2: Ausgangsversion auf dem Mac installieren**

Die Version 1.5 aus einem früheren Release nach `/Applications` legen und starten. Prüfen, dass der Menüleisten-Footer `v1.5` zeigt.

- [ ] **Step 3: Update auf dem Mac durchführen**

In den Einstellungen unter Zugang auf "Nach Updates suchen" klicken.

Expected: "Version 1.6.0 ist verfuegbar." Nach Klick auf den Installieren-Knopf läuft der Fortschritt, die App beendet sich und startet neu.

- [ ] **Step 4: Mac-Ergebnis prüfen**

Nach dem Neustart prüfen:

- Der Footer zeigt `v1.6.0`
- Die Hotkeys funktionieren weiterhin, ohne die Bedienungshilfen-Berechtigung neu zu erteilen
- Der Schalter "Beim Anmelden" steht noch so, wie er vorher stand
- Ein Diktat läuft durch, der API-Schlüssel liegt weiterhin im Schlüsselbund
- `~/Library/Application Support/Blitztext/updates` ist nach dem Neustart leer oder nicht vorhanden

- [ ] **Step 5: Manipuliertes Update ablehnen lassen**

Diesen Fall einmal aktiv herbeiführen, weil er der wichtigste ist. Ein Testrelease anlegen, in dem die `.sig`-Datei zu einem anderen Archiv gehört, und die App darauf zeigen lassen.

Expected: Die App bricht ab, zeigt "Die Signatur des Downloads passt nicht", löscht die geladene Datei und die installierte Version bleibt unverändert.

- [ ] **Step 6: Windows-Durchlauf auf echter Hardware**

Nicht auf dem Mac-Entwicklungsrechner. Auf einem Windows-Rechner die vorherige Version über das NSIS-Setup installieren, starten, dann in den Einstellungen unter Zugang auf "Nach Updates suchen" klicken.

Expected: Das Update wird gefunden, der passive Installer läuft durch, die App startet neu.

- [ ] **Step 7: Windows-Ergebnis prüfen**

Nach dem Neustart prüfen:

- Die App meldet die neue Version im Update-Abschnitt
- Die Hotkeys sind weiterhin registriert
- Der Autostart-Schalter steht noch so, wie er vorher stand
- Der im Credential Manager abgelegte API-Schlüssel ist noch da, ein Diktat läuft durch

- [ ] **Step 8: Ergebnis festhalten**

Die Abweichungen aus dem Durchlauf als eigene Commits beheben. Wenn nichts abweicht, in `BlitztextWin/HANDOFF.md` unter "Plan, remaining steps" den Schritt 9 als erledigt markieren und dort ergänzen, dass der Auto-Updater auf echter Hardware verifiziert wurde.
