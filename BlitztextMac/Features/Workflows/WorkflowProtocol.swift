import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case localTranscription
    case textImprover
    case dampfAblassen
    case emojiText
    case translate
    case summarize
    case format

    var id: String { rawValue }

    static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTranscription }
    }

    var displayName: String {
        switch self {
        case .transcription: return "Blitztext"
        case .localTranscription: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        case .translate: return "Blitztext \u{2192}EN"
        case .summarize: return "Zusammenfassen"
        case .format: return "Format"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .localTranscription: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        case .translate: return "globe"
        case .summarize: return "doc.plaintext"
        case .format: return "list.bullet"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Sprache rein. Text raus."
        case .localTranscription: return "Nur lokal. Kein Server."
        case .textImprover: return "Geschrieben sprechen."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        case .translate: return "Deutsch sprechen. Englisch raus."
        case .summarize: return "Sprechen. Kurzfassung raus."
        case .format: return "Stichpunkte \u{00B7} E-Mail \u{00B7} To-do."
        }
    }

    var hotkeyLabel: String {
        switch self {
        case .transcription: return "fn + Shift"
        case .localTranscription: return "fn + Shift + Ctrl"
        case .textImprover: return "fn + Control"
        case .dampfAblassen: return "fn + Option"
        case .emojiText: return "Men\u{00FC}"
        case .translate: return "fn + Cmd"
        case .summarize: return "Men\u{00FC}"
        case .format: return "Men\u{00FC}"
        }
    }

    var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .localTranscription: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        case .translate: return "indigo"
        case .summarize: return "teal"
        case .format: return "mint"
        }
    }
}

enum TextFormatKind: String, Codable, CaseIterable, Identifiable {
    case bullets
    case email
    case todo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bullets: return "Stichpunkte"
        case .email: return "E-Mail"
        case .todo: return "To-do"
        }
    }

    var icon: String {
        switch self {
        case .bullets: return "list.bullet"
        case .email: return "envelope"
        case .todo: return "checklist"
        }
    }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

// MARK: - App Settings

struct AppSettings: Codable {
    static let defaultLocalLLMBaseURL = "http://localhost:8080/v1"
    static let defaultLocalLLMModel = "qwen"
    static let defaultLocalLLMServerPath = "/opt/homebrew/bin/llama-server"
    static var defaultLocalLLMModelPath: String {
        NSHomeDirectory() + "/Library/Application Support/app.cotypist.Cotypist/Models/Qwen3-8B.i1-Q4_K_M.gguf"
    }

    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    // Lokales KI-Modell (offline Rewrite über OpenAI-kompatiblen Server, z. B. llama-server)
    var localLLMEnabled: Bool = false
    var localLLMBaseURL: String = AppSettings.defaultLocalLLMBaseURL
    var localLLMFastModel: String = AppSettings.defaultLocalLLMModel
    var localLLMStrongModel: String = AppSettings.defaultLocalLLMModel
    // Autostart: Blitztext startet den llama-server beim App-Start selbst.
    var localLLMAutostart: Bool = true
    var localLLMServerPath: String = AppSettings.defaultLocalLLMServerPath
    var localLLMModelPath: String = AppSettings.defaultLocalLLMModelPath
    // Lernende Korrekturen: feste Ersetzungen, die auf jeden finalen Text angewendet werden.
    var corrections: [TextCorrection] = []
    // Hängt nach jedem Diktat ein Leerzeichen an, damit aufeinanderfolgende Diktate getrennt bleiben.
    var appendTrailingSpace: Bool = true
    // Darstellung: false = Klassisch, true = Modern (Ring-Icon + Frosted-Glass-Popover).
    var useModernTheme: Bool = false

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        localLLMEnabled: Bool = false,
        localLLMBaseURL: String = AppSettings.defaultLocalLLMBaseURL,
        localLLMFastModel: String = AppSettings.defaultLocalLLMModel,
        localLLMStrongModel: String = AppSettings.defaultLocalLLMModel,
        localLLMAutostart: Bool = true,
        localLLMServerPath: String = AppSettings.defaultLocalLLMServerPath,
        localLLMModelPath: String = AppSettings.defaultLocalLLMModelPath,
        corrections: [TextCorrection] = [],
        appendTrailingSpace: Bool = true,
        useModernTheme: Bool = false
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.localLLMEnabled = localLLMEnabled
        self.localLLMBaseURL = localLLMBaseURL
        self.localLLMFastModel = localLLMFastModel
        self.localLLMStrongModel = localLLMStrongModel
        self.localLLMAutostart = localLLMAutostart
        self.localLLMServerPath = localLLMServerPath
        self.localLLMModelPath = localLLMModelPath
        self.corrections = corrections
        self.appendTrailingSpace = appendTrailingSpace
        self.useModernTheme = useModernTheme
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case localLLMEnabled
        case localLLMBaseURL
        case localLLMFastModel
        case localLLMStrongModel
        case localLLMAutostart
        case localLLMServerPath
        case localLLMModelPath
        case corrections
        case appendTrailingSpace
        case useModernTheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        secureLocalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        localLLMEnabled = try container.decodeIfPresent(Bool.self, forKey: .localLLMEnabled) ?? false
        localLLMBaseURL = try container.decodeIfPresent(
            String.self,
            forKey: .localLLMBaseURL
        ) ?? AppSettings.defaultLocalLLMBaseURL
        localLLMFastModel = try container.decodeIfPresent(
            String.self,
            forKey: .localLLMFastModel
        ) ?? AppSettings.defaultLocalLLMModel
        localLLMStrongModel = try container.decodeIfPresent(
            String.self,
            forKey: .localLLMStrongModel
        ) ?? AppSettings.defaultLocalLLMModel
        localLLMAutostart = try container.decodeIfPresent(Bool.self, forKey: .localLLMAutostart) ?? true
        localLLMServerPath = try container.decodeIfPresent(
            String.self,
            forKey: .localLLMServerPath
        ) ?? AppSettings.defaultLocalLLMServerPath
        localLLMModelPath = try container.decodeIfPresent(
            String.self,
            forKey: .localLLMModelPath
        ) ?? AppSettings.defaultLocalLLMModelPath
        corrections = try container.decodeIfPresent([TextCorrection].self, forKey: .corrections) ?? []
        appendTrailingSpace = try container.decodeIfPresent(Bool.self, forKey: .appendTrailingSpace) ?? true
        useModernTheme = try container.decodeIfPresent(Bool.self, forKey: .useModernTheme) ?? false
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

/// Eine lernende Korrektur-Regel: ersetzt `from` (z. B. "CloudCode") im finalen Text
/// durch `to` (z. B. "Claude Code"). Wird auf die Ausgabe aller Workflows angewendet.
struct TextCorrection: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

struct DampfAblassenSettings: Codable {
    var systemPrompt: String = "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib NUR die fertige Nachricht zurück."
    var customName: String = ""
}

struct EmojiTextSettings: Codable {
    var emojiDensity: EmojiDensity = .mittel
    var customName: String = ""

    enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
        case wenig
        case mittel
        case viel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wenig: return "Wenig"
            case .mittel: return "Mittel"
            case .viel: return "Viel"
            }
        }
    }
}

struct TextImprovementSettings: Codable {
    var systemPrompt: String = ""
    var customTerms: [String] = []
    var context: String = ""
    var tone: TextTone = .neutral
    var customName: String = ""

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }
}

struct TranslateSettings: Codable {
    var tone: TextImprovementSettings.TextTone = .neutral
    var customName: String = ""
}
