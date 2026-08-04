import AudioToolbox
import Foundation
import Observation
import OSLog

private let audioRecorderLogger = Logger(subsystem: "app.blitztext.mac", category: "AudioRecorder")

@Observable
@MainActor
final class AudioRecorder {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0

    private let inputDeviceUID: String?
    private var audioQueue: AudioQueueRef?
    private var recordingState: AudioQueueRecordingState?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?

    init(inputDeviceUID: String? = nil) {
        let normalizedUID = inputDeviceUID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inputDeviceUID = normalizedUID?.isEmpty == false ? normalizedUID : nil
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-\(UUID().uuidString).wav")
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        removeCurrentTemporaryFile()

        let fileURL = makeRecordingURL()
        currentFileURL = fileURL

        var format = Self.recordingFormat
        var newQueue: AudioQueueRef?
        var newAudioFile: AudioFileID?

        do {
            try check(
                AudioQueueNewInputWithDispatchQueue(
                    &newQueue,
                    &format,
                    0,
                    Self.callbackQueue
                ) { queue, buffer, _, packetCount, packetDescriptions in
                    guard let state = AudioQueueRecordingStateRegistry.state(for: queue) else {
                        return
                    }
                    state.process(
                        queue: queue,
                        buffer: buffer,
                        packetCount: packetCount,
                        packetDescriptions: packetDescriptions
                    )
                },
                operation: "Aufnahmegerät konnte nicht vorbereitet werden"
            )
            guard let newQueue else {
                throw AudioRecorderError.inputUnavailable
            }

            try configureInputDevice(on: newQueue)
            try check(
                AudioFileCreateWithURL(
                    fileURL as CFURL,
                    kAudioFileWAVEType,
                    &format,
                    .eraseFile,
                    &newAudioFile
                ),
                operation: "Aufnahmedatei konnte nicht erstellt werden"
            )
            guard let newAudioFile else {
                throw AudioRecorderError.fileUnavailable
            }

            let state = AudioQueueRecordingState(
                audioFile: newAudioFile,
                bytesPerPacket: format.mBytesPerPacket,
                levelHandler: { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.audioLevel = level
                    }
                },
                errorHandler: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.errorMessage = message
                    }
                }
            )
            AudioQueueRecordingStateRegistry.register(state, for: newQueue)

            do {
                try prepareBuffers(for: newQueue)
                try check(
                    AudioQueueStart(newQueue, nil),
                    operation: "Aufnahme konnte nicht gestartet werden"
                )
            } catch {
                AudioQueueRecordingStateRegistry.removeState(for: newQueue)
                state.deactivate()
                throw error
            }

            audioQueue = newQueue
            recordingState = state
            recordingStartedAt = Date()
            isRecording = true
            audioRecorderLogger.info("Audio input queue started")
        } catch {
            if let newQueue, AudioQueueRecordingStateRegistry.state(for: newQueue) == nil {
                AudioQueueDispose(newQueue, true)
            }
            if let newAudioFile {
                AudioFileClose(newAudioFile)
            }
            removeCurrentTemporaryFile()
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
            audioRecorderLogger.error("Audio input queue failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopRecording() {
        guard let audioQueue else {
            isRecording = false
            return
        }

        recordingState?.deactivate()
        AudioQueueStop(audioQueue, true)
        AudioQueueRecordingStateRegistry.removeState(for: audioQueue)
        AudioQueueDispose(audioQueue, true)
        recordingState?.closeFile()

        lastRecordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        isRecording = false
        recordingURL = currentFileURL
        currentFileURL = nil
        recordingStartedAt = nil
        recordingState = nil
        self.audioQueue = nil
        audioLevel = 0
        audioRecorderLogger.info("Audio input queue stopped")
    }

    func discardRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }
        removeCurrentTemporaryFile()
    }

    private func configureInputDevice(on queue: AudioQueueRef) throws {
        guard let inputDeviceUID else { return }
        guard AudioInputDeviceService.deviceID(forUID: inputDeviceUID) != nil else {
            // The selected microphone was disconnected. The queue then uses the
            // current macOS default input without changing the system setting.
            return
        }

        let deviceUID = inputDeviceUID as CFString
        var unmanagedDeviceUID: Unmanaged<CFString>? = .passUnretained(deviceUID)
        let status = withExtendedLifetime(deviceUID) {
            AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                &unmanagedDeviceUID,
                UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            )
        }
        try check(
            status,
            operation: "Das ausgewählte Mikrofon konnte nicht aktiviert werden"
        )
    }

    private func prepareBuffers(for queue: AudioQueueRef) throws {
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            try check(
                AudioQueueAllocateBuffer(queue, Self.bufferByteSize, &buffer),
                operation: "Aufnahmepuffer konnte nicht erstellt werden"
            )
            guard let buffer else {
                throw AudioRecorderError.bufferUnavailable
            }
            try check(
                AudioQueueEnqueueBuffer(queue, buffer, 0, nil),
                operation: "Aufnahmepuffer konnte nicht aktiviert werden"
            )
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioRecorderError.coreAudio(operation: operation, status: status)
        }
    }

    private func removeCurrentTemporaryFile() {
        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
            self.currentFileURL = nil
        }
    }

    private static let callbackQueue = DispatchQueue(
        label: "app.blitztext.audio-input",
        qos: .userInitiated
    )
    private static let bufferByteSize: UInt32 = 6_400
    private static let recordingFormat = AudioStreamBasicDescription(
        mSampleRate: 16_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )
}

