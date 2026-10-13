import AVFoundation

/// Turns any audio file the system can read (m4a from Voice Memos, mp3, wav, Opus in
/// Ogg from WhatsApp and other messengers) into the 16 kHz mono WAV that Parakeet and
/// Whisper expect. Shared by the iOS and macOS apps.
enum AudioFileConverter {
    /// 16 kHz mono float, the input format of the local speech models.
    nonisolated static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    struct Result {
        let url: URL
        let duration: TimeInterval
    }

    enum ConversionError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Diese Audiodatei kann Blitztext nicht öffnen."
            case .empty: return "Die Audiodatei ist leer."
            }
        }
    }

    static func convertToWAV(_ sourceURL: URL) throws -> Result {
        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw ConversionError.unreadable
        }

        let target = targetFormat
        guard let converter = AVAudioConverter(from: input.processingFormat, to: target) else {
            throw ConversionError.unreadable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-import-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: target.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        var output: AVAudioFile? = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        defer { output = nil } // closing finalizes the WAV header

        let chunkFrames: AVAudioFrameCount = 16_384
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunkFrames) else {
            throw ConversionError.unreadable
        }
        let ratio = target.sampleRate / input.processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(chunkFrames) * ratio) + 1_024
        var framesWritten: AVAudioFramePosition = 0
        var reachedEnd = false

        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                if reachedEnd {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: readBuffer, frameCount: chunkFrames)
                } catch {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if readBuffer.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return readBuffer
            }
            if let conversionError {
                try? FileManager.default.removeItem(at: outputURL)
                throw conversionError
            }
            if outBuffer.frameLength > 0 {
                try output?.write(from: outBuffer)
                framesWritten += AVAudioFramePosition(outBuffer.frameLength)
            }
            if status == .endOfStream || status == .error {
                break
            }
        }

        guard framesWritten > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ConversionError.empty
        }
        return Result(url: outputURL, duration: Double(framesWritten) / target.sampleRate)
    }
}
