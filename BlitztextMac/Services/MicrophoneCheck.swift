import AppKit
import CoreAudio

/// What the microphone a dictation records from looks like (the chosen one, otherwise the
/// macOS default; `MicrophoneSelection.dictationInput`): whether there is one, and how loud
/// macOS records it. The input volume belongs to the user: Blitztext changes it only when they click
/// "Lauter stellen", never on its own (call apps adjust it too, and a call running at the same
/// time would suddenly hear the user louder).
enum MicrophoneCheck {
    enum Issue: Equatable {
        /// No input at all, e.g. a closed MacBook with an external keyboard and no headset.
        case noInput
        /// macOS records very quietly; consonants get lost and words go missing.
        case quiet(percent: Int)
    }

    /// On a MacBook Pro 50 % is 0 dB; 27 % (-5.5 dB) kept quiet speech below the speech check.
    static let quietBelow: Float = 0.4

    /// What "Lauter stellen" sets: +4.8 dB on a MacBook Pro.
    static let raisedVolume: Float = 0.7

    static var issue: Issue? {
        guard let device = MicrophoneSelection.dictationInput else { return .noInput }
        if let volume = inputVolume(of: device), volume < quietBelow {
            return .quiet(percent: Int((volume * 100).rounded()))
        }
        return nil
    }

    /// Raises a quiet dictation microphone to `raisedVolume`. False when the device has no
    /// volume Blitztext may set; then only the System Settings help.
    @discardableResult
    static func raiseInputVolume() -> Bool {
        guard let device = MicrophoneSelection.dictationInput, let volume = inputVolume(of: device), volume < raisedVolume else { return false }
        // The main volume covers every channel; devices without one have a volume per channel.
        if setInputVolume(raisedVolume, of: device, element: kAudioObjectPropertyElementMain) { return true }
        let channels = [1, 2].map { setInputVolume(raisedVolume, of: device, element: AudioObjectPropertyElement($0)) }
        return channels.contains(true)
    }

    private static func setInputVolume(_ volume: Float, of device: AudioObjectID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The input volume 0...1, from the main element or, on devices without one, channel 1.
    private static func inputVolume(of device: AudioObjectID) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = volumeAddress(element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }

    private static func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }
}
