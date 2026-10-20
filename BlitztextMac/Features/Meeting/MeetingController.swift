import AVFoundation
import Foundation
import Observation

/// Records a meeting through the Mac's microphone and turns it into a transcript by person,
/// optionally with a summary and to-dos. For an online meeting it also records what the Mac
/// plays: the microphone becomes "Ich", the system sound is split into the other people.
/// Transcription and speaker detection run on this Mac; the summary too, unless the user
/// connected an AI provider.
@Observable
@MainActor
final class MeetingController {
    enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing(String)
        case showing(UUID)
        case failed(String, meetingID: UUID?)
    }

    struct Settings {
        let language: String
        let postProcessor: TranscriptPostProcessor
        let summarizes: Bool
        let engine: TextRewriter.Engine
    }

    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?() }
    }
    private(set) var audioLevel: Float = 0
    /// The running recording includes the Mac's sound, so it must not be muted.
    private(set) var isRecordingSystemAudio = false
    /// When the running recording was paused, e.g. for a break or breakout rooms.
    private(set) var pausedAt: Date?
    /// Notes that grow during the recording, nil when switched off or no model is there.
    private(set) var liveNotes: LiveNotesController?
    /// Something the user should know about the current meeting, e.g. an interrupted recording.
    private(set) var notice: String?
    /// The meeting being recorded. It is stored as pending from the start, so a quit or crash
    /// keeps the audio for a later evaluation.
    private(set) var recordingID: UUID?
    let store: MeetingStore
    /// Lets the menu bar show that a meeting is being recorded.
    @ObservationIgnored var onPhaseChange: (() -> Void)?
    /// An evaluation ended: the finished meeting, or the reason it failed.
    @ObservationIgnored var onEvaluationEnd: ((Result<MeetingRecord, MeetingEvaluationFailure>) -> Void)?

    @ObservationIgnored private let settingsProvider: () -> Settings
    @ObservationIgnored private var recorder: AVAudioRecorder?
    /// A `SystemAudioCapture` (macOS 14.2 and later) during an online meeting.
    @ObservationIgnored private var systemCapture: Any?
    /// The live notes free their model; the evaluation waits for that.
    @ObservationIgnored private var liveNotesShutdown: Task<Void, Never>?
    @ObservationIgnored private var recorderObserver: RecorderObserver?
    @ObservationIgnored private var levelTimer: Timer?
    @ObservationIgnored private var recordingActivity: NSObjectProtocol?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    /// Only the latest evaluation may change the phase; a cancelled one must not reset it.
    @ObservationIgnored private var evaluation = 0

    init(store: MeetingStore, settings: @escaping () -> Settings) {
        self.store = store
        settingsProvider = settings
    }

    #if DEBUG
    /// Shows a state without recording, for snapshots.
    func preview(_ phase: Phase) {
        self.phase = phase
    }
    #endif

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }

    /// Meetings need Parakeet: its word timings place every word with a person.
    static var blocker: String? {
        guard ParakeetTranscriber.isSupported else {
            return "Meetings brauchen einen Mac mit Apple-Chip."
        }
        return ParakeetTranscriber.isInstalled
            ? nil
            : "F\u{00FC}r Meetings braucht Blitztext Parakeet. Bitte in den Einstellungen unter Sprachmodell laden."
    }

    /// Recording the Mac's sound needs Core Audio taps.
    static var canRecordSystemAudio: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    // MARK: - Recording

    func start(includingSystemAudio: Bool = false, liveNotes wantsLiveNotes: Bool = false) {
        switch phase {
        case .idle, .showing, .failed: break
        case .recording, .processing: return
        }
        guard Self.blocker == nil else { return }
        notice = nil
        MeetingNotifier.requestPermission()

        let startedAt = Date()
        let record = MeetingRecord(
            id: UUID(),
            createdAt: startedAt,
            title: MeetingRecord.title(startedAt: startedAt),
            duration: 0,
            status: .pending
        )
        // 16 kHz mono PCM: what the speech models read, and recoverable after a crash.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            try FileManager.default.createDirectory(at: MeetingStore.directoryURL, withIntermediateDirectories: true)
            let recorder = try AVAudioRecorder(url: record.audioURL, settings: settings)
            let observer = RecorderObserver { [weak self] in self?.recordingInterrupted() }
            recorder.delegate = observer
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                phase = .failed("Die Aufnahme lie\u{00DF} sich nicht starten. Darf Blitztext das Mikrofon nutzen?", meetingID: nil)
                return
            }
            self.recorder = recorder
            recorderObserver = observer
            recordingID = record.id
            store.upsert(record)
            // Keeps the Mac awake through a long meeting; closing the lid still sends it to sleep.
            recordingActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "Blitztext nimmt ein Meeting auf"
            )
            let withLiveNotes = wantsLiveNotes && LiveNotesController.isAvailable
            let liveBuffer = withLiveNotes && includingSystemAudio ? LiveAudioBuffer() : nil
            if includingSystemAudio { startSystemAudio(for: record, liveBuffer: liveBuffer) }
            if withLiveNotes {
                let settings = settingsProvider()
                let live = LiveNotesController(
                    microphoneURL: record.audioURL,
                    systemBuffer: isRecordingSystemAudio ? liveBuffer : nil,
                    language: settings.language,
                    postProcessor: settings.postProcessor,
                    ownName: Self.ownName
                )
                live.start()
                liveNotes = live
            }
            startMetering()
            phase = .recording(startedAt: startedAt)
            // The speaker models download on first use; fetch them while the network is likely there.
            Task.detached(priority: .utility) { try? await SpeakerDiarizer.shared.prepare() }
        } catch {
            phase = .failed("Die Aufnahme lie\u{00DF} sich nicht starten: \(error.localizedDescription)", meetingID: nil)
        }
    }

    private func startSystemAudio(for record: MeetingRecord, liveBuffer: LiveAudioBuffer?) {
        guard #available(macOS 14.2, *) else { return }
        let capture = SystemAudioCapture()
        capture.liveBuffer = liveBuffer
        capture.onOutputChange = { [weak self] error in
            MainActor.assumeIsolated { self?.outputChanged(error) }
        }
        do {
            try capture.start(writingTo: record.systemAudioURL)
            systemCapture = capture
            isRecordingSystemAudio = true
        } catch {
            capture.stop()
            try? FileManager.default.removeItem(at: record.systemAudioURL)
            notice = "Der Ton des Macs l\u{00E4}sst sich nicht aufnehmen, es l\u{00E4}uft nur das Mikrofon. (\(error.localizedDescription))"
        }
    }

    private static let outputLostNotice = "Das Ausgabeger\u{00E4}t ist weg, der Ton des Macs l\u{00E4}sst sich gerade nicht aufnehmen. Blitztext versucht es weiter, das Mikrofon l\u{00E4}uft."

    /// Headphones unplugged or Bluetooth gone: the capture moves to the current output by itself.
    private func outputChanged(_ error: Error?) {
        if error != nil {
            notice = Self.outputLostNotice
        } else if notice == Self.outputLostNotice {
            notice = nil
        }
    }

    /// Stops the system sound. Without the permission macOS delivers only silence; then the
    /// file is dropped and the meeting is evaluated from the microphone alone.
    private func stopSystemAudio(for record: MeetingRecord) {
        guard #available(macOS 14.2, *), let capture = systemCapture as? SystemAudioCapture else { return }
        capture.stop()
        if capture.peak == 0 {
            try? FileManager.default.removeItem(at: record.systemAudioURL)
            notice = "Vom Ton des Macs kam nichts an. Fehlt die Freigabe unter Datenschutz & Sicherheit > Bildschirm- und Systemaudioaufnahme? Ausgewertet wird nur das Mikrofon."
        }
    }

    /// Stops recording for a while, e.g. while the call is in breakout rooms. Both tracks
    /// skip the pause, so they stay in step.
    func pause() {
        guard case .recording = phase, pausedAt == nil, let recorder else { return }
        recorder.pause()
        if #available(macOS 14.2, *) { (systemCapture as? SystemAudioCapture)?.setPaused(true) }
        pausedAt = Date()
        audioLevel = 0
    }

    func resume() {
        guard case .recording(let startedAt) = phase, let pausedAt, let recorder else { return }
        guard recorder.record() else {
            recordingInterrupted()
            return
        }
        if #available(macOS 14.2, *) { (systemCapture as? SystemAudioCapture)?.setPaused(false) }
        self.pausedAt = nil
        // The clock shows recorded time, without the pause.
        phase = .recording(startedAt: startedAt.addingTimeInterval(Date().timeIntervalSince(pausedAt)))
    }

    /// Ends the recording and starts the evaluation.
    func stop() {
        guard case .recording = phase, let id = finishRecording() else { return }
        process(id)
    }

    /// Throws a running recording away, audio included.
    func discard() {
        guard case .recording = phase else { return }
        let id = recordingID
        recorder?.stop()
        if #available(macOS 14.2, *) { (systemCapture as? SystemAudioCapture)?.stop() }
        endRecording()
        if let id { store.delete(id: id) }
        phase = .idle
    }

    /// Blitztext quits (menu, update, logout): close the file properly. The meeting stays
    /// pending and can be evaluated after the next launch.
    func finishBeforeQuit() {
        guard case .recording = phase else { return }
        _ = finishRecording()
    }

    /// The microphone went away or the encoder failed: evaluate what was recorded.
    private func recordingInterrupted() {
        guard case .recording = phase else { return }
        notice = "Die Aufnahme wurde unterbrochen, zum Beispiel weil das Mikrofon getrennt wurde. Ausgewertet wird, was bis dahin aufgenommen wurde."
        stop()
    }

    /// Stops the recorder and stores the duration. Returns the meeting's ID.
    private func finishRecording() -> UUID? {
        guard let recorder, let id = recordingID else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        if let record = store.meeting(id: id) { stopSystemAudio(for: record) }
        endRecording()
        if var record = store.meeting(id: id) {
            record.duration = max(duration, Self.duration(of: record.audioURL) ?? 0)
            store.upsert(record)
        }
        return id
    }

    private func endRecording() {
        recorder = nil
        pausedAt = nil
        if let liveNotes {
            liveNotesShutdown = Task { await liveNotes.stop() }
            self.liveNotes = nil
        }
        systemCapture = nil
        isRecordingSystemAudio = false
        recorderObserver = nil
        recordingID = nil
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
        if let recordingActivity {
            ProcessInfo.processInfo.endActivity(recordingActivity)
            self.recordingActivity = nil
        }
    }

    private func startMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder, self.pausedAt == nil else { return }
                // A recorder that stopped on its own would otherwise look like silence.
                guard recorder.isRecording else {
                    self.recordingInterrupted()
                    return
                }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.audioLevel = max(0, min(1, (power + 50) / 50))
            }
        }
    }

    private static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    // MARK: - Evaluation

    /// Runs (or retries) transcription, speaker detection and the summary for a stored meeting.
    func process(_ meetingID: UUID) {
        guard var record = store.meeting(id: meetingID), record.id != recordingID else { return }
        let settings = settingsProvider()
        processingTask?.cancel()
        evaluation += 1
        let current = evaluation
        phase = .processing("Wird transkribiert ...")

        processingTask = Task {
            // A long evaluation must not stall because the Mac went to sleep.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "Blitztext wertet ein Meeting aus"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            @MainActor func update(_ newPhase: Phase) {
                guard current == evaluation else { return }
                phase = newPhase
                switch newPhase {
                case .showing(let id):
                    if let record = store.meeting(id: id) { onEvaluationEnd?(.success(record)) }
                case .failed(let message, _):
                    onEvaluationEnd?(.failure(MeetingEvaluationFailure(message: message)))
                default:
                    break
                }
            }

            // A recording cut off by a crash still says zero bytes in its header.
            if WAVRecovery.repairIfNeeded(record.audioURL) || record.duration == 0 {
                record.duration = Self.duration(of: record.audioURL) ?? record.duration
            }

            do {
                let words = try await ParakeetTranscriber.shared.transcribeWords(
                    audioURL: record.audioURL,
                    language: settings.language
                )
                try Task.checkCancellation()

                let paragraphs: [SpeakerAlignment.Paragraph]
                let turns: [SpeakerTurn]
                // An online meeting: the system sound holds the other people.
                var system: (words: [TimedWord], wav: URL)?
                if FileManager.default.fileExists(atPath: record.systemAudioURL.path) {
                    update(.processing("Ton des Macs wird transkribiert ..."))
                    do {
                        system = try await Self.transcribeSystemAudio(record.systemAudioURL, language: settings.language)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // The microphone alone still gives a transcript, e.g. when a crash left the file unreadable.
                        notice = "Der Ton des Macs lie\u{00DF} sich nicht auswerten, ausgewertet wird nur das Mikrofon. (\(error.localizedDescription))"
                    }
                    try Task.checkCancellation()
                }
                defer { if let system { try? FileManager.default.removeItem(at: system.wav) } }

                update(.processing("Stimmen werden erkannt ..."))
                do {
                    if let system {
                        turns = try await SpeakerDiarizer.shared.turns(in: system.wav)
                    } else {
                        turns = try await SpeakerDiarizer.shared.turns(in: record.audioURL)
                    }
                } catch {
                    try Task.checkCancellation()
                    // Keep the audio, so the people can still be told apart once this works.
                    store.upsert(record)
                    update(.failed(
                        "Die Stimmen lie\u{00DF}en sich nicht erkennen. Beim ersten Meeting l\u{00E4}dt Blitztext daf\u{00FC}r ein Modell und braucht Internet. (\(error.localizedDescription))",
                        meetingID: record.id
                    ))
                    return
                }
                try Task.checkCancellation()

                if let system {
                    // The microphone is "Ich", without what it heard from the speakers.
                    let own = SpeakerAlignment.paragraphs(words: EchoFilter.removeEcho(from: words, heard: system.words), turns: [])
                        .map { SpeakerAlignment.Paragraph(speaker: 0, start: $0.start, text: $0.text) }
                    let others = SpeakerAlignment.paragraphs(words: system.words, turns: turns, breaks: own.map(\.start))
                    paragraphs = (others + own).sorted { $0.start < $1.start }
                } else {
                    paragraphs = SpeakerAlignment.paragraphs(words: words, turns: turns)
                }

                let transcribed = paragraphs.compactMap { paragraph -> MeetingTurn? in
                    let text = TranscriptionQualityService.cleanedTranscript(settings.postProcessor.process(paragraph.text))
                    return text.isEmpty ? nil : MeetingTurn(speaker: paragraph.speaker, start: paragraph.start, text: text)
                }
                guard !transcribed.isEmpty else {
                    store.upsert(record)
                    update(.failed("In der Aufnahme wurde keine Sprache erkannt.", meetingID: record.id))
                    return
                }
                record.turns = transcribed

                if settings.summarizes {
                    let model = settings.engine == .provider ? nil : LocalModelStore.shared.preferredInstalled
                    update(.processing(model.map { "Wird zusammengefasst (\($0.name), lokal) ..." } ?? "Wird zusammengefasst ..."))
                    await summarize(&record, engine: settings.engine)
                    try Task.checkCancellation()
                }

                record.status = .done
                // The audio goes only once the transcript is safely on disk.
                if store.upsert(record) {
                    try? FileManager.default.removeItem(at: record.audioURL)
                    try? FileManager.default.removeItem(at: record.systemAudioURL)
                } else {
                    notice = "Das Meeting lie\u{00DF} sich nicht sichern, zum Beispiel weil der Speicher voll ist. Die Aufnahme bleibt erhalten."
                }
                update(.showing(record.id))
            } catch is CancellationError {
                update(.idle)
            } catch {
                store.upsert(record)
                update(.failed(error.localizedDescription, meetingID: record.id))
            }
        }
    }

    /// The other people of an online meeting. Nil when the file holds no speech, e.g. one cut
    /// short by a crash; the microphone then is the whole meeting.
    private static func transcribeSystemAudio(_ url: URL, language: String) async throws -> (words: [TimedWord], wav: URL)? {
        let wav = try AudioFileConverter.convertToWAV(url).url
        do {
            let words = try await ParakeetTranscriber.shared.transcribeWords(audioURL: wav, language: language)
            guard !words.isEmpty else {
                try? FileManager.default.removeItem(at: wav)
                return nil
            }
            return (words, wav)
        } catch {
            try? FileManager.default.removeItem(at: wav)
            throw error
        }
    }

    /// Creates the summary (again), e.g. after renaming people.
    func resummarize(_ meetingID: UUID) async {
        guard var record = store.meeting(id: meetingID) else { return }
        await summarize(&record, engine: settingsProvider().engine)
        store.setSummary(record.summary, note: record.summaryNote, for: meetingID)
    }

    private func summarize(_ record: inout MeetingRecord, engine: TextRewriter.Engine) async {
        // The live notes may still hold the local model; only one copy fits comfortably.
        await liveNotesShutdown?.value
        liveNotesShutdown = nil
        let transcript = record.transcriptText(ownName: Self.ownName)
        // Why the local model did not summarize, when it was tried.
        var localFailure: String?
        #if arch(arm64)
        // A downloaded local model summarizes more exactly than Apple Intelligence; only an
        // explicit "Immer Modell-Anbieter" goes past it. When it fails, the engine setting
        // decides as without it.
        if engine != .provider, let variant = LocalModelStore.shared.preferredInstalled {
            let model = LocalLanguageModel(folder: LocalModelStore.folder(for: variant))
            do {
                try await model.load()
                let backend = MeetingSummarizer.Backend(characterLimit: Self.localModelCharacterLimit) { instruction, text in
                    try await model.complete(instruction: instruction, text: text, maxTokens: 1_500)
                }
                record.summary = try await MeetingSummarizer.summarize(transcript, engine: engine, backend: backend)
                record.summaryNote = nil
                await model.unload()
                return
            } catch {
                localFailure = "\(variant.name) konnte nicht zusammenfassen (\(error.localizedDescription))."
            }
            await model.unload()
        }
        #endif
        guard TextRewriter.canRewrite(engine: engine) else {
            if let localFailure {
                // An earlier summary stays.
                record.summaryNote = localFailure
            } else {
                record.summary = nil
                record.summaryNote = "F\u{00FC}r die Zusammenfassung braucht Blitztext Apple Intelligence oder einen API-Key in den Einstellungen."
            }
            return
        }
        do {
            let fallback = TextRewriter.runsLocally(engine: engine) ? "Apple Intelligence" : "dem Modell-Anbieter"
            record.summary = try await MeetingSummarizer.summarize(transcript, engine: engine)
            record.summaryNote = localFailure.map { "\($0) Stattdessen mit \(fallback) zusammengefasst." }
        } catch {
            record.summaryNote = [localFailure, "Zusammenfassung fehlgeschlagen: \(error.localizedDescription)"]
                .compactMap { $0 }.joined(separator: " ")
        }
    }

    /// The first name of the macOS account, e.g. "Paul", so a summary can assign the tasks
    /// the person at this Mac took on. Nil without a name.
    static var ownName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Characters per request for a local model: about 11,000 tokens of German, which keeps
    /// the memory for the context small while a two-hour meeting needs only a few parts.
    static let localModelCharacterLimit = 40_000

    // MARK: - Results

    func show(_ meetingID: UUID) {
        guard !isRecording, !isProcessing else { return }
        notice = nil
        phase = .showing(meetingID)
    }

    func rename(speaker: Int, to name: String, in meetingID: UUID) {
        guard var record = store.meeting(id: meetingID) else { return }
        record.speakerNames[speaker] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.upsert(record)
    }

    /// Removes a meeting and its audio, finished or not.
    func delete(_ meetingID: UUID) {
        guard meetingID != recordingID else { return }
        store.delete(id: meetingID)
        switch phase {
        case .showing(let id) where id == meetingID, .failed(_, let id?) where id == meetingID:
            notice = nil
            phase = .idle
        default:
            break
        }
    }

    /// Back to the start screen. A running recording or evaluation keeps going.
    func close() {
        switch phase {
        case .showing, .failed:
            notice = nil
            phase = .idle
        default:
            break
        }
    }
}

struct MeetingEvaluationFailure: Error {
    let message: String
}

/// AVAudioRecorder reports a stop it did not ask for through its delegate.
private final class RecorderObserver: NSObject, AVAudioRecorderDelegate {
    private let onInterruption: @MainActor () -> Void

    init(onInterruption: @escaping @MainActor () -> Void) {
        self.onInterruption = onInterruption
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor in onInterruption() }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in onInterruption() }
    }
}
