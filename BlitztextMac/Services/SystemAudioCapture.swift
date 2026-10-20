import AVFoundation
import CoreAudio

/// Records what the Mac plays, e.g. the other side of an online call, through a Core
/// Audio tap. macOS asks for "System Audio Recording" the first time; without that
/// permission the tap delivers silence instead of an error, so `peak` tells whether
/// anything arrived.
///
/// The tap runs inside an aggregate device clocked by an output device. When that device
/// goes away mid-call (headphones unplugged, Bluetooth gone), sound stops arriving; a
/// watchdog then moves the tap to the current output and fills the gap with silence, so the
/// file stays in step with the microphone.
///
/// Start, stop and the watchdog run on the main thread: creating the aggregate device waits
/// for a Core Audio notification on the main run loop, so the main thread must not wait for
/// another queue meanwhile.
@available(macOS 14.2, *)
final class SystemAudioCapture {
    struct Failure: LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { "Systemton: \(step) fehlgeschlagen (\(status))." }
    }

    /// No sound for this long means the clocking device stopped.
    static let silenceBeforeRestart: TimeInterval = 2

    /// Loudest sample so far, 0...1.
    private(set) var peak: Float = 0
    private(set) var format: AVAudioFormat?
    /// Also receives the sound for live notes. Set before `start`.
    var liveBuffer: LiveAudioBuffer?
    /// The output device went away and the capture moved to the current one: nil when that
    /// worked, otherwise why not (it keeps trying). Called on the main thread.
    var onOutputChange: ((Error?) -> Void)?

    // Touched only on the main thread.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var watchdog: DispatchSourceTimer?
    private var restartFailed = false

    // Touched only on `queue`, where Core Audio delivers the sound.
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var isPaused = false
    private var lastDelivery = Date()
    private var startedAt = Date()
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0
    private var framesWritten: AVAudioFramePosition = 0
    private var fillsGap = false
    private let queue = DispatchQueue(label: "app.blitztext.system-audio")

    /// Taps everything the Mac plays except Blitztext itself, or only `processes`.
    /// `outputUID` is the device that clocks the tap; by default the current output.
    func start(writingTo url: URL, processes: [AudioObjectID] = [], outputUID: String? = nil) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        let description = processes.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: AudioProcesses.own.map { [$0] } ?? [])
            : CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Blitztext"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Tap anlegen")
        tapUUID = description.uuid

        let format = try tapFormat()
        self.format = format
        // The device is not running yet, so nothing else touches these now.
        file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        // The first time, macOS holds the start until the permission is answered; the gap
        // until the first sound becomes silence, so this track starts with the microphone.
        startedAt = Date()
        fillsGap = true
        try startDevice(outputUID: outputUID ?? CoreAudioProperty.defaultOutputUID())
        queue.sync { lastDelivery = Date() }

        let watchdog = DispatchSource.makeTimerSource(queue: .main)
        watchdog.schedule(deadline: .now() + 1, repeating: 1)
        watchdog.setEventHandler { [weak self] in self?.checkDelivery() }
        watchdog.resume()
        self.watchdog = watchdog
    }

    /// While paused nothing is written, so the file stays in step with a paused microphone.
    func setPaused(_ paused: Bool) {
        queue.async {
            guard paused != self.isPaused else { return }
            if paused {
                self.pausedSince = Date()
            } else if let pausedSince = self.pausedSince {
                self.pausedTotal += Date().timeIntervalSince(pausedSince)
                self.pausedSince = nil
            }
            self.isPaused = paused
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        watchdog?.cancel()
        watchdog = nil
        stopDevice()
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.sync { file = nil }
    }

    #if DEBUG
    /// Stops the device without telling anyone, as when headphones are unplugged.
    func simulateOutputLoss() {
        dispatchPrecondition(condition: .onQueue(.main))
        if aggregateID != kAudioObjectUnknown { AudioDeviceStop(aggregateID, procID) }
    }
    #endif

    // MARK: - Device, on the main thread

    /// The tap only delivers audio inside an aggregate device; the output device gives that
    /// device its clock.
    private func startDevice(outputUID: String) throws {
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Blitztext Systemton",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID.uuidString],
            ],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Ger\u{00E4}t anlegen")
        let format = try tapFormat()
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.deliver(input, format: format)
        }, "Aufnahme vorbereiten")
        try check(AudioDeviceStart(aggregateID, procID), "Aufnahme starten")
    }

    private func stopDevice() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
    }

    private func tapFormat() throws -> AVAudioFormat {
        var streamDescription = AudioStreamBasicDescription()
        try check(CoreAudioProperty.read(tapID, kAudioTapPropertyFormat, into: &streamDescription), "Format lesen")
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw Failure(step: "Format lesen", status: kAudioHardwareUnspecifiedError)
        }
        return format
    }

    /// Core Audio calls even when nothing plays, with silence; no call at all means the
    /// device stopped.
    private func checkDelivery() {
        let silentFor = queue.sync { Date().timeIntervalSince(lastDelivery) }
        guard silentFor > Self.silenceBeforeRestart, tapID != kAudioObjectUnknown else { return }
        stopDevice()
        queue.sync { fillsGap = true }
        do {
            try startDevice(outputUID: CoreAudioProperty.defaultOutputUID())
            restartFailed = false
            report(nil)
        } catch {
            stopDevice()
            // Once per loss; the next tries are quiet.
            if !restartFailed { report(error) }
            restartFailed = true
        }
        queue.sync { lastDelivery = Date() }
    }

    private func report(_ error: Error?) {
        onOutputChange?(error)
    }

    // MARK: - Sound, on `queue`

    private func deliver(_ input: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        lastDelivery = Date()
        guard !isPaused, let file,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
              buffer.frameLength > 0 else { return }
        if let samples = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength) * (format.isInterleaved ? Int(format.channelCount) : 1)
            for index in 0..<count { peak = max(peak, abs(samples[index])) }
        }
        guard let output = converted(buffer, to: file.processingFormat) else { return }
        if fillsGap {
            fillsGap = false
            writeSilence(before: output.frameLength, to: file)
        }
        write(output, to: file)
    }

    private func write(_ buffer: AVAudioPCMBuffer, to file: AVAudioFile) {
        guard (try? file.write(from: buffer)) != nil else { return }
        framesWritten += AVAudioFramePosition(buffer.frameLength)
        liveBuffer?.append(buffer)
    }

    /// Silence for the time without sound (waiting for the permission, or after the output
    /// changed), measured on the clock and without pauses, up to the buffer that arrives now.
    private func writeSilence(before frames: AVAudioFrameCount, to file: AVAudioFile) {
        let rate = file.processingFormat.sampleRate
        let recorded = Date().timeIntervalSince(startedAt) - pausedTotal
        var missing = AVAudioFramePosition(recorded * rate) - AVAudioFramePosition(frames) - framesWritten
        guard missing > AVAudioFramePosition(rate / 10),
              let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(rate)) else { return }
        silence.frameLength = silence.frameCapacity
        for channel in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
            if let data = channel.mData { memset(data, 0, Int(channel.mDataByteSize)) }
        }
        while missing > 0 {
            silence.frameLength = AVAudioFrameCount(min(AVAudioFramePosition(silence.frameCapacity), missing))
            write(silence, to: file)
            missing -= AVAudioFramePosition(silence.frameLength)
        }
    }

    /// The tap's format can change with the new output device; the file keeps the first one.
    private func converted(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != target else { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter,
              let output = AVAudioPCMBuffer(
                  pcmFormat: target,
                  frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
              ) else { return nil }
        var handedOver = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw Failure(step: step, status: status) }
    }
}

/// Apps that use audio right now, e.g. to notice that a call app has the microphone open.
@available(macOS 14.2, *)
enum AudioProcesses {
    struct Process {
        let id: AudioObjectID
        let bundleID: String
        let isRunningInput: Bool
        let isRunningOutput: Bool
    }

    static var own: AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var address = CoreAudioProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func all() -> [Process] {
        CoreAudioProperty.objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .map { id in
                Process(
                    id: id,
                    bundleID: CoreAudioProperty.string(id, kAudioProcessPropertyBundleID) ?? "?",
                    isRunningInput: CoreAudioProperty.flag(id, kAudioProcessPropertyIsRunningInput),
                    isRunningOutput: CoreAudioProperty.flag(id, kAudioProcessPropertyIsRunningOutput)
                )
            }
    }
}

/// Small readers for Core Audio object properties.
enum CoreAudioProperty {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func read<Value>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout Value) -> OSStatus {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Value>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    }

    static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var value: UInt32 = 0
        return read(object, selector, into: &value) == noErr && value != 0
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        guard read(object, selector, into: &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        let status = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device)
        guard status == noErr, let uid = string(device, kAudioDevicePropertyDeviceUID) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Kein Ausgabegerät gefunden.",
            ])
        }
        return uid
    }
}
