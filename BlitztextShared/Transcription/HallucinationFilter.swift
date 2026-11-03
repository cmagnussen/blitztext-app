import AVFoundation

/// Drops text the speech models invent: subtitle credits from Whisper's training data
/// ("Untertitel im Auftrag des ZDF, 2021"), doubtful phrases like "Thank you." on a recording
/// with hardly any speech, and anything at all on a short live dictation without speech, where
/// Whisper writes "Thank you." and Parakeet "Oh", "Moment." or a French sentence.
///
/// Whisper's no-speech probability would be the natural gate, but WhisperKit reports it
/// as 0 for these cases, and Parakeet has none, so Blitztext checks whether the recording
/// holds a stretch loud enough and long enough to be a word.
enum HallucinationFilter {
    /// Credits and sign-offs that are never meant as dictation. Normalized, without years.
    static let credits: Set<String> = [
        "untertitel im auftrag des zdf",
        "untertitel im auftrag des zdf für funk",
        "untertitelung im auftrag des zdf",
        "untertitelung des zdf",
        "untertitel des zdf",
        "untertitel der amara org community",
        "untertitel von der amara org community",
        "untertitel von amara org",
        "untertitel von stephanie geiges",
        "copyright wdr",
        "copyright swr",
        "vielen dank fürs zuschauen",
        "vielen dank für s zuschauen",
        "danke fürs zuschauen",
        "danke für s zuschauen",
        "abonniert den kanal",
        "bitte abonnieren",
        "abonniere meinen kanal",
        "subtitles by the amara org community",
        "subtitles by amara org",
        "thanks for watching",
        "thank you for watching",
        "thank you so much for watching",
        "please subscribe",
        "like and subscribe",
        "please like and subscribe",
    ]

    /// Short phrases people do say, so they only count as invented when the recording holds
    /// hardly any speech: Whisper writes them on a cough or a click that passes the speech check.
    static let doubtfulPhrases: Set<String> = [
        "vielen dank", "danke", "danke schön", "dankeschön", "tschüss", "tschüs",
        "bis zum nächsten mal", "bis bald", "bis dann", "das war s", "ende",
        "thank you", "thanks", "thank you very much", "you", "bye", "bye bye",
        "okay", "ok", "ja", "hmm", "hm", "mhm",
        "musik", "music", "applaus", "applause", "lachen",
        "swr", "wdr", "zdf", "ard",
    ]

    /// Shorter than this, the longest run of speech is no word: a quick "Ja." is one run of
    /// about 0.2 s, a click, a chair or a mic bump gives one or two 30 ms frames.
    static let minimumVoicedSeconds = 0.15

    /// Below this longest run, a doubtful phrase counts as invented.
    static let doubtfulBelowSeconds = 0.3

    /// Only live dictations shorter than this are checked for speech before a model runs: an
    /// accidental shortcut or tap. A longer recording may just be quiet (a whisper, a voice
    /// across the room), so it is not thrown away for lack of speech.
    static let accidentalRecordingSeconds: TimeInterval = 3

    /// True when the whole transcript is a credit.
    static func isCredit(_ text: String) -> Bool {
        credits.contains(phraseKey(text))
    }

    /// True when no run of speech in the recording is long enough to be a word.
    static func hasNoSpeech(longestVoicedRun: Double) -> Bool {
        longestVoicedRun < minimumVoicedSeconds
    }

    /// True when the whole transcript is a credit, or a doubtful phrase on a recording with
    /// hardly any speech.
    static func isInvented(_ text: String, longestVoicedRun: Double) -> Bool {
        let key = phraseKey(text)
        guard !key.isEmpty else { return false }
        if credits.contains(key) { return true }
        return longestVoicedRun < doubtfulBelowSeconds && doubtfulPhrases.contains(key)
    }

    /// What Whisper's text leaves for a dictation. Nil on hardly any speech when the text is
    /// invented (a credit or a doubtful phrase on a cough or click), which counts as a dictation
    /// without speech. A credit on a recording with speech leaves no text instead: someone
    /// spoke, so the Mac keeps the recording for another try.
    static func whisperText(_ text: String, longestVoicedRun: Double) -> String? {
        guard isInvented(text, longestVoicedRun: longestVoicedRun) else { return removingTrailingCredits(text) }
        return longestVoicedRun < doubtfulBelowSeconds ? nil : ""
    }

    /// Longest run of speech in samples, see `VoicedRunMeter`.
    static func longestVoicedRun(_ samples: [Float], sampleRate: Double = 16_000) -> Double {
        var meter = VoicedRunMeter(sampleRate: sampleRate)
        meter.add(samples)
        return meter.longestRun
    }

