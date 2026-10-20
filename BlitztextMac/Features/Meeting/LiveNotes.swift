import AVFoundation
import Foundation
import Observation

/// Notes that grow while a meeting runs: every few minutes the newest stretch is transcribed
/// and the model updates topics, decisions, open questions and to-dos. Runs on this Mac only,
/// with the downloaded local model or Apple Intelligence, never with a cloud provider, and
/// reads the recording without touching it.
@Observable
@MainActor
final class LiveNotesController {
    /// How often the notes catch up with the meeting.
    static let interval: TimeInterval = 150
    /// Audio kept for a later try when transcribing fails, per track.
    static let maximumPendingAudio = 300

    private(set) var notes = ""
    private(set) var updatedAt: Date?
    private(set) var isUpdating = false
    private(set) var problem: String?
    /// "Was habe ich verpasst?"
    private(set) var catchUp: String?
    private(set) var isCatchingUp = false
    /// The model that writes the notes, e.g. "Gemma 4 12B".
    private(set) var modelName: String?

    @ObservationIgnored private var microphone: MicrophoneFileTail
    @ObservationIgnored private let systemBuffer: LiveAudioBuffer?
    @ObservationIgnored private let language: String
    @ObservationIgnored private let postProcessor: TranscriptPostProcessor
    @ObservationIgnored private let ownName: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var catchUpTask: Task<Void, Never>?
    /// One load for updates and "Was habe ich verpasst?" together, so the model is in memory once.
    @ObservationIgnored private var backendLoad: Task<LiveNotesBackend, Error>?
    @ObservationIgnored private var isStopped = false
    /// Audio read from the recording but not transcribed yet; both tracks start at the same moment.
    @ObservationIgnored private var pendingMicrophone: [Float] = []
    @ObservationIgnored private var pendingSystem: [Float] = []
    /// Transcribed text that is not in the notes yet.
    @ObservationIgnored private var pendingText = ""
    /// The start of `pendingText` the model failed on last time.
    @ObservationIgnored private var failedText: String?
    /// What was said, stretch by stretch, for "Was habe ich verpasst?".
    @ObservationIgnored private var stretches: [(at: Date, text: String)] = []

    init(microphoneURL: URL, systemBuffer: LiveAudioBuffer?, language: String, postProcessor: TranscriptPostProcessor, ownName: String?) {
        microphone = MicrophoneFileTail(url: microphoneURL)
        self.systemBuffer = systemBuffer
        self.language = language
        self.postProcessor = postProcessor
        self.ownName = ownName
    }

