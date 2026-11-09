import Cocoa
import Observation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

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
    case down(WorkflowType)  // Keys pressed
    case up(WorkflowType)    // Keys released (for hold mode)
    case escape              // Stops a running recording, in both modes
}

@Observable
@MainActor
final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var activeCombo: WorkflowType?  // Which fn combo is currently held
    private var activeCustomCombo: WorkflowType?  // Which custom shortcut is currently held
    private let carbonRegistrar = CarbonHotkeyRegistrar()
    private var customHotkeys: [WorkflowType: KeyCombo] = [:]
    private var customHotkeysSuspended = false
    /// Carbon ids per mode, stable while Blitztext runs (`HotkeyIDs`).
    private var hotkeyIDs = HotkeyIDs()

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?
    /// Whether a dictation is recording or being processed. Only then does Escape get taken
    /// from the frontmost app.
    var isWorkflowRunning: (() -> Bool)?
    /// Escape ended a dictation while its keys were still held: ignore the keys until fn is
    /// let go, so releasing one of three keys does not start a new dictation.
    private var ignoresHeldKeys = false
    /// Workflows whose custom shortcut macOS refused to register (e.g. already taken).
    private(set) var failedCustomHotkeys: Set<WorkflowType> = []

    init() {
        carbonRegistrar.onEvent = { [weak self] id, pressed in
            Task { @MainActor in
                self?.handleCustomHotkey(id: id, pressed: pressed)
            }
        }
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
            return event
        }
        // Escape stops a recording: in other apps through the global monitor, which runs only
        // while a dictation is active (see `setDictationActive`), and while the popover makes
        // Blitztext frontmost (Drücken mode) through the local one.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, self.isWorkflowRunning?() == true else { return false }
                self.handleEscape()
                return true
            }
            return handled ? nil : event
        }
    }

    /// Installs the global Escape monitor while a dictation records or is processed, and
    /// removes it afterwards. Outside a dictation the app then receives no key events from
    /// other apps at all; only fn/modifier changes and the registered shortcuts reach it.
    func setDictationActive(_ active: Bool) {
        if active {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in
                    if event.keyCode == 53 { // Escape
                        self?.handleEscape()
                    }
                }
            }
        } else if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
        localKeyMonitor = nil
        carbonRegistrar.unregisterAll()
    }

    // MARK: - Custom Shortcuts

    func updateCustomHotkeys(_ hotkeys: [WorkflowType: KeyCombo]) {
        customHotkeys = hotkeys
        registerCustomHotkeys()
    }

    /// Temporarily disables all shortcuts (own and fn), e.g. while the user records a new one.
    func setCustomHotkeysSuspended(_ suspended: Bool) {
        guard customHotkeysSuspended != suspended else { return }
        customHotkeysSuspended = suspended
        registerCustomHotkeys()
    }

    private func registerCustomHotkeys() {
        carbonRegistrar.unregisterAll()
        failedCustomHotkeys = []
        guard !customHotkeysSuspended else { return }

        for (type, combo) in customHotkeys {
            if !carbonRegistrar.register(id: hotkeyIDs.id(for: type), combo: combo) {
                failedCustomHotkeys.insert(type)
            }
        }
    }

    private func handleCustomHotkey(id: UInt32, pressed: Bool) {
        guard let type = hotkeyIDs.type(for: id), customHotkeys[type] != nil || activeCustomCombo == type else { return }

        if pressed {
            // A missed key-up (e.g. while a password field had secure input) can leave an
            // fn combo marked as held and would block every shortcut. fn is not down, so
            // that combo is over.
            if let stale = activeCombo, !NSEvent.modifierFlags.contains(.function) {
                activeCombo = nil
                onHotkeyEvent?(.up(stale))
            }
            guard activeCustomCombo == nil, activeCombo == nil else { return }
            activeCustomCombo = type
            onHotkeyEvent?(.down(type))
        } else if activeCustomCombo == type {
            activeCustomCombo = nil
            onHotkeyEvent?(.up(type))
        }
    }

    /// The built-in fn shortcuts. A mode with its own working shortcut does not
    /// listen to its fn combo any more: the own shortcut replaces it.
    private static let fnCombos: [(flags: NSEvent.ModifierFlags, type: WorkflowType)] = [
        ([.function, .shift, .control], .localTapTalk),
        ([.function, .shift], .tapTalk),
        ([.function, .control], .textImprover),
        ([.function, .option], .dampfAblassen),
        ([.function, .command], .emojiText),
    ]

    private func isReplacedByCustomShortcut(_ type: WorkflowType) -> Bool {
        customHotkeys[type] != nil && !failedCustomHotkeys.contains(type)
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = ShortcutModifiers.normalized(event.modifierFlags)
        if ignoresHeldKeys {
            guard !flags.contains(.function) else { return }
            ignoresHeldKeys = false
        }

        if let match = Self.fnCombos.first(where: { $0.flags == flags }) {
            if activeCombo == nil, !customHotkeysSuspended, !isReplacedByCustomShortcut(match.type) {
                activeCombo = match.type
                onHotkeyEvent?(.down(match.type))
            }
            return
        }

        // Keys released -- fire up event
        if let combo = activeCombo {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
    }

    private func handleEscape() {
        // Releasing the keys after Escape must neither stop again nor start anew.
        ignoresHeldKeys = activeCombo != nil
        activeCustomCombo = nil
        activeCombo = nil
        onHotkeyEvent?(.escape)
    }

    nonisolated deinit {}
}
