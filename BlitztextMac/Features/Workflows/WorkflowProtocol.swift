import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case tapTalk
    case localTapTalk
    case textImprover
    case dampfAblassen
    case emojiText

    var id: String { rawValue }

    static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTapTalk }
    }

    var displayName: String {
        switch self {
        case .tapTalk: return "Blitztext"
        case .localTapTalk: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        }
    }

    var icon: String {
        switch self {
        case .tapTalk: return "mic.fill"
        case .localTapTalk: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        }
    }

    var subtitle: String {
        switch self {
        case .tapTalk: return "Sprache rein. Text raus."
        case .localTapTalk: return "Sprache rein. Text raus."
        case .textImprover: return "Gesprochen rein. Geschrieben raus."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        }
    }

    var hotkeyLabel: String {
        switch self {
        case .tapTalk: return "fn + Shift"
        case .localTapTalk: return "fn + Shift + Ctrl"
        case .textImprover: return "fn + Control"
        case .dampfAblassen: return "fn + Option"
        case .emojiText: return "fn + Cmd"
        }
    }

    var accentColor: String {
        switch self {
        case .tapTalk: return "blue"
        case .localTapTalk: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        }
    }
}

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

    func start()
    func stop()
    func reset()
}

extension Workflow {
    var transcript: String? { nil }
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
    }

    func customHotkey(for type: WorkflowType) -> KeyCombo? {
        customHotkeys[type.rawValue]
    }

    var resolvedCustomHotkeys: [WorkflowType: KeyCombo] {
        var result: [WorkflowType: KeyCombo] = [:]
        for (rawValue, combo) in customHotkeys {
            if let type = WorkflowType(rawValue: rawValue) {
                result[type] = combo
            }
        }
        return result
    }
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

