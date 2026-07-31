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
    case cancel              // Escape pressed
}

// MARK: - Hotkey Combo

enum HotkeyModifier: String, Codable, CaseIterable, Identifiable {
    case function
    case shift
    case control
    case option
    case command

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .function: return "fn"
        case .shift: return "Shift"
        case .control: return "Ctrl"
        case .option: return "Option"
        case .command: return "Cmd"
        }
    }

    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .function: return .function
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        case .command: return .command
        }
    }
}

struct HotkeyCombo: Codable, Equatable, Hashable {
    var modifiers: Set<HotkeyModifier>
    var keyCode: UInt16?
    var keyLabel: String?

    init(modifiers: Set<HotkeyModifier>, keyCode: UInt16? = nil, keyLabel: String? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.keyLabel = keyLabel
    }

    /// Ohne normale Taste mindestens zwei Sondertasten, sonst feuert der
    /// Hotkey beim normalen Tippen. Mit normaler Taste reicht eine Sondertaste.
    var isValid: Bool {
        if keyCode != nil {
            return !modifiers.isEmpty
        }
        return modifiers.count >= 2
    }

    var nsFlags: NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { $0.insert($1.nsFlag) }
    }

    var displayLabel: String {
        var parts = HotkeyModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.displayName)
        if let keyLabel {
            parts.append(keyLabel)
        }
        return parts.joined(separator: " + ")
    }

    static func defaultCombo(for type: WorkflowType) -> HotkeyCombo {
        switch type {
        case .transcription: return HotkeyCombo(modifiers: [.function, .shift])
        case .localTranscription: return HotkeyCombo(modifiers: [.function, .shift, .control])
        case .textImprover: return HotkeyCombo(modifiers: [.function, .control])
        case .dampfAblassen: return HotkeyCombo(modifiers: [.function, .option])
        case .emojiText: return HotkeyCombo(modifiers: [.function, .command])
        }
    }

    static var defaults: [WorkflowType: HotkeyCombo] {
        WorkflowType.allCases.reduce(into: [:]) { $0[$1] = defaultCombo(for: $1) }
    }
}

