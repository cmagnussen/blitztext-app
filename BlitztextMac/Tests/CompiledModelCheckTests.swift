import XCTest

final class CompiledModelCheckTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func model(_ name: String, parts: [String] = ["coremldata.bin", "model.mil", "weights/weight.bin"]) throws {
        for part in parts {
            let file = directory.appendingPathComponent("\(name).mlmodelc").appendingPathComponent(part)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: file)
        }
    }

    func testCompleteModelsPass() throws {
        try model("Encoder")
        try model("Decoder")
        XCTAssertTrue(CompiledModelCheck.isComplete(directory))
    }

    func testMissingWeightsFail() throws {
        try model("Encoder")
        // Interrupted before the weights arrived.
        try model("Decoder", parts: ["coremldata.bin", "model.mil"])
        XCTAssertFalse(CompiledModelCheck.isComplete(directory))
    }

    func testHalfDownloadedFileFails() throws {
        try model("Encoder")
        try Data("x".utf8).write(to: directory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin.partial"))
        XCTAssertFalse(CompiledModelCheck.isComplete(directory))
    }

    func testEmptyOrMissingFolderFails() {
        XCTAssertFalse(CompiledModelCheck.isComplete(directory))
        XCTAssertFalse(CompiledModelCheck.isComplete(directory.appendingPathComponent("missing")))
    }
}
