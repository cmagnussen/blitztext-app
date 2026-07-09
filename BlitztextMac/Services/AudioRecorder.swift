import AVFoundation
import Observation

@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0

    private let pauseMediaDuringRecording: Bool
    private var pausedPlayback: MediaPlaybackControlService.PausedPlayback?
    private var pauseGeneration = 0

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var currentFileURL: URL?

    init(pauseMediaDuringRecording: Bool = false) {
        self.pauseMediaDuringRecording = pauseMediaDuringRecording
        super.init()
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-\(UUID().uuidString).m4a")
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        pausedPlayback = nil
        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let fileURL = makeRecordingURL()
            currentFileURL = fileURL
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            startMetering()

            if pauseMediaDuringRecording {
                pauseGeneration += 1
                let generation = pauseGeneration
                MediaPlaybackControlService.pausePlayback { [weak self] paused in
                    guard !paused.isEmpty else { return }
                    guard let self, generation == self.pauseGeneration, self.isRecording else {
                        // Aufnahme ist schon vorbei — sofort wieder fortsetzen.
                        MediaPlaybackControlService.resume(paused)
                        return
                    }
                    self.pausedPlayback = paused
                }
            }
        } catch {
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        stopMetering()
        lastRecordingDuration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        isRecording = false
        recordingURL = currentFileURL
        currentFileURL = nil
        audioRecorder = nil
        audioLevel = 0
        pauseGeneration += 1

        if let pausedPlayback {
            MediaPlaybackControlService.resume(pausedPlayback)
            self.pausedPlayback = nil
        }
    }

    func discardRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }

        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
            self.currentFileURL = nil
        }
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