@Observable
@MainActor
final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var fallbackKeyDownMonitors: [Any] = []
    private var fallbackKeyUpMonitors: [Any] = []
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var eventTapRetryTimer: Timer?
    private var activeCombo: WorkflowType?  // Which combo is currently held
    private var activeKeyCode: UInt16?      // Set when the active combo includes a regular key

    /// false, solange der CGEventTap mangels Accessibility-Berechtigung nicht
    /// laeuft -- Kombos mit normaler Taste funktionieren dann nicht.
    private(set) var keyEventTapActive = false

    var combos: [WorkflowType: HotkeyCombo] = HotkeyCombo.defaults

    /// Waehrend der Hotkey-Aufnahme in den Einstellungen pausiert,
    /// damit die gedrueckten Tasten keinen Workflow starten.
    var isSuspended = false {
        didSet {
            if isSuspended {
                activeCombo = nil
                activeKeyCode = nil
            }
        }
    }

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

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
        // Escape key monitor for toggle mode
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                if event.keyCode == 53 { // Escape
                    self?.handleEscape()
                }
            }
        }
        startKeyEventTap()
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
        stopFallbackKeyMonitors()
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
        keyEventTapActive = false
    }

    // MARK: - Key Event Tap (fuer Kombos mit normaler Taste, z.B. fn + R)

    /// Ein CGEventTap schluckt die normale Taste beim Ausloesen, damit sie nicht
    /// zusaetzlich in das fokussierte Textfeld getippt wird. Ohne Accessibility-
    /// Berechtigung faellt der Service auf passive NSEvent-Monitore zurueck und
    /// versucht periodisch erneut, den Tap zu erstellen -- sonst blieben
    /// Tasten-Kombos nach spaeter erteilter Berechtigung bis zum Neustart tot.
    private func startKeyEventTap() {
        guard !createKeyEventTap() else { return }
        startFallbackKeyMonitors()
        eventTapRetryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.retryKeyEventTap()
            }
        }
    }

    private func retryKeyEventTap() {
        guard createKeyEventTap() else { return }
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
        stopFallbackKeyMonitors()
    }

    private func createKeyEventTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
            // Der Tap haengt am Main-RunLoop, der Callback laeuft also auf dem Main Thread.
            return MainActor.assumeIsolated {
                service.handleKeyTapEvent(type: type, event: cgEvent)
            }
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            keyEventTapActive = false
            return false
        }

        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        keyEventTapActive = true
        return true
    }

    private func startFallbackKeyMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            Task { @MainActor in
                _ = self?.handleKeyDown(keyCode: event.keyCode, modifiers: Self.modifierSet(from: event.modifierFlags))
            }
        }) {
            fallbackKeyDownMonitors.append(monitor)
        }
        fallbackKeyDownMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(keyCode: event.keyCode, modifiers: Self.modifierSet(from: event.modifierFlags)) ? nil : event
        } as Any)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            Task { @MainActor in
                _ = self?.handleKeyUp(keyCode: event.keyCode)
            }
        }) {
            fallbackKeyUpMonitors.append(monitor)
        }
        fallbackKeyUpMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyUp(keyCode: event.keyCode) ? nil : event
        } as Any)
    }

    private func stopFallbackKeyMonitors() {
        fallbackKeyDownMonitors.forEach { NSEvent.removeMonitor($0) }
        fallbackKeyUpMonitors.forEach { NSEvent.removeMonitor($0) }
        fallbackKeyDownMonitors = []
        fallbackKeyUpMonitors = []
    }

    private func handleKeyTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            guard !isSuspended else { return Unmanaged.passUnretained(event) }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let handled = handleKeyDown(keyCode: keyCode, modifiers: Self.modifierSet(from: event.flags))
            return handled ? nil : Unmanaged.passUnretained(event)
        case .keyUp:
            guard !isSuspended else { return Unmanaged.passUnretained(event) }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return handleKeyUp(keyCode: keyCode) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// true = Event gehoert zu einem Hotkey und soll geschluckt werden.
    private func handleKeyDown(keyCode: UInt16, modifiers: Set<HotkeyModifier>) -> Bool {
        guard !isSuspended else { return false }

        // Autorepeat waehrend gehaltener Kombo weiter schlucken
        if activeCombo != nil, activeKeyCode == keyCode {
            return true
        }

        for (type, combo) in combos {
            guard combo.isValid, combo.keyCode == keyCode, combo.modifiers == modifiers else { continue }
            if activeCombo == nil {
                activeCombo = type
                activeKeyCode = keyCode
                onHotkeyEvent?(.down(type))
            }
            return true
        }
        return false
    }

    private func handleKeyUp(keyCode: UInt16) -> Bool {
        guard !isSuspended else { return false }
        guard let combo = activeCombo, activeKeyCode == keyCode else { return false }
        activeCombo = nil
        activeKeyCode = nil
        onHotkeyEvent?(.up(combo))
        return true
    }

    static func modifierSet(from flags: NSEvent.ModifierFlags) -> Set<HotkeyModifier> {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        return Set(HotkeyModifier.allCases.filter { normalized.contains($0.nsFlag) })
    }

    static func modifierSet(from flags: CGEventFlags) -> Set<HotkeyModifier> {
        var result: Set<HotkeyModifier> = []
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    private func handleFlags(_ event: NSEvent) {
        guard !isSuspended else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Nur reine Modifier-Kombos matchen; Kombos mit normaler Taste laufen
        // ueber den Key-Event-Tap. Spezifischste Kombo zuerst pruefen, damit
        // z.B. fn+Shift+Ctrl nicht faelschlich als fn+Shift erkannt wird.
        let modifierOnlyCombos = combos
            .filter { $0.value.keyCode == nil }
            .sorted { $0.value.modifiers.count > $1.value.modifiers.count }
        for (type, combo) in modifierOnlyCombos where combo.isValid && flags == combo.nsFlags {
            if activeCombo == nil {
                activeCombo = type
                onHotkeyEvent?(.down(type))
            }
            return
        }

        // Keine passende Kombo mehr gedrueckt -- fire up event.
        // Beendet auch Tasten-Kombos, wenn zuerst die Sondertasten losgelassen werden.
        if let combo = activeCombo, flags.isEmpty || activeKeyCode == nil {
            activeCombo = nil
            activeKeyCode = nil
            onHotkeyEvent?(.up(combo))
        }
    }

    private func handleEscape() {
        activeCombo = nil
        activeKeyCode = nil
        onHotkeyEvent?(.cancel)
    }
}

// MARK: - Hotkey Combo Recorder

/// Nimmt in den Einstellungen eine neue Modifier-Kombination auf:
/// Sondertasten druecken und halten, beim Loslassen wird die Kombination uebernommen.
@Observable
@MainActor
final class HotkeyComboRecorder {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var accumulated: Set<HotkeyModifier> = []

    private(set) var isRecording = false
    private(set) var liveModifiers: Set<HotkeyModifier> = []

    var onFinish: ((HotkeyCombo?) -> Void)?

    func start() {
        guard !isRecording else { return }
        isRecording = true
        accumulated = []
        liveModifiers = []

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
            return nil
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func handleFlags(_ event: NSEvent) {
        let current = HotkeyService.modifierSet(from: event.modifierFlags)

        if current.isEmpty {
            // Alles losgelassen -- Aufnahme abschliessen
            if !accumulated.isEmpty {
                finish(with: HotkeyCombo(modifiers: accumulated))
            }
            return
        }

        accumulated.formUnion(current)
        liveModifiers = current
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancel()
            return
        }

        // Normale Taste beendet die Aufnahme sofort:
        // aktuell gehaltene Sondertasten + diese Taste ergeben die Kombination.
        let modifiers = HotkeyService.modifierSet(from: event.modifierFlags)
        finish(with: HotkeyCombo(
            modifiers: modifiers,
            keyCode: event.keyCode,
            keyLabel: Self.keyLabel(for: event)
        ))
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 123: return "\u{2190}"
        case 124: return "\u{2192}"
        case 125: return "\u{2193}"
        case 126: return "\u{2191}"
        default:
            let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            return characters.isEmpty ? "Taste \(event.keyCode)" : characters
        }
    }

    private func finish(with combo: HotkeyCombo?) {
        guard isRecording else { return }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        localMonitor = nil
        globalMonitor = nil
        keyMonitor = nil
        isRecording = false
        liveModifiers = []
        accumulated = []
        onFinish?(combo)
    }
}