private final class AudioQueueRecordingState: @unchecked Sendable {
    private let lock = NSLock()
    private var audioFile: AudioFileID?
    private var packetIndex: Int64 = 0
    private var isActive = true
    private let bytesPerPacket: UInt32
    private let levelHandler: @Sendable (Float) -> Void
    private let errorHandler: @Sendable (String) -> Void

    init(
        audioFile: AudioFileID,
        bytesPerPacket: UInt32,
        levelHandler: @escaping @Sendable (Float) -> Void,
        errorHandler: @escaping @Sendable (String) -> Void
    ) {
        self.audioFile = audioFile
        self.bytesPerPacket = bytesPerPacket
        self.levelHandler = levelHandler
        self.errorHandler = errorHandler
    }

    func process(
        queue: AudioQueueRef,
        buffer: AudioQueueBufferRef,
        packetCount: UInt32,
        packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) {
        lock.lock()
        guard isActive, let audioFile else {
            lock.unlock()
            return
        }

        let byteCount = buffer.pointee.mAudioDataByteSize
        var packetsToWrite = packetCount
        if packetsToWrite == 0, bytesPerPacket > 0 {
            packetsToWrite = byteCount / bytesPerPacket
        }
        let startPacket = packetIndex

        let writeStatus: OSStatus
        if byteCount > 0, packetsToWrite > 0 {
            writeStatus = AudioFileWritePackets(
                audioFile,
                false,
                byteCount,
                packetDescriptions,
                startPacket,
                &packetsToWrite,
                buffer.pointee.mAudioData
            )
            if writeStatus == noErr {
                packetIndex += Int64(packetsToWrite)
            }
        } else {
            writeStatus = noErr
        }
        let shouldReenqueue = isActive
        lock.unlock()

        if writeStatus != noErr {
            errorHandler("Aufnahme konnte nicht gespeichert werden (Core Audio \(writeStatus)).")
        }
        if byteCount > 0 {
            levelHandler(Self.normalizedLevel(from: buffer))
        }
        if shouldReenqueue {
            let enqueueStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            if enqueueStatus != noErr {
                errorHandler("Aufnahme wurde unerwartet unterbrochen (Core Audio \(enqueueStatus)).")
            }
        }
    }

    func deactivate() {
        lock.lock()
        isActive = false
        lock.unlock()
    }

    func closeFile() {
        lock.lock()
        let file = audioFile
        audioFile = nil
        lock.unlock()
        if let file {
            AudioFileClose(file)
        }
    }

    private static func normalizedLevel(from buffer: AudioQueueBufferRef) -> Float {
        let sampleCount = Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
        var sumOfSquares: Double = 0
        for index in 0..<sampleCount {
            let sample = Double(samples[index]) / Double(Int16.max)
            sumOfSquares += sample * sample
        }

        let rootMeanSquare = sqrt(sumOfSquares / Double(sampleCount))
        guard rootMeanSquare > 0 else { return 0 }
        let decibels = 20 * log10(rootMeanSquare)
        return Float(max(0, min(1, (decibels + 50) / 50)))
    }
}

private enum AudioQueueRecordingStateRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [AudioQueueRef: AudioQueueRecordingState] = [:]

    static func register(_ state: AudioQueueRecordingState, for queue: AudioQueueRef) {
        lock.lock()
        states[queue] = state
        lock.unlock()
    }

    static func state(for queue: AudioQueueRef) -> AudioQueueRecordingState? {
        lock.lock()
        let state = states[queue]
        lock.unlock()
        return state
    }

    static func removeState(for queue: AudioQueueRef) {
        lock.lock()
        states.removeValue(forKey: queue)
        lock.unlock()
    }
}

private enum AudioRecorderError: LocalizedError {
    case inputUnavailable
    case fileUnavailable
    case bufferUnavailable
    case coreAudio(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "Das ausgewählte Mikrofon ist nicht verfügbar."
        case .fileUnavailable:
            return "Die Aufnahmedatei konnte nicht geöffnet werden."
        case .bufferUnavailable:
            return "Der Aufnahmepuffer konnte nicht erstellt werden."
        case .coreAudio(let operation, let status):
            return "\(operation) (Core Audio \(status))."
        }
    }
}
