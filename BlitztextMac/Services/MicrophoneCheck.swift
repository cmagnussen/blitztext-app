import AppKit
import CoreAudio

/// What the default microphone looks like: whether there is one, and how loud macOS records
/// it. Only read, never changed: the input volume belongs to the user.
enum MicrophoneCheck {
    enum Issue: Equatable {
        /// No input at all, e.g. a closed MacBook with an external keyboard and no headset.
        case noInput
        /// macOS records very quietly; consonants get lost and words go missing.
        case quiet(percent: Int)
    }

    static let quietBelow: Float = 0.25

    static var issue: Issue? {
        guard let device = defaultInput else { return .noInput }
        if let volume = inputVolume(of: device), volume < quietBelow {
            return .quiet(percent: Int((volume * 100).rounded()))
        }
        return nil
    }

    static func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static var defaultInput: AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// The input volume 0...1, from the main element or, on devices without one, channel 1.
    private static func inputVolume(of device: AudioObjectID) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }
}
