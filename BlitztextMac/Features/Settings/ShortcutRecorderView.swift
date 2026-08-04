import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: HotkeyShortcut
    let onCapture: (HotkeyShortcut) -> Bool
    let onRecordingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.coordinator = context.coordinator
        button.update(shortcut: shortcut)
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.update(shortcut: shortcut)
    }

    final class Coordinator {
        var parent: ShortcutRecorderView

        init(parent: ShortcutRecorderView) {
            self.parent = parent
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    weak var coordinator: ShortcutRecorderView.Coordinator?

    private var isRecordingShortcut = false
    private var displayedShortcut: HotkeyShortcut?
    private var capturedModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        controlSize = .small
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        focusRingType = .exterior
        toolTip = "Klicken und gewünschtes Tastenkürzel drücken"
        setAccessibilityLabel("Tastenkürzel aufnehmen")
    }

    func update(shortcut: HotkeyShortcut) {
        displayedShortcut = shortcut
        guard !isRecordingShortcut else { return }
        title = shortcut.displayLabel
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        handleKeyEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecordingShortcut, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handleKeyEvent(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = HotkeyShortcut.normalized(event.modifierFlags)
        capturedModifiers.formUnion(modifiers)
        title = modifiers.isEmpty ? "Loslassen …" : modifierPreview(modifiers)

        if modifiers.isEmpty, !capturedModifiers.isEmpty {
            finishRecording(
                with: HotkeyShortcut(modifiers: capturedModifiers)
            )
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecordingShortcut {
            cancelRecording()
        }
        return result
    }

    private func beginRecording() {
        capturedModifiers = []
        isRecordingShortcut = true
        state = .on
        title = "Tastenkürzel drücken …"
        window?.makeFirstResponder(self)
        coordinator?.parent.onRecordingChanged(true)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        let shortcut = HotkeyShortcut.captured(from: event)
        finishRecording(with: shortcut)
    }

    private func finishRecording(with shortcut: HotkeyShortcut) {
        let accepted = coordinator?.parent.onCapture(shortcut) ?? false

        isRecordingShortcut = false
        state = .off
        title = accepted ? shortcut.displayLabel : (displayedShortcut?.displayLabel ?? "Nicht belegt")
        coordinator?.parent.onRecordingChanged(false)
        window?.makeFirstResponder(nil)
    }

    private func cancelRecording() {
        isRecordingShortcut = false
        state = .off
        title = displayedShortcut?.displayLabel ?? "Nicht belegt"
        coordinator?.parent.onRecordingChanged(false)
    }

    private func modifierPreview(_ modifiers: NSEvent.ModifierFlags) -> String {
        HotkeyShortcut(modifiers: modifiers).displayLabel
    }
}
