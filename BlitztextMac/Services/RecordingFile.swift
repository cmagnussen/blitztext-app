import AVFoundation
import OSLog

private let recordingLogger = Logger(subsystem: "app.blitztext.mac", category: "Recording")

/// The recorder may still be writing when `stop()` returns. Reading the file right away then
/// gives the models silence, and dictation ends in "Das lokale Modell hat keinen Text erkannt"
/// (public issue #40, macOS 27.2). This waits until the file holds the recorded audio.
enum RecordingFile {
    enum Failure: LocalizedError {
        /// Recorded for `expected` seconds, but the file held only `read` seconds.
        case empty(read: TimeInterval, expected: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .empty(let read, let expected):
                let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
                return "Die Aufnahme kam leer an (\(read.formatted(format)) von \(expected.formatted(format)) Sekunden). Bitte versuch es noch einmal und melde es über „Feedback senden“, wenn es bleibt."
            }
        }
    }

    /// Seconds of audio in the file, nil while it cannot be read.
    static func readableSeconds(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        return rate > 0 ? Double(file.length) / rate : nil
    }

    /// Waits up to `timeout` until the file holds about `expected` seconds. Goes on with what
    /// is there after that, and throws only when the file stays (almost) empty.
    static func waitUntilComplete(
        _ url: URL,
        expected: TimeInterval,
        timeout: Duration = .milliseconds(1_500)
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let enough = max(0, expected - 0.3)
        var read: TimeInterval = 0
        while true {
            read = readableSeconds(of: url) ?? 0
            if read >= enough { break }
            if clock.now - start >= timeout { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let waited = clock.now - start
        let milliseconds = Int(waited.components.seconds * 1_000) + Int(waited.components.attoseconds / 1_000_000_000_000_000)
        recordingLogger.info("Recording file: \(read, format: .fixed(precision: 2)) of \(expected, format: .fixed(precision: 2)) s readable after \(milliseconds) ms")
        if read < 0.1, expected >= 0.5 {
            recordingLogger.error("Recording file stayed empty: \(read, format: .fixed(precision: 2)) of \(expected, format: .fixed(precision: 2)) s")
            throw Failure.empty(read: read, expected: expected)
        }
    }
}
