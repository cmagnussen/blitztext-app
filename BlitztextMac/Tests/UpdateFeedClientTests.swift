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
        let daten = liste(release(tag: "v1.7.0", prerelease: true), release(tag: "v1.5.0"))
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
