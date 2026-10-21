import AVFoundation
import Observation

@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?

    /// One file per recording: deleting one after its transcription never hits the next.
    private var fileURL = AudioRecorder.newFileURL()

    private static func newFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
    }

    /// Deletes this recorder's audio, for recordings that are not transcribed.
    func discardRecording() {
        try? FileManager.default.removeItem(at: fileURL)
        recordingURL = nil
    }

    /// Recordings a crash or quit left behind, with their padded copies (`AudioPadding`), the
    /// stretches of live notes and the converted and streamed copies of meeting and audio file
    /// sound; nothing records or transcribes while the app starts.
    static func removeLeftoverRecordings() {
        let temp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let name = file.lastPathComponent
            let leftover = (name.hasPrefix("recording") && file.pathExtension == "m4a")
                || (["blitztext-padded-", "blitztext-live-", "blitztext-import-"].contains { name.hasPrefix($0) } && file.pathExtension == "wav")
                || (name.hasPrefix("fluidaudio-streaming-") && file.pathExtension == "raw")
            if leftover { try? FileManager.default.removeItem(at: file) }
        }
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        fileURL = Self.newFileURL()

        // Without access macOS records silence; say why instead of "Keine Aufnahme erkannt".
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            errorMessage = MicrophonePermission.deniedMessage
            return
        default:
            break
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                audioRecorder = nil
                errorMessage = "Die Aufnahme lie\u{00DF} sich nicht starten. Darf Blitztext das Mikrofon nutzen?"
                return
            }
            isRecording = true
            recordingURL = nil
            startMetering()
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        stopMetering()
        lastRecordingDuration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        isRecording = false
        recordingURL = fileURL
        audioLevel = 0
    }

    private func startMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.audioRecorder?.updateMeters()
            let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            let normalized = max(0, min(1, (power + 50) / 50))
            self.audioLevel = normalized
        }
    }

    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.errorMessage = "Aufnahme fehlgeschlagen"
            }
        }
    }
}
