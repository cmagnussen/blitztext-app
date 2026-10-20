import AVFoundation

/// A little silence before and after a dictation. Speech models tend to drop a word that
/// starts right at the first sample, and Bluetooth microphones begin with a moment of
/// digital silence that cuts into the first word; padding keeps the first and last word.
enum AudioPadding {
    static let seconds = 0.3
    /// Longer recordings, e.g. audio files and meetings, start with room anyway.
    static let maximumDuration: TimeInterval = 600

    /// A padded copy as WAV next to the temporary files, or nil when the file cannot be
    /// read or is long enough not to need it. The caller removes the copy.
    static func paddedCopy(of url: URL, seconds: Double = seconds) -> URL? {
        guard let input = try? AVAudioFile(forReading: url) else { return nil }
        let format = input.processingFormat
        guard format.sampleRate > 0, Double(input.length) / format.sampleRate <= maximumDuration else { return nil }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-padded-\(UUID().uuidString).wav")
        do {
            let file = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            let silenceFrames = AVAudioFrameCount(seconds * format.sampleRate)
            if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: silenceFrames) {
                silence.frameLength = silenceFrames
                // A new buffer is zero-filled; write it before and after the speech.
                try file.write(from: silence)
                let chunk: AVAudioFrameCount = 65_536
                while input.framePosition < input.length, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) {
                    try input.read(into: buffer, frameCount: chunk)
                    guard buffer.frameLength > 0 else { break }
                    try file.write(from: buffer)
                }
                try file.write(from: silence)
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
    }
}
