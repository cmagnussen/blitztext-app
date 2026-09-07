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
