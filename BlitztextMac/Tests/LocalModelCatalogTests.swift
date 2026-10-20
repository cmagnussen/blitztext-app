import XCTest

final class LocalModelCatalogTests: XCTestCase {
    func testOffersWhatTheMemoryAllows() {
        XCTAssertEqual(LocalModelVariant.recommended(memoryGB: 8, appleSilicon: true), nil)
        XCTAssertEqual(LocalModelVariant.recommended(memoryGB: 16, appleSilicon: true), .gemma4E4B)
        XCTAssertEqual(LocalModelVariant.recommended(memoryGB: 24, appleSilicon: true), .gemma4_12B)
        XCTAssertEqual(LocalModelVariant.recommended(memoryGB: 64, appleSilicon: true), .gemma4_12B)
    }

    func testIntelMacsGetNoModel() {
        XCTAssertEqual(LocalModelVariant.recommended(memoryGB: 64, appleSilicon: false), nil)
        XCTAssertEqual(LocalModelVariant.gemma4E4B.support(memoryGB: 64, appleSilicon: false), .unavailable("Braucht einen Mac mit Apple-Chip."))
    }

    func testSaysWhyAModelDoesNotFit() {
        XCTAssertEqual(
            LocalModelVariant.gemma4_12B.support(memoryGB: 16, appleSilicon: true),
            .unavailable("Braucht mindestens 24 GB Arbeitsspeicher, dieser Mac hat 16 GB.")
        )
    }

    func testFilesArePinned() {
        for variant in LocalModelVariant.all {
            XCTAssertEqual(variant.revision.count, 40, variant.name)
            XCTAssertTrue(variant.files.allSatisfy { $0.sha256.count == 64 && $0.size > 0 }, variant.name)
            XCTAssertTrue(variant.files.contains { $0.name.hasSuffix(".safetensors") }, variant.name)
            XCTAssertTrue(variant.url(for: variant.files[0]).absoluteString.contains("/resolve/\(variant.revision)/"))
        }
        XCTAssertEqual(LocalModelVariant.gemma4E4B.downloadSize, 5_179_239_349)
    }
}
