import Cocoa
import CoreAudio

/// Pausiert Medienwiedergabe beim Aufnahmestart und setzt sie danach fort —
/// ohne jemals versehentlich eine pausierte Wiedergabe zu starten.
///
/// Zwei Wege, weil die System-Medientaste nur ein zustandsloses Toggle ist:
/// - Skriptfähige Player (Spotify, Apple Music) werden per AppleScript
///   explizit abgefragt (`player state`) und mit `pause`/`play` gesteuert.
///   Das kann nie ungewollt starten, weil nur bei "playing" pausiert wird.
/// - Browser (YouTube & Co.) bieten keine Skript-Schnittstelle für den
///   Player-Zustand. Für sie wird die Medientaste nur gedrückt, wenn
///   CoreAudio meldet, dass ein Browser-Prozess gerade aktiv Audio ausgibt
///   (prozessgenau — pausierte Apps wie Spotify, die ihren Audio-Stream
///   offen halten, können das Toggle so nicht mehr fälschlich auslösen).
enum MediaPlaybackControlService {
    private static let nxKeyTypePlay: Int32 = 16
    private static let workQueue = DispatchQueue(label: "app.blitztext.media-playback-control", qos: .userInitiated)

    // MARK: - Public API

    enum ScriptablePlayer: String, CaseIterable {
        case spotify = "com.spotify.client"
        case appleMusic = "com.apple.Music"

        var scriptTargetName: String {
            switch self {
            case .spotify: return "Spotify"
            case .appleMusic: return "Music"
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
        }
    }

    /// Beschreibt, was tatsächlich pausiert wurde — nur das wird beim
    /// Fortsetzen wieder gestartet.
    struct PausedPlayback {
        let pausedPlayers: [ScriptablePlayer]
        let sentBrowserToggle: Bool

        var isEmpty: Bool { pausedPlayers.isEmpty && !sentBrowserToggle }
    }

    /// Pausiert laufende Wiedergabe (asynchron, da AppleScript-Abfragen
    /// dauern können) und meldet über `completion` auf dem Main-Thread,
    /// was pausiert wurde. Läuft nichts, wird nichts angefasst.
    static func pausePlayback(completion: @escaping (PausedPlayback) -> Void) {
        workQueue.async {
            var pausedPlayers: [ScriptablePlayer] = []

            for player in ScriptablePlayer.allCases where player.isRunning {
                let state = runAppleScript("tell application \"\(player.scriptTargetName)\" to player state as string")
                if state == "playing" {
                    _ = runAppleScript("tell application \"\(player.scriptTargetName)\" to pause")
                    pausedPlayers.append(player)
                }
            }

            let sentBrowserToggle = isBrowserAudioPlaying()
            if sentBrowserToggle {
                togglePlayPause()
            }

            let result = PausedPlayback(pausedPlayers: pausedPlayers, sentBrowserToggle: sentBrowserToggle)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Setzt eine zuvor über `pausePlayback` pausierte Wiedergabe fort.
    static func resume(_ paused: PausedPlayback) {
        guard !paused.isEmpty else { return }

        workQueue.async {
            for player in paused.pausedPlayers where player.isRunning {
                _ = runAppleScript("tell application \"\(player.scriptTargetName)\" to play")
            }

            if paused.sentBrowserToggle {
                togglePlayPause()
            }
        }
    }

    // MARK: - AppleScript (Spotify / Apple Music)

    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Browser-Audio-Erkennung (CoreAudio, prozessgenau)

    /// Browser-Prozesse, für die das Medientasten-Toggle sicher ist, wenn sie
    /// gerade aktiv Audio ausgeben. Präfix-Vergleich, weil Browser ihr Audio
    /// in Helper-Prozessen ausgeben (z. B. `com.apple.WebKit.GPU` für Safari,
    /// `com.google.Chrome.helper` für Chrome).
    private static let browserBundleIDPrefixes = [
        "com.apple.Safari",
        "com.apple.WebKit",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware",
    ]

    private static func isBrowserAudioPlaying() -> Bool {
        for processObjectID in audioProcessObjectIDs() {
            guard processIsRunningOutput(processObjectID),
                  let bundleID = processBundleID(processObjectID),
                  browserBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
            else { continue }
            return true
        }
        return false
    }

    private static func audioProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        var objectIDs = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        )
        guard status == noErr else { return [] }

        return objectIDs
    }

    private static func processIsRunningOutput(_ processObjectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processObjectID, &address, 0, nil, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }

    private static func processBundleID(_ processObjectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bundleID: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(processObjectID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }

        let result = bundleID as String
        return result.isEmpty ? nil : result
    }

    // MARK: - System-Medientaste (Play/Pause-Toggle)

    private static func togglePlayPause() {
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