    /// True for a live dictation that was an accidental shortcut: shorter than
    /// `accidentalRecordingSeconds` and without a run of speech long enough to be a word. A
    /// longer one is never dropped, it may just be quiet. False when the file cannot be read.
    static func isAccidentalRecording(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0,
              Double(file.length) / file.processingFormat.sampleRate < accidentalRecordingSeconds,
              let run = longestVoicedRun(in: url) else { return false }
        return hasNoSpeech(longestVoicedRun: run)
    }

    /// Longest run of speech in an audio file, read in pieces. Meant for short recordings: the
    /// noise floor needs the whole file. Nil when the file cannot be read: then nothing may be
    /// dropped for lack of speech.
    static func longestVoicedRun(in url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else { return nil }
        var meter = VoicedRunMeter(sampleRate: file.processingFormat.sampleRate)
        while file.framePosition < file.length {
            guard (try? file.read(into: buffer)) != nil else { return nil }
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            meter.add(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return meter.longestRun
    }

    /// Runs of speech in audio fed in pieces of any length: 30 ms frames, gaps of up to two
    /// frames (60 ms) bridged, so a plosive does not split a word.
    ///
    /// A frame is speech above about -40 dBFS, or, when that is lower, 15 dB above the noise
    /// floor of the recording (its quietest tenth of frames). At a low input volume (27 % on a
    /// MacBook Pro, -5.5 dB) real speech stayed below -40 dBFS but 15 to 30 dB above a floor of
    /// about -66 dBFS; a steady fan or hum stays within a few dB of its floor. Never below
    /// -60 dBFS, so digital silence and dither are no speech.
    struct VoicedRunMeter {
        static let loudLevel: Float = 0.01
        static let aboveNoiseFloor: Float = 5.62
        static let quietestLevel: Float = 0.001

        private let sampleRate: Double
        private let frameLength: Int
        private var frameEnergy: Float = 0
        private var frameFill = 0
        /// RMS of every finished frame.
        private var levels: [Float] = []

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
            frameLength = max(1, Int(sampleRate * 0.03))
        }

        /// Seconds of the longest run so far, including one still going on.
        var longestRun: Double {
            Double(Self.longestRun(in: levels, above: Self.speechLevel(levels)) * frameLength) / sampleRate
        }

        mutating func add<Samples: Sequence>(_ samples: Samples) where Samples.Element == Float {
            for sample in samples {
                frameEnergy += sample * sample
                frameFill += 1
                if frameFill == frameLength {
                    levels.append((frameEnergy / Float(frameLength)).squareRoot())
                    frameEnergy = 0
                    frameFill = 0
                }
            }
        }

        /// The RMS a frame must exceed to count as speech.
        static func speechLevel(_ levels: [Float]) -> Float {
            guard !levels.isEmpty else { return loudLevel }
            let noiseFloor = levels.sorted()[levels.count / 10]
            return min(loudLevel, max(noiseFloor * aboveNoiseFloor, quietestLevel))
        }

        /// Frames in the longest run above `level`.
        static func longestRun(in levels: [Float], above level: Float) -> Int {
            var longest = 0
            var runStart: Int?
            var lastVoiced = 0
            for (index, frame) in levels.enumerated() {
                if frame > level {
                    if runStart == nil { runStart = index }
                    lastVoiced = index
                } else if let start = runStart, index - lastVoiced > 2 {
                    longest = max(longest, lastVoiced - start + 1)
                    runStart = nil
                }
            }
            if let start = runStart { longest = max(longest, lastVoiced - start + 1) }
            return longest
        }
    }

    /// Removes credits at the end of a transcript ("... bis morgen. Untertitel im Auftrag
    /// des ZDF, 2021."). Works on any engine's text, so Parakeet output is covered too.
    static func removingTrailingCredits(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let cut = trailingCreditStart(in: result) {
            result = String(result[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Start of the last one to three sentences when together they are a credit.
    private static func trailingCreditStart(in text: String) -> String.Index? {
        guard !text.isEmpty else { return nil }
        let starts = sentenceStarts(in: text)
        for start in starts.suffix(3).reversed() {
            if credits.contains(phraseKey(String(text[start...]))) {
                return start
            }
        }
        return nil
    }

    /// Index 0 and every position after ".", "!", "?" or "…" plus whitespace, or after a
    /// line break. "Amara.org" stays one sentence.
    private static func sentenceStarts(in text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isNewline, next < text.endIndex {
                starts.append(next)
            } else if ".!?…".contains(character), next < text.endIndex, text[next].isWhitespace {
                starts.append(next)
            }
            index = next
        }
        return starts
    }

    /// Lowercased letters and digits, everything else becomes a single space.
    static func normalized(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                result.append(character)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// Like `normalized`, without numbers, so "ZDF, 2021" and "ZDF 2017" match "zdf".
    static func phraseKey(_ text: String) -> String {
        normalized(text)
            .split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }
}
