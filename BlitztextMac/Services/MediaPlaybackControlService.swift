import Cocoa

/// Simuliert die System-Medientaste (Play/Pause), damit macOS die aktuell
/// aktive "Jetzt läuft"-App (Spotify, Browser, Musik ...) pausiert bzw. fortsetzt.
enum MediaPlaybackControlService {
    private static let nxKeyTypePlay: Int32 = 16

    static func togglePlayPause() {
        postMediaKeyEvent(down: true)
        postMediaKeyEvent(down: false)
    }

    private static func postMediaKeyEvent(down: Bool) {
        let flags: Int = down ? 0xa00 : 0xb00
        let data1 = (Int(nxKeyTypePlay) << 16) | flags

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
