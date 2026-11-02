import Foundation

// MARK: - Workflow Types

/// A dictation mode: one of the built-in modes or an own mode (`CustomMode`).
///
/// Stored as its raw string, as when this was a plain String enum: settings, rules, shortcuts
/// and the history keep decoding. An own mode's raw value is its id ("custom-<UUID>", as on
/// iOS). Any other unknown string decodes as an own mode too, so a deleted or unknown mode
/// never breaks decoding; it shows as "Eigener Modus" and cannot run.
/// Foundation only, so the tests compile it.
enum WorkflowType: Hashable, Identifiable, Codable, RawRepresentable {
    case tapTalk
    case localTapTalk
    case textImprover
    case dampfAblassen
    case emojiText
    /// An own mode, by the id of its `CustomMode`.
    case custom(String)

    /// The built-in modes, in the order of their fixed hotkey ids.
    static let builtIn: [WorkflowType] = [.tapTalk, .localTapTalk, .textImprover, .dampfAblassen, .emojiText]

    /// Built-in modes shown in the menu; own modes follow them (`AppState.menuModes`).
    static let builtInMenuCases: [WorkflowType] = [.tapTalk, .textImprover, .dampfAblassen, .emojiText]

    init(rawValue: String) {
        switch rawValue {
        case "tapTalk": self = .tapTalk
        case "localTapTalk": self = .localTapTalk
        case "textImprover": self = .textImprover
        case "dampfAblassen": self = .dampfAblassen
        case "emojiText": self = .emojiText
        default: self = .custom(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .tapTalk: return "tapTalk"
        case .localTapTalk: return "localTapTalk"
        case .textImprover: return "textImprover"
        case .dampfAblassen: return "dampfAblassen"
        case .emojiText: return "emojiText"
        case .custom(let id): return id
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    var isBuiltIn: Bool { customModeID == nil }

    var customModeID: String? {
        if case .custom(let id) = self { return id }
        return nil
    }

    /// The definition behind an own mode; nil for built-in modes and modes that no longer exist.
    var customMode: CustomMode? {
        customModeID.flatMap(CustomModeCatalog.mode(id:))
    }

    var displayName: String {
        switch self {
        case .tapTalk: return "Blitztext"
        case .localTapTalk: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        case .custom: return Self.customName(customMode)
        }
    }

    /// The name of an own mode; an empty name or a deleted mode shows as "Eigener Modus".
    static func customName(_ mode: CustomMode?) -> String {
        let name = mode?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Eigener Modus" : name
    }

    var icon: String {
        switch self {
        case .tapTalk: return "mic.fill"
        case .localTapTalk: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        case .custom: return customMode?.icon ?? "wand.and.stars"
        }
    }

    var subtitle: String {
        switch self {
        case .tapTalk: return "Sprache rein. Text raus."
        case .localTapTalk: return "Sprache rein. Text raus."
        case .textImprover: return "Gesprochen rein. Geschrieben raus."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        case .custom: return "Dein Format, dein Prompt."
        }
    }

    /// The built-in fn shortcut; empty for own modes, which only have a recorded shortcut.
    var hotkeyLabel: String {
        switch self {
        case .tapTalk: return "fn + Shift"
        case .localTapTalk: return "fn + Shift + Ctrl"
        case .textImprover: return "fn + Control"
        case .dampfAblassen: return "fn + Option"
        case .emojiText: return "fn + Cmd"
        case .custom: return ""
        }
    }

    var accentColor: String {
        switch self {
        case .tapTalk: return "blue"
        case .localTapTalk: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        case .custom: return "purple"
        }
    }
}

// MARK: - Own modes as the app knows them

/// The user's own modes right now, so names, symbols and colours of `WorkflowType.custom`
/// can be looked up anywhere (menu bar icon, recording pill, history). `AppState` keeps it in
/// step with the settings; views that edit modes read the settings themselves.
enum CustomModeCatalog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [CustomMode] = []

    static var modes: [CustomMode] {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    static func mode(id: String) -> CustomMode? {
        modes.first { $0.id == id }
    }
}

/// How a mode is stored where builds without own modes read it too: the history and the app
/// and website rules. Those builds know only the built-in modes and drop a whole list when one
/// value is unknown (the history file is then deleted on the next save). So an own mode is
/// stored as a built-in stand-in, plus its id in a field older builds ignore.
enum StoredMode {
    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, mode: Key, customID: Key
    ) throws -> WorkflowType {
        if let id = try container.decodeIfPresent(String.self, forKey: customID) {
            return .custom(id)
        }
        // Builds before this one stored an own mode's id right in the mode field.
        return WorkflowType(rawValue: try container.decode(String.self, forKey: mode))
    }

    static func encode<Key: CodingKey>(
        _ type: WorkflowType, standIn: WorkflowType,
        into container: inout KeyedEncodingContainer<Key>, mode: Key, customID: Key
    ) throws {
        try container.encode(type.isBuiltIn ? type : standIn, forKey: mode)
        try container.encodeIfPresent(type.customModeID, forKey: customID)
    }
}
