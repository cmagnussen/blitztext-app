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
