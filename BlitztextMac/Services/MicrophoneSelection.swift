import CoreAudio
import Foundation

/// The microphone Blitztext dictates with. AVAudioRecorder always uses the macOS default input,
/// so a chosen microphone becomes the default input while a dictation records, and the previous
/// default comes back afterwards. Meetings keep the macOS default. Empty choice: whatever macOS uses.
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

    /// What a recording changed, kept in the defaults until it is undone, so a crash in the
    /// middle of a recording is repaired at the next launch.
    struct Switch: Codable, Equatable {
        /// The input before the recording.
        let previousUID: String
        /// The chosen microphone that became the input.
        let chosenUID: String
    }

    static let switchKey = "BlitztextMicrophoneSwitch"

    static var pendingSwitch: Switch? {
        get { UserDefaults.standard.data(forKey: switchKey).flatMap { try? JSONDecoder().decode(Switch.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: switchKey) }
    }

    /// True while a Blitztext meeting records (`MeetingController.recordingID`). The meeting
    /// records from the macOS default input, so a dictation then leaves it alone.
    static var meetingIsRecording = false

    /// Makes the chosen microphone the default input for a dictation. Meetings never call it:
    /// a call running at the same time keeps its microphone, and while a meeting records a
    /// dictation does not switch either. True when it changed something.
    @discardableResult
    static func applyForRecording() -> Bool {
        let uid = preferredUID
        guard shouldSwitch(preferredUID: uid, meetingIsRecording: meetingIsRecording), pendingSwitch == nil,
              let wanted = device(uid: uid), hasInput(wanted),
              let current = defaultInput, current != wanted,
              let currentUID = string(current, kAudioDevicePropertyDeviceUID) else { return false }
        // Noted before the switch, so a crash right after it is covered too.
        pendingSwitch = Switch(previousUID: currentUID, chosenUID: uid)
        guard setDefaultInput(wanted) else {
            pendingSwitch = nil
            return false
        }
        return true
    }

    /// Only with a chosen microphone, and never while a meeting records.
    static func shouldSwitch(preferredUID: String, meetingIsRecording: Bool) -> Bool {
        !preferredUID.isEmpty && !meetingIsRecording
    }

    /// Puts the previous input back after a recording, and at launch after a crash.
    static func restore() {
        guard let change = pendingSwitch else { return }
        pendingSwitch = nil
        let currentUID = defaultInput.flatMap { string($0, kAudioDevicePropertyDeviceUID) }
        guard shouldRestore(currentUID: currentUID, after: change),
              let previous = device(uid: change.previousUID) else { return }
        _ = setDefaultInput(previous)
    }

    /// Only while the chosen microphone is still the input: a change made meanwhile (in the
    /// System Settings, or macOS after the device was unplugged) wins.
    static func shouldRestore(currentUID: String?, after change: Switch) -> Bool {
        currentUID == change.chosenUID
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

    private static func device(uid: String) -> AudioObjectID? {
        allDeviceIDs().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
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
