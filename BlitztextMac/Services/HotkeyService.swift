import Cocoa
import Observation

struct HotkeyShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt16?
    let modifierRawValue: UInt
    let keyLabel: String?

    init(keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifierRawValue = Self.normalized(modifiers).rawValue
        self.keyLabel = keyLabel
    }

    var modifiers: NSEvent.ModifierFlags {
        Self.normalized(NSEvent.ModifierFlags(rawValue: modifierRawValue))
    }

    var displayLabel: String {
        var parts: [String] = []
        let flags = modifiers
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }
        if let keyLabel, !keyLabel.isEmpty { parts.append(keyLabel) }
        return parts.joined(separator: " + ")
    }

    var validationError: String? {
        if keyCode == 53 {
            return "Escape ist zum Abbrechen reserviert."
        }
        if keyCode == nil && modifiers.count < 2 {
            return "Nutze mindestens zwei Sondertasten."
        }
        if keyCode != nil && modifiers.isEmpty && !Self.isFunctionKey(keyCode) {
            return "Nutze mindestens eine Sondertaste."
        }
        return nil
    }

    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == keyCode && self.modifiers == Self.normalized(modifiers)
    }

    static func captured(from event: NSEvent) -> HotkeyShortcut {
        HotkeyShortcut(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            keyLabel: keyLabel(for: event)
        )
    }

    static func defaultShortcut(for type: WorkflowType) -> HotkeyShortcut {
        switch type {
        case .transcription:
            return HotkeyShortcut(modifiers: [.function, .shift])
        case .localTranscription:
            return HotkeyShortcut(modifiers: [.function, .shift, .control])
        case .textImprover:
            return HotkeyShortcut(modifiers: [.function, .control])
        case .dampfAblassen:
            return HotkeyShortcut(modifiers: [.function, .option])
        case .emojiText:
            return HotkeyShortcut(modifiers: [.function, .command])
        }
    }

    static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift, .function])
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if let specialKey = specialKeyLabels[event.keyCode] {
            return specialKey
        }

        let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let characters, !characters.isEmpty {
            return characters.uppercased()
        }
        return "Taste \(event.keyCode)"
    }

    private static func isFunctionKey(_ keyCode: UInt16?) -> Bool {
        guard let keyCode else { return false }
        return functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]

    private static let specialKeyLabels: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        119: "End",
        121: "Page Down",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20"
    ]
}

private extension NSEvent.ModifierFlags {
    var count: Int {
        [Self.command, .option, .control, .shift, .function]
            .reduce(0) { $0 + (contains($1) ? 1 : 0) }
    }
}

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case down(WorkflowType)
    case up(WorkflowType)
    case cancel
}

@Observable
@MainActor
final class HotkeyService {
    private static let modifierOnlyRecognitionDelay: Duration = .milliseconds(140)

    private var monitors: [Any] = []
    private var shortcuts: [WorkflowType: HotkeyShortcut] = [:]
    private var activeCombo: WorkflowType?
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var pendingModifierTask: Task<Void, Never>?
    private var suppressModifierShortcutsUntilRelease = false

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?
    var isSuspended = false {
        didSet {
            if isSuspended {
                pendingModifierTask?.cancel()
                pendingModifierTask = nil
                releaseActiveCombo()
            }
        }
    }

    func updateShortcuts(_ shortcuts: [WorkflowType: HotkeyShortcut]) {
        self.shortcuts = shortcuts
        pendingModifierTask?.cancel()
        releaseActiveCombo()
    }

    func start() {
        stop()

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in self?.handleKey(event) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event)
            return event
        } as Any)
    }

    func stop() {
        pendingModifierTask?.cancel()
        pendingModifierTask = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        activeCombo = nil
        currentModifiers = []
        suppressModifierShortcutsUntilRelease = false
    }

    private func handleFlags(_ event: NSEvent) {
        guard !isSuspended else { return }
        let flags = HotkeyShortcut.normalized(event.modifierFlags)
        currentModifiers = flags
        pendingModifierTask?.cancel()
        pendingModifierTask = nil

        if let activeCombo,
           let shortcut = shortcuts[activeCombo],
           shortcut.modifiers != flags {
            releaseActiveCombo()
            suppressModifierShortcutsUntilRelease = true
        }

        if flags.isEmpty {
            suppressModifierShortcutsUntilRelease = false
            return
        }
        guard !suppressModifierShortcutsUntilRelease else { return }
        guard activeCombo == nil else { return }
        guard let match = WorkflowType.allCases.first(where: {
            guard let shortcut = shortcuts[$0] else { return false }
            return shortcut.keyCode == nil && shortcut.modifiers == flags
        }) else {
            return
        }

        pendingModifierTask = Task { [weak self] in
            try? await Task.sleep(for: Self.modifierOnlyRecognitionDelay)
            guard !Task.isCancelled else { return }
            guard let self,
                  !self.isSuspended,
                  self.activeCombo == nil,
                  self.currentModifiers == self.shortcuts[match]?.modifiers else {
                return
            }
            self.activeCombo = match
            self.onHotkeyEvent?(.down(match))
            self.pendingModifierTask = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard !isSuspended else { return }
        pendingModifierTask?.cancel()
        pendingModifierTask = nil

        if event.type == .keyDown, event.keyCode == 53 {
            releaseActiveCombo()
            onHotkeyEvent?(.cancel)
            return
        }

        if event.type == .keyUp {
            guard let activeCombo,
                  shortcuts[activeCombo]?.keyCode == event.keyCode else {
                return
            }
            releaseActiveCombo()
            return
        }

        guard event.type == .keyDown, !event.isARepeat, activeCombo == nil else { return }
        guard let match = WorkflowType.allCases.first(where: {
            shortcuts[$0]?.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) == true
        }) else {
            return
        }

        activeCombo = match
        onHotkeyEvent?(.down(match))
    }

    private func releaseActiveCombo() {
        guard let activeCombo else { return }
        self.activeCombo = nil
        onHotkeyEvent?(.up(activeCombo))
    }
}