    /// Notes need a model on this Mac: a downloaded one or Apple Intelligence.
    static var isAvailable: Bool {
        LocalModelStore.shared.preferredInstalled != nil || TextRewriter.isLocalAvailable
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    /// Ends the notes and frees the model; the meeting's evaluation waits for this.
    func stop() async {
        isStopped = true
        timer?.invalidate()
        timer = nil
        task?.cancel()
        catchUpTask?.cancel()
        await task?.value
        await catchUpTask?.value
        // A load still running ends with a model in memory; free it as well.
        if let backend = try? await backendLoad?.value { await backend.close() }
        backendLoad = nil
    }

    /// Transcribes what is new and updates the notes. Waits for more when less than a few
    /// seconds were recorded, e.g. during a pause; nothing recorded gets lost on the way.
    func update() {
        guard !isUpdating, !isStopped else { return }
        pendingMicrophone += microphone.read()
        pendingSystem += systemBuffer?.takeAll() ?? []
        keepPendingAudioBounded()
        let hasNewAudio = max(pendingMicrophone.count, pendingSystem.count) >= LiveAudioBuffer.sampleRate * 5
        guard hasNewAudio || !pendingText.isEmpty else { return }
        isUpdating = true
        task = Task {
            defer { isUpdating = false }
            do {
                if hasNewAudio {
                    let stretch = try await transcribe(microphone: pendingMicrophone, system: pendingSystem)
                    pendingMicrophone = []
                    pendingSystem = []
                    if !stretch.isEmpty {
                        stretches.append((Date(), stretch))
                        pendingText += (pendingText.isEmpty ? "" : "\n") + stretch
                    }
                }
                guard !pendingText.isEmpty, !Task.isCancelled else { return }
                let leftOut = try await writeNotes(with: loadedBackend())
                updatedAt = Date()
                problem = leftOut
                    ? "Ein Abschnitt lie\u{00DF} sich nicht in die Notizen \u{00FC}bernehmen. Im Transkript nach dem Meeting fehlt nichts."
                    : nil
            } catch is CancellationError {
            } catch {
                problem = "Live-Notizen gerade nicht m\u{00F6}glich: \(error.localizedDescription)"
            }
        }
    }

    /// Works the pending text into the notes, in parts when it does not fit at once (after a
    /// failed update, or with Apple Intelligence's small context). The model answers the same
    /// text the same way every time, so text it fails on twice, or that makes its answer too
    /// long once, is left out instead of blocking every later update. Returns whether that
    /// happened.
    private func writeNotes(with backend: LiveNotesBackend) async throws -> Bool {
        let german = MeetingSummarizer.isGermanMeeting(stretches.map(\.text).joined(separator: "\n"))
        let instruction = german ? Self.instruction : Self.englishInstruction
        let heading = german ? "Neuer Abschnitt:\n" : "New section:\n"
        var leftOut = false
        while !pendingText.isEmpty {
            let earlier = notes.isEmpty ? "" : (german ? "Bisherige Notizen:\n" : "Notes so far:\n") + notes + "\n\n"
            let room = backend.characterLimit - earlier.count - heading.count
            guard room >= 1_000 else { throw LiveNotesFailure.notesTooLong }
            var end = TextParts.endOfLeadingPart(of: pendingText, limit: room)
            let part = String(pendingText[..<end])
            do {
                let result = try await backend.complete(instruction, earlier + heading + part)
                try Task.checkCancellation()
                notes = MeetingSummarizer.cleaned(result)
                failedText = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if case LiveNotesFailure.answerCutOff = error {
                    // Leave out this part.
                } else if let failedText, part.hasPrefix(failedText) {
                    end = pendingText.index(pendingText.startIndex, offsetBy: failedText.count)
                } else {
                    failedText = part
                    throw error
                }
                failedText = nil
                leftOut = true
            }
            pendingText = String(pendingText[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return leftOut
    }

    /// Drops the oldest audio once transcribing failed for minutes, the same span on both
    /// tracks so they stay in step.
    private func keepPendingAudioBounded() {
        let excess = max(pendingMicrophone.count, pendingSystem.count) - LiveAudioBuffer.sampleRate * Self.maximumPendingAudio
        guard excess > 0 else { return }
        pendingMicrophone.removeFirst(min(excess, pendingMicrophone.count))
        pendingSystem.removeFirst(min(excess, pendingSystem.count))
    }

    /// A few sentences on the last ten minutes.
    func catchUpOnLastMinutes(_ minutes: Double = 10) {
        guard !isCatchingUp, !isStopped else { return }
        let since = Date().addingTimeInterval(-minutes * 60)
        let recent = stretches.filter { $0.at >= since }.map(\.text).joined(separator: "\n\n")
        guard !recent.isEmpty else {
            catchUp = "Noch nichts aufgeschrieben. Die ersten Notizen kommen nach etwa zweieinhalb Minuten."
            return
        }
        isCatchingUp = true
        catchUpTask = Task {
            defer { isCatchingUp = false }
            do {
                let backend = try await loadedBackend()
                // In a busy meeting ten minutes can be more than the model reads; the newest part counts.
                let text = String(recent[TextParts.startOfTrailingPart(of: recent, limit: backend.characterLimit)...])
                let german = MeetingSummarizer.isGermanMeeting(text)
                let answer = try await backend.complete(german ? Self.catchUpInstruction : Self.englishCatchUpInstruction, text)
                try Task.checkCancellation()
                catchUp = answer
            } catch is CancellationError {
            } catch {
                catchUp = "Gerade nicht m\u{00F6}glich: \(error.localizedDescription)"
            }
        }
    }

    func dismissCatchUp() {
        catchUp = nil
    }

    #if DEBUG
    /// What was transcribed so far, for the debug check.
    var transcriptForCheck: String { stretches.map(\.text).joined(separator: "\n") }
    #endif

    private func loadedBackend() async throws -> LiveNotesBackend {
        let load = backendLoad ?? Task { try await LiveNotesBackend.make() }
        backendLoad = load
        do {
            let backend = try await load.value
            modelName = backend.name
            return backend
        } catch {
            // The next update tries again, e.g. once memory is free.
            if backendLoad == load { backendLoad = nil }
            throw error
        }
    }

    // MARK: - Transcription

    /// The newest stretch as "Ich: ..." and "Andere: ..." paragraphs. People are only told
    /// apart at the end; live, the system sound is everybody else.
    private func transcribe(microphone: [Float], system: [Float]) async throws -> String {
        let own = try await words(of: microphone)
        let others = try await words(of: system)
        let kept = others.isEmpty ? own : EchoFilter.removeEcho(from: own, heard: others)
        let me = ownName ?? "Ich"
        var lines: [(start: TimeInterval, text: String)] = []
        if others.isEmpty {
            lines = SpeakerAlignment.paragraphs(words: kept, turns: []).map { ($0.start, $0.text) }
        } else {
            lines = SpeakerAlignment.paragraphs(words: kept, turns: []).map { ($0.start, "\(me): \($0.text)") }
                + SpeakerAlignment.paragraphs(words: others, turns: []).map { ($0.start, "Andere: \($0.text)") }
        }
        return lines.sorted { $0.start < $1.start }
            .map { TranscriptionQualityService.cleanedTranscript(postProcessor.process($0.text)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func words(of samples: [Float]) async throws -> [TimedWord] {
        guard samples.count >= LiveAudioBuffer.sampleRate * 2 else { return [] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-live-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try LiveAudioBuffer.write(samples, to: url)
        return try await ParakeetTranscriber.shared.transcribeWords(audioURL: url, language: language)
    }

    // MARK: - Instructions

    static let instruction = """
    Du führst laufende Notizen zu einem Meeting, das gerade stattfindet. Du erhältst die bisherigen Notizen und den neuesten Abschnitt des Transkripts. Wer spricht, ist markiert; „Andere“ sind alle Personen außer der, die die Notizen nutzt.
    Gib die vollständigen, aktualisierten Notizen zurück, genau mit diesen vier Abschnitten, jede Überschrift auf einer eigenen Zeile und ihre Punkte direkt darunter:

    Themen
    Spiegelstriche mit „- “: worüber gesprochen wurde.

    Entscheidungen
    Spiegelstriche mit „- “: nur, was die Runde ausdrücklich vereinbart hat, keine Meinung und kein Vorschlag.

    Offene Fragen
    Spiegelstriche mit „- “: was noch ungeklärt ist.

    To-dos
    Spiegelstriche im Format „- Wer: Was“. „Wer“ ist der Name der Person, die es laut Transkript übernimmt. Nennt das Transkript niemanden, schreibe „- Offen: Was“.

    Höchstens acht Punkte je Abschnitt; werden es mehr, fasse Ähnliches zusammen. Übernimm aus den bisherigen Notizen, was weiterhin gilt, und ergänze das Neue. Hat ein Abschnitt keinen Inhalt, steht darunter „- Noch keine“.
    Erfinde nichts dazu, vor allem keine Termine, Fristen, Namen oder Zahlen. Keine Einleitung.
    """

    static let englishInstruction = """
    You keep running notes on a meeting that is taking place right now. You receive the notes so far and the newest section of the transcript. Speakers are marked; "Andere" means everybody except the person using the notes.
    Return the complete, updated notes with exactly these four sections, each heading on its own line and its bullet points right below it:

    Topics
    Bullet points starting with "- ": what was discussed.

    Decisions
    Bullet points starting with "- ": only what the group explicitly agreed on, not an opinion or a proposal.

    Open questions
    Bullet points starting with "- ": what is still unresolved.

    To-dos
    Bullet points in the format "- Who: What". "Who" is the name of the person who takes it on according to the transcript. If the transcript names nobody, write "- Open: What".

    At most eight bullet points per section; when there are more, merge similar ones. Keep from the notes so far what still holds and add what is new. A section without content gets "- None yet" below it.
    Do not invent anything, above all no dates, deadlines, names or numbers. No introduction.
    """

    static let catchUpInstruction = """
    Du erhältst das Transkript der letzten Minuten eines laufenden Meetings. Fasse in drei bis fünf kurzen Sätzen zusammen, was besprochen wurde, das Wichtigste zuerst: Entscheidungen, Aufgaben, offene Fragen. Nenne als Entscheidung nur, was ausdrücklich vereinbart wurde; Meinungen und Vorschläge sind keine. Erfinde nichts dazu. Keine Einleitung.
    """

    static let englishCatchUpInstruction = """
    You receive the transcript of the last minutes of a meeting that is still running. Summarize in three to five short sentences what was discussed, most important first: decisions, tasks, open questions. Call something a decision only when it was explicitly agreed; opinions and proposals are not. Do not invent anything. No introduction.
    """
}

enum LiveNotesFailure: LocalizedError {
    case notesTooLong
    /// The model's answer reached its token limit, e.g. because it repeated itself on a
    /// garbled transcript.
    case answerCutOff

    var errorDescription: String? {
        switch self {
        case .notesTooLong: "Die Notizen sind zu lang f\u{00FC}r das Modell geworden."
        case .answerCutOff: "Die Antwort des Modells wurde zu lang."
        }
    }
}

/// The model behind the live notes: the downloaded local model if there is one and it
/// loads, otherwise Apple Intelligence. Never a cloud provider, whatever the engine setting.
/// The local model stays loaded for the whole meeting.
struct LiveNotesBackend {
    let name: String
    /// Characters per request, earlier notes and new transcript together.
    let characterLimit: Int
    let complete: (_ instruction: String, _ text: String) async throws -> String
    let close: () async -> Void

    @MainActor
    static func make() async throws -> LiveNotesBackend {
        var localFailure: Error?
        #if arch(arm64)
        if let variant = LocalModelStore.shared.preferredInstalled {
            let model = LocalLanguageModel(folder: LocalModelStore.folder(for: variant))
            do {
                try await model.load()
                return LiveNotesBackend(
                    name: variant.name,
                    characterLimit: MeetingController.localModelCharacterLimit,
                    // Cut-off notes would be the base of every later update; better keep the last ones.
                    complete: { instruction, text in
                        do {
                            return try await model.complete(instruction: instruction, text: text, maxTokens: 1_500, failsWhenCutOff: true)
                        } catch LocalLanguageModel.Failure.cutOff {
                            throw LiveNotesFailure.answerCutOff
                        }
                    },
                    close: { await model.unload() }
                )
            } catch {
                await model.unload()
                localFailure = error
            }
        }
        #endif
        guard TextRewriter.isLocalAvailable else {
            throw localFailure ?? TextRewriter.RewriteError.noModel
        }
        return LiveNotesBackend(
            name: "Apple Intelligence",
            characterLimit: MeetingSummarizer.localCharacterLimit,
            complete: { instruction, text in
                try await TextRewriter.rewriteOnDevice(text, instruction: instruction, deterministic: true)
            },
            close: {}
        )
    }
}

/// Audio for the live notes, 16 kHz mono, filled on the capture thread and emptied on
/// the main actor.
final class LiveAudioBuffer: @unchecked Sendable {
    static let sampleRate = 16_000

    private let lock = NSLock()
    private var samples: [Float] = []
    /// Used on the capture queue only.
    private var converter: AVAudioConverter?
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!

    func append(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.downmix = true
        }
        guard let converter,
              let output = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64
              ) else { return }
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
        guard error == nil, let data = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let converted = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
        lock.lock()
        samples += converted
        lock.unlock()
    }

    func takeAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let all = samples
        samples.removeAll(keepingCapacity: true)
        return all
    }

    static func write(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}

/// New samples of the microphone recording while AVAudioRecorder still writes it: 16 kHz
/// mono 16-bit PCM after a WAV header whose sizes are filled in only at the end.
struct MicrophoneFileTail {
    let url: URL
    private var offset: UInt64?

    init(url: URL) {
        self.url = url
    }

    mutating func read() -> [Float] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        if offset == nil { offset = Self.dataOffset(handle) }
        guard let start = offset, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), data.count >= 2 else { return [] }
        let usable = data.count - data.count % 2
        offset = start + UInt64(usable)
        var samples = [Float]()
        samples.reserveCapacity(usable / 2)
        data.withUnsafeBytes { raw in
            for index in stride(from: 0, to: usable, by: 2) {
                samples.append(Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index, as: Int16.self))) / 32_768)
            }
        }
        return samples
    }

    /// Walks the RIFF chunks to the first byte of "data".
    static func dataOffset(_ handle: FileHandle) -> UInt64? {
        var position: UInt64 = 12
        for _ in 0..<16 {
            guard (try? handle.seek(toOffset: position)) != nil,
                  let header = try? handle.read(upToCount: 8), header.count == 8 else { return nil }
            let id = String(decoding: header.prefix(4), as: UTF8.self)
            let size = header.withUnsafeBytes { UInt64(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))) }
            position += 8
            if id == "data" { return position }
            position += size + size % 2
        }
        return nil
    }
}
