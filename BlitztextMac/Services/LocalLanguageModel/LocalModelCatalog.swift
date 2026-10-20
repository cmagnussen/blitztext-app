import Foundation

/// The local language models Blitztext can download for meeting summaries: Gemma 4 by
/// Google (Apache 2.0) in the 4-bit MLX conversion, pinned to one revision with a checksum
/// for every file, and what a Mac needs to run them.
struct LocalModelVariant: Identifiable, Equatable, Sendable {
    struct File: Equatable, Sendable {
        let name: String
        let size: Int64
        let sha256: String
    }

    enum Support: Equatable, Sendable {
        case available
        case unavailable(String)
    }

    let id: String
    let name: String
    /// One line on what the variant is for.
    let purpose: String
    let repository: String
    let revision: String
    let files: [File]
    /// Memory the model takes while it summarizes, in GB (measured on an M5 with a short
    /// meeting; long transcripts add some for the context).
    let memoryInUse: Double
    /// Memory a Mac needs so that the model, a call app and macOS fit at the same time.
    let minimumMemoryGB: Int

    var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
    }

    func support(memoryGB: Int = Self.installedMemoryGB, appleSilicon: Bool = Self.isAppleSilicon) -> Support {
        guard appleSilicon else { return .unavailable("Braucht einen Mac mit Apple-Chip.") }
        guard memoryGB >= minimumMemoryGB else {
            return .unavailable("Braucht mindestens \(minimumMemoryGB) GB Arbeitsspeicher, dieser Mac hat \(memoryGB) GB.")
        }
        return .available
    }

    /// The largest variant this Mac can run, nil when none fits.
    static func recommended(memoryGB: Int = installedMemoryGB, appleSilicon: Bool = isAppleSilicon) -> LocalModelVariant? {
        all.last { $0.support(memoryGB: memoryGB, appleSilicon: appleSilicon) == .available }
    }

    static var installedMemoryGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// From small to large.
    static let all = [gemma4E4B, gemma4_12B]

    static let gemma4E4B = LocalModelVariant(
        id: "gemma-4-e4b-it-4bit",
        name: "Gemma 4 E4B",
        purpose: "Kompakt und schnell",
        repository: "mlx-community/gemma-4-e4b-it-4bit",
        revision: "475b9088d29754a3379866cf5aeb6b41acd313c2",
        files: [
            File(name: "config.json", size: 6_628, sha256: "780ccb3a514a5f1ced161d383f948fc22eca9b84b752ca19494f625bd9bad7a6"),
            File(name: "generation_config.json", size: 208, sha256: "d4226bbe3117d2d253ba4609720ba82c6c4ce4627a9a6ae05387c78983ac03de"),
            File(name: "chat_template.jinja", size: 17_336, sha256: "2f1b4d75d067bae3fe44e676721c7f077d243bc007156cb9c2f8b5836613d082"),
            File(name: "processor_config.json", size: 1_316, sha256: "de3e580aebdc98272d4c4547daffe6525fcbae18a83a0e0bcf0d7444d4ee6f37"),
            File(name: "tokenizer_config.json", size: 2_740, sha256: "080d9e1aff284e2f6043889cd05367966f7c7b80e025fbc0b06745e218158656"),
            File(name: "tokenizer.json", size: 32_169_626, sha256: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"),
            File(name: "model.safetensors.index.json", size: 240_961, sha256: "f8accac59ee7efe87e0c298c854610b262c3cadd477407503147c71209ff0093"),
            File(name: "model.safetensors", size: 5_146_800_534, sha256: "932b8271fc3fe65adcc78b96c10c6268bbfb13e8f67d1358727c0d6ee97e1eff"),
        ],
        memoryInUse: 4.8,
        minimumMemoryGB: 16
    )

    static let gemma4_12B = LocalModelVariant(
        id: "gemma-4-12b-it-4bit",
        name: "Gemma 4 12B",
        purpose: "Gr\u{00FC}ndlicher, f\u{00FC}r lange Meetings",
        repository: "mlx-community/gemma-4-12B-it-4bit",
        revision: "73bcf09092aa277861d5a191b989b666f7f32e8f",
        files: [
            File(name: "config.json", size: 5_415, sha256: "fbc1c1cb48ed86ec98482b2d41f5a03d3991aba74b7c29a93d430761e6518a38"),
            File(name: "generation_config.json", size: 260, sha256: "a8349d9bd64cc5841297fcb5002f0fdc4749c473c8f1b10ea337f9ce4ee7014e"),
            File(name: "chat_template.jinja", size: 17_466, sha256: "36e3a42e5cf14cd0020e72d92e1fdd9970f59b82170e421f0cbe1bb42bead3f0"),
            File(name: "processor_config.json", size: 868, sha256: "016a1db9c4f41ea0c61919c46855ea5e7c45c6e4ae4bfbedfb5b6bed79a2fe92"),
            File(name: "tokenizer_config.json", size: 2_719, sha256: "fc1384a911d2c9860ac07bc3ceafff20bff26695991744b7dbe5e1e4522bfa57"),
            File(name: "tokenizer.json", size: 32_169_626, sha256: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"),
            File(name: "model.safetensors.index.json", size: 135_329, sha256: "9ac99e7a6cf3e4d40eb8df01644fe9c04036ace94f3389df35db9d9449758516"),
            File(name: "model-00001-of-00002.safetensors", size: 5_351_756_584, sha256: "0d58feed0c98a69c07317b4481aeae5ab2785f12a496ea96ab24c4842808de78"),
            File(name: "model-00002-of-00002.safetensors", size: 1_389_282_927, sha256: "5b00a1bcb596ce6e827b4cdea6ecf2a0f35bb01306eb87c1ea4b3bcde36c7755"),
        ],
        memoryInUse: 6.8,
        minimumMemoryGB: 24
    )
}
