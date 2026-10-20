import Foundation

/// Removes from the microphone what it only heard from the Mac's speakers. In an online
/// meeting without headphones the other side comes out of the speakers and into the
/// microphone, so the same words show up in both tracks at about the same time.
/// Apple's echo cancellation would do this on the audio, but it stops the system sound
/// tap from delivering anything (tested on macOS 27).
enum EchoFilter {
    /// How far apart, after aligning both tracks, the same word may be and still count as echo.
    static let window: TimeInterval = 0.6
    /// The two tracks start a moment apart and the speakers add a little delay.
    static let maximumOffset: TimeInterval = 2.0

    static func removeEcho(from microphone: [TimedWord], heard system: [TimedWord]) -> [TimedWord] {
        guard !microphone.isEmpty, !system.isEmpty else { return microphone }
        var timesByKey: [String: [TimeInterval]] = [:]
        for word in system {
            let key = key(word.text)
            guard !key.isEmpty else { continue }
            timesByKey[key, default: []].append(word.start)
        }
        for key in timesByKey.keys { timesByKey[key]?.sort() }

        let keys = microphone.map { key($0.text) }
        let offset = bestOffset(microphone, keys: keys, timesByKey: timesByKey)
        let matches = microphone.indices.map { index in
            !keys[index].isEmpty
                && hasTime(near: microphone[index].start - offset, in: timesByKey[keys[index]] ?? [], tolerance: window)
        }

        var echo = [Bool](repeating: false, count: microphone.count)
        // A single matching word is often coincidence ("ja", "und"); echo comes in runs.
        // Single letters ("I", "a") carry no key and do not break a run.
        let significant = microphone.indices.filter { !keys[$0].isEmpty }
        for (position, index) in significant.enumerated() where matches[index] {
            let previous = position > 0 && matches[significant[position - 1]]
            let next = position + 1 < significant.count && matches[significant[position + 1]]
            echo[index] = previous || next
        }
        // Words the microphone garbled inside a run of echo belong to it as well.
        let marked = echo
        for index in microphone.indices where !marked[index] {
            let before = (max(0, index - 2)..<index).contains { marked[$0] }
            let after = (index + 1..<min(microphone.count, index + 3)).contains { marked[$0] }
            echo[index] = before && after
        }
        removeFragments(&echo, microphone: microphone, keys: keys, matches: matches, system: system, offset: offset)
        return microphone.indices.filter { !echo[$0] }.map { microphone[$0] }
    }

    /// What is left of a garbled echo: short scraps ("I I", "a little spot work with")
    /// while the other side is talking. Dropped when they have at most `fragmentWords`
    /// words or when much of them also is in the system sound, and only where the
    /// microphone demonstrably picked up the speakers: echo within `echoNearby` seconds, or
    /// at least two words of the scrap itself. With headphones there is no echo, so short
    /// replies like "Mach ich" stay even while the others talk. Own sentences in a pause,
    /// and longer ones during crosstalk, stay too.
    static let fragmentWords = 4
    static let echoNearby: TimeInterval = 20

    private static func removeFragments(
        _ echo: inout [Bool],
        microphone: [TimedWord],
        keys: [String],
        matches: [Bool],
        system: [TimedWord],
        offset: TimeInterval
    ) {
        let systemStarts = system.map(\.start).sorted()
        let echoStarts = microphone.indices.filter { echo[$0] }.map { microphone[$0].start }.sorted()
        var segments: [[Int]] = []
        for index in microphone.indices where !echo[index] {
            if let last = segments.last?.last, microphone[index].start - microphone[last].end <= 1.0 {
                segments[segments.count - 1].append(index)
            } else {
                segments.append([index])
            }
        }
        for segment in segments {
            guard let first = segment.first, let last = segment.last else { continue }
            let start = microphone[first].start - offset
            let end = microphone[last].end - offset
            let othersTalking = hasTime(near: (start + end) / 2, in: systemStarts, tolerance: (end - start) / 2 + 0.5)
            guard othersTalking else { continue }
            let significant = segment.filter { !keys[$0].isEmpty }
            let matched = significant.filter { matches[$0] }.count
            let middle = (microphone[first].start + microphone[last].end) / 2
            let span = (microphone[last].end - microphone[first].start) / 2
            let speakersAudible = matched >= 2 || hasTime(near: middle, in: echoStarts, tolerance: span + echoNearby)
            guard speakersAudible else { continue }
            let mostlyEcho = !significant.isEmpty && Double(matched) / Double(significant.count) >= 0.4
            if segment.count <= fragmentWords || mostlyEcho {
                for index in segment { echo[index] = true }
            }
        }
    }

    /// The shift between the tracks at which most microphone words find themselves in the
    /// system sound; 0 when there is hardly any echo, e.g. with headphones.
    private static func bestOffset(_ microphone: [TimedWord], keys: [String], timesByKey: [String: [TimeInterval]]) -> TimeInterval {
        var best: (offset: TimeInterval, count: Int) = (0, 0)
        for step in Int(-maximumOffset * 10)...Int(maximumOffset * 10) {
            let offset = TimeInterval(step) / 10
            let count = microphone.indices.filter { index in
                hasTime(near: microphone[index].start - offset, in: timesByKey[keys[index]] ?? [], tolerance: 0.3)
            }.count
            if count > best.count { best = (offset, count) }
        }
        return best.count >= 3 ? best.offset : 0
    }

    /// Whether the sorted `times` hold a value within `tolerance` of `time`.
    private static func hasTime(near time: TimeInterval, in times: [TimeInterval], tolerance: TimeInterval) -> Bool {
        var low = 0, high = times.count
        while low < high {
            let middle = (low + high) / 2
            if times[middle] < time - tolerance { low = middle + 1 } else { high = middle }
        }
        return low < times.count && times[low] <= time + tolerance
    }

    /// "Kanal," and "kanal" are the same word; single letters say too little.
    private static func key(_ word: String) -> String {
        let letters = word.lowercased().filter { $0.isLetter || $0.isNumber }
        return letters.count > 1 ? letters : ""
    }
}
