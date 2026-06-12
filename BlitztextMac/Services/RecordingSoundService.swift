import AppKit

/// Spielt dezente akustische Signale beim Start und Ende einer Aufnahme,
/// analog zur Diktierfunktion von macOS.
enum RecordingSoundService {
    private static let volume: Float = 0.4

    static func playRecordingStarted() {
        play(named: "Tink")
    }

    static func playRecordingStopped() {
        play(named: "Pop")
    }

    private static func play(named name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }
}
