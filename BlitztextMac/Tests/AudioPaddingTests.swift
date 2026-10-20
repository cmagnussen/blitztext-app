import AVFoundation
import XCTest

final class AudioPaddingTests: XCTestCase {
    private func makeRecording(seconds: Double, rate: Double = 16_000) throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = 0.5 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("padding-test-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        return url
    }

    func testAddsSilenceOnBothEnds() throws {
        let original = try makeRecording(seconds: 2)
        defer { try? FileManager.default.removeItem(at: original) }
        let padded = try XCTUnwrap(AudioPadding.paddedCopy(of: original))
        defer { try? FileManager.default.removeItem(at: padded) }

        let file = try AVAudioFile(forReading: padded)
        XCTAssertEqual(file.length, Int64(16_000 * (2 + 2 * AudioPadding.seconds)))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        XCTAssertEqual(samples[0], 0)
        XCTAssertEqual(samples[4_799], 0)
        XCTAssertEqual(samples[4_800], 0.5, accuracy: 0.001)
        XCTAssertEqual(samples[Int(file.length) - 1], 0)
    }

    func testLeavesLongRecordingsAlone() throws {
        let original = try makeRecording(seconds: AudioPadding.maximumDuration + 1, rate: 8_000)
        defer { try? FileManager.default.removeItem(at: original) }
        XCTAssertNil(AudioPadding.paddedCopy(of: original))
    }

    func testUnreadableFileGivesNil() {
        XCTAssertNil(AudioPadding.paddedCopy(of: URL(fileURLWithPath: "/nonexistent/recording.m4a")))
    }
}
