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
