import Foundation

// MARK: - Workflow State

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
    /// Input level 0...1 while recording, for the waveforms.
    var audioLevel: Float { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }
    /// What was said, word for word, before an AI mode rewrote it; nil for plain dictation.
    var transcript: String? { get }
    /// An AI mode failed on a finished transcript: the word-for-word text to keep.
    var onKeptTranscript: WorkflowOutputHandler? { get set }

    func start()
    func stop()
    func reset()
}

extension Workflow {
    var transcript: String? { nil }
    /// Plain dictation has no AI step that could fail.
    var onKeptTranscript: WorkflowOutputHandler? {
        get { nil }
        set {}
    }
}

// MARK: - App Settings

struct AppSettings: Codable {
    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    /// Where Blitztext+, $%&! and :) run their AI step. Transcription is always local.
    var rewriteEngine: TextRewriter.Engine = .automatic
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.initialModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    /// The one-time switch from Whisper Small to Parakeet Ultra for Macs without a model ran.
    var hasCheckedParakeetDefault: Bool = false
    /// Macs that already had a model when the setup assistant arrived were marked as set up.
    var hasMigratedToSetupAssistant: Bool = false
    /// Optional shortcuts per workflow (keyed by `WorkflowType.rawValue`) for non-Apple keyboards.
    /// The only shortcut an own mode can have.
    var customHotkeys: [String: KeyCombo] = [:]
    var restoreClipboardAfterPaste: Bool = true
    var correctCustomTermsEnabled: Bool = true
    var removeFillerWordsEnabled: Bool = true
    var historyRetention: HistoryRetention = .day
    /// `WhatsNew.version` the user already confirmed; nil before the first note.
    var lastSeenWhatsNewVersion: String?
    /// "Modus je App": the Blitztext shortcut uses another mode in these apps.
    var appModeRules: [AppModeRule] = []
    /// The same for websites in a browser, e.g. Gmail. Wins over a rule for the browser.
    var websiteModeRules: [WebsiteModeRule] = []
    /// Spaces and capitals of a dictation follow the text around the cursor.
    var fitToSurroundingText: Bool = true
    /// The AI modes get the text around the cursor as context (like the iOS keyboard).
    var aiSeesFieldContext: Bool = false
    /// The Mac's sound output is muted while Blitztext records.
    var muteOutputWhileRecording: Bool = true
    /// Long word-for-word dictation gets paragraph breaks at sentence ends.
    var automaticParagraphs: Bool = false
    /// A small lilac pill at the bottom of the screen while recording and processing.
    var showsRecordingIndicator: Bool = true
    /// Write the summary right after a meeting. Off: transcript by person only, faster;
    /// the summary can still be created later.
    var summarizesMeetings: Bool = true
    /// The user's own modes ("Eigene Modi"), in menu order.
    var customModes: [CustomMode] = []
    /// E-Mail and Stichpunkte were added once, as on iOS; deleting them later sticks.
    var hasSeededCustomModes: Bool = false
    /// German as in Germany and Austria, or as in Switzerland and Liechtenstein.
    var germanVariant: GermanVariant = .automatic

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.initialModelName,
        hasAutoSelectedFastLocalModel: Bool = false
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case rewriteEngine
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case hasCheckedParakeetDefault
        case hasMigratedToSetupAssistant
        case customHotkeys
        case restoreClipboardAfterPaste
        case correctCustomTermsEnabled
        case removeFillerWordsEnabled
        case historyRetention
        case lastSeenWhatsNewVersion
        case appModeRules
        case websiteModeRules
        case fitToSurroundingText
        case aiSeesFieldContext
        case muteOutputWhileRecording
        case automaticParagraphs
        case showsRecordingIndicator
        case summarizesMeetings
        case customModes
        case hasSeededCustomModes
        case germanVariant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        rewriteEngine = try container.decodeIfPresent(TextRewriter.Engine.self, forKey: .rewriteEngine) ?? .automatic
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.initialModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        hasCheckedParakeetDefault = try container.decodeIfPresent(Bool.self, forKey: .hasCheckedParakeetDefault) ?? false
        hasMigratedToSetupAssistant = try container.decodeIfPresent(Bool.self, forKey: .hasMigratedToSetupAssistant) ?? false
        customHotkeys = (try? container.decodeIfPresent([String: KeyCombo].self, forKey: .customHotkeys)) ?? [:]
        restoreClipboardAfterPaste = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboardAfterPaste) ?? true
        correctCustomTermsEnabled = try container.decodeIfPresent(Bool.self, forKey: .correctCustomTermsEnabled) ?? true
        removeFillerWordsEnabled = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWordsEnabled) ?? true
        historyRetention = (try? container.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention)) ?? .day
        lastSeenWhatsNewVersion = try container.decodeIfPresent(String.self, forKey: .lastSeenWhatsNewVersion)
        appModeRules = (try? container.decodeIfPresent([AppModeRule].self, forKey: .appModeRules)) ?? []
        websiteModeRules = (try? container.decodeIfPresent([WebsiteModeRule].self, forKey: .websiteModeRules)) ?? []
        fitToSurroundingText = try container.decodeIfPresent(Bool.self, forKey: .fitToSurroundingText) ?? true
        aiSeesFieldContext = try container.decodeIfPresent(Bool.self, forKey: .aiSeesFieldContext) ?? false
        muteOutputWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .muteOutputWhileRecording) ?? true
        automaticParagraphs = try container.decodeIfPresent(Bool.self, forKey: .automaticParagraphs) ?? false
        showsRecordingIndicator = try container.decodeIfPresent(Bool.self, forKey: .showsRecordingIndicator) ?? true
        summarizesMeetings = try container.decodeIfPresent(Bool.self, forKey: .summarizesMeetings) ?? true
        customModes = (try? container.decodeIfPresent([CustomMode].self, forKey: .customModes)) ?? []
        hasSeededCustomModes = try container.decodeIfPresent(Bool.self, forKey: .hasSeededCustomModes) ?? false
        germanVariant = (try? container.decodeIfPresent(GermanVariant.self, forKey: .germanVariant)) ?? .automatic
    }

    func customHotkey(for type: WorkflowType) -> KeyCombo? {
        customHotkeys[type.rawValue]
    }

    /// Own shortcuts of the modes that exist; a deleted own mode's leftovers do not register.
    var resolvedCustomHotkeys: [WorkflowType: KeyCombo] {
        CustomModeLinks.resolvedHotkeys(customHotkeys, modes: customModes)
    }

    func customMode(id: String) -> CustomMode? {
        customModes.first { $0.id == id }
    }

    /// Removes an own mode with its shortcut; its app and website rules go back to Blitztext.
    mutating func deleteCustomMode(id: String) {
        var modes = customModes
        var hotkeys = customHotkeys
        var appRules = appModeRules
        var websiteRules = websiteModeRules
        CustomModeLinks.delete(id: id, modes: &modes, hotkeys: &hotkeys, appRules: &appRules, websiteRules: &websiteRules)
        customModes = modes
        customHotkeys = hotkeys
        appModeRules = appRules
        websiteModeRules = websiteRules
    }

    /// Tidies shortcuts and rules of own modes that no longer exist.
    mutating func removeCustomModeOrphans() {
        var hotkeys = customHotkeys
        var appRules = appModeRules
        var websiteRules = websiteModeRules
        CustomModeLinks.removeOrphans(modes: customModes, hotkeys: &hotkeys, appRules: &appRules, websiteRules: &websiteRules)
        customHotkeys = hotkeys
        appModeRules = appRules
        websiteModeRules = websiteRules
    }
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    /// What the user dictates: a language code that Parakeet gets as a hint, or
    /// `automaticLanguage`. "de" stays the default: most dictations are German, and on very
    /// short or quiet German recordings the hint keeps Parakeet from switching languages.
    var language: String = "de"

    /// No hint: Parakeet detects the language of each dictation. For people who dictate in
    /// several languages; an English dictation is then not pulled towards German.
    static let automaticLanguage = TranscriptPostProcessor.automaticLanguage

    /// The choices offered in the settings. Parakeet Ultra covers 25 European languages;
    /// the list names the common ones, the automatic option covers the rest.
    static let languageOptions: [(code: String, label: String)] = [
        ("de", "Deutsch"),
        ("en", "Englisch"),
        ("fr", "Französisch"),
        ("es", "Spanisch"),
        ("it", "Italienisch"),
        ("nl", "Niederländisch"),
        (automaticLanguage, "Automatisch erkennen"),
    ]

    var usesAutomaticLanguage: Bool { language == Self.automaticLanguage }
}

