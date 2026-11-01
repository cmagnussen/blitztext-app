import CoreAudio
import Foundation

/// The microphone Blitztext records with. AVAudioRecorder always uses the macOS default input,
/// so a chosen microphone becomes the default input while Blitztext records, and the previous
/// default comes back afterwards. Empty choice: whatever macOS uses.
enum MicrophoneSelection {
    struct Device: Identifiable, Hashable {
        let id: String   // CoreAudio device UID, stable across reconnects
        let name: String
    }

    static let defaultsKey = "BlitztextPreferredMicrophoneUID"

    /// UID of the chosen microphone, "" for the macOS default.
    static var preferredUID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// All devices with at least one input channel, without Blitztext's own aggregate devices.
    static func inputDevices() -> [Device] {
        allDeviceIDs().compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            if uid.lowercased().contains("blitztext") { return nil }
            return Device(id: uid, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Makes the chosen microphone the default input. Returns the previous default when it
    /// changed something, for `restore`.
    @discardableResult
    static func applyForRecording() -> AudioObjectID? {
        let uid = preferredUID
        guard !uid.isEmpty,
              let wanted = allDeviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }),
              hasInput(wanted),
              let current = defaultInput,
              current != wanted else { return nil }
        return setDefaultInput(wanted) ? current : nil
    }

    /// Puts the previous default input back, if it is still connected.
    static func restore(_ previous: AudioObjectID?) {
        guard let previous, allDeviceIDs().contains(previous) else { return }
        _ = setDefaultInput(previous)
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static var defaultInput: AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func setDefaultInput(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var value = device
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &value)
        return status == noErr
    }
}
