import AVFoundation
import XCTest

final class RecordingFileTests: XCTestCase {
    private func wav(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 16_000)
        if frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) {
            buffer.frameLength = frames
            try file.write(from: buffer)
        }
        return url
    }

    func testCompleteFileGoesOnAtOnce() async throws {
        let url = try wav(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let started = Date()
        try await RecordingFile.waitUntilComplete(url, expected: 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    }

    func testEmptyFileOfALongRecordingIsReported() async throws {
        let url = try wav(seconds: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await RecordingFile.waitUntilComplete(url, expected: 3, timeout: .milliseconds(200))
            XCTFail("An empty file of a 3 s recording must not reach the model")
        } catch RecordingFile.Failure.empty(let read, let expected) {
            XCTAssertEqual(read, 0, accuracy: 0.01)
            XCTAssertEqual(expected, 3)
        }
    }

    func testUnreadableFileOfALongRecordingIsReported() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        defer { try? FileManager.default.removeItem(at: url) }
        await XCTAssertThrowsErrorAsync(try await RecordingFile.waitUntilComplete(url, expected: 2, timeout: .milliseconds(150)))
    }

    /// Slightly shorter than the recorder's clock is normal; it goes on with that.
    func testFileSlightlyShorterThanTheRecordingGoesOn() async throws {
        let url = try wav(seconds: 1.8)
        defer { try? FileManager.default.removeItem(at: url) }
        try await RecordingFile.waitUntilComplete(url, expected: 2, timeout: .milliseconds(150))
    }
}

private func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
