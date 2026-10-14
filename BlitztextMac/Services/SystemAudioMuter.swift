import AudioToolbox
import CoreAudio

/// Silences the Mac's sound output while Blitztext records, so a podcast or music does
/// not run on over the dictation, and restores it exactly as it was.
///
/// Pausing would be nicer but is not safe: since macOS 15.4 apps cannot see what is
/// playing, so "resume" afterwards could start something that was paused. Muting uses
/// the mute switch, or volume 0 when a device has none.
@MainActor
final class SystemAudioMuter {
    private enum Restore {
        case unmute(AudioDeviceID)
        case volume(AudioDeviceID, Float32)
    }

    private var restore: Restore?

    func mute() {
        guard restore == nil, let device = Self.defaultOutputDevice() else { return }
        // Already silent: nothing to do and nothing to restore later.
        if Self.isMuted(device) == true { return }
        if Self.setMuted(device, true) {
            restore = .unmute(device)
        } else if let volume = Self.volume(device), volume > 0, Self.setVolume(device, 0) {
            restore = .volume(device, volume)
        }
    }

    func restoreIfNeeded() {
        guard let restore else { return }
        self.restore = nil
        switch restore {
        case .unmute(let device):
            _ = Self.setMuted(device, false)
        case .volume(let device, let volume):
            _ = Self.setVolume(device, volume)
        }
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector, output: Bool = true) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: output ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, output: false)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    private static func setMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var address = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func volume(_ device: AudioDeviceID) -> Float32? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setVolume(_ device: AudioDeviceID, _ volume: Float32) -> Bool {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
