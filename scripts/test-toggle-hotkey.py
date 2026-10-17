#!/usr/bin/env python3
"""Execute the actual upstream hotkey handler against fake workflow state."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
source = (root / 'BlitztextMac/App/BlitztextMacApp.swift').read_text()
start = source.index('    private func handleHotkeyDown(')
end = source.index('    private func handleHotkeyUp(', start)
up_end = source.index('    @objc private func togglePopover(', end)
handler = source[start:up_end].replace('private func', 'func')
protocol = (root / 'BlitztextMac/Features/Workflows/WorkflowProtocol.swift').read_text()
phase_start = protocol.index('enum WorkflowPhase:')
phase_end = protocol.index('enum WorkflowLaunchSource:', phase_start)
phase = protocol[phase_start:phase_end]
fixture = r'''
import Foundation
__PHASE__
enum WorkflowType { case original, other }
enum HotkeyMode { case hold, toggle }
enum Source { case manual, hotkeyBackground }
enum Page { case main, whatsNew }
final class Workflow {
    let type = WorkflowType.original
    var phase = WorkflowPhase.running("Recording")
    var isRecording = true
    var stops = 0
    func stop() { stops += 1; isRecording = false }
}
final class Settings { var hotkeyMode = HotkeyMode.toggle }
final class State {
    let appSettings = Settings()
    var activeWorkflow: Workflow?
    var available = true
    var starts = 0
    var presentations = 0
    var page = Page.main
    func isWorkflowAvailable(_ type: WorkflowType) -> Bool { available }
    func prepareForPopoverPresentation() { presentations += 1 }
    func startWorkflow(_ type: WorkflowType, source: Source) { starts += 1 }
}
final class Popover { var isShown = false }
final class Harness {
    let appState = State()
    let popover = Popover()
    var shown = 0
    func showPopover() { shown += 1 }
__HANDLER__
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { print("FAIL: \(message)"); exit(1) }
}
for requested in [WorkflowType.original, .other] {
    let h = Harness()
    let w = Workflow()
    h.appState.activeWorkflow = w
    h.handleHotkeyDown(requested)
    check(w.stops == 1 && h.appState.starts == 0, "Finish original recording")
    check(h.appState.presentations == 0 && h.shown == 0, "Preserve output target")
    h.handleHotkeyDown(requested)
    check(w.stops == 1 && h.appState.starts == 0, "Preserve pending processing")
    w.phase = .done("Transcript")
    h.handleHotkeyDown(requested)
    check(h.appState.starts == 1 && h.shown == 1, "Allow start after completion")
}
// Use the real production phase enum: done/error are active for presentation,
// but must never block a fresh recording, for either shortcut.
for phase in [WorkflowPhase.done("Transcript"), .error("Microphone unavailable")] {
    for requested in [WorkflowType.original, .other] {
        let h = Harness()
        let w = Workflow()
        w.isRecording = false
        w.phase = phase
        h.appState.activeWorkflow = w
        check(w.phase.isActive, "Terminal states remain active for presentation")
        h.handleHotkeyDown(requested)
        check(h.appState.starts == 1 && h.shown == 1 && w.stops == 0,
              "Allow fresh start after done/error")
    }
}
let missing = Harness()
let original = Workflow()
missing.appState.activeWorkflow = original
missing.appState.available = false
missing.handleHotkeyDown(.other)
check(original.stops == 1 && missing.shown == 0, "Finish even if other mode unavailable")
let hold = Harness()
hold.appState.appSettings.hotkeyMode = .hold
hold.appState.activeWorkflow = Workflow()
hold.handleHotkeyDown(.other)
check(hold.appState.starts == 1 && hold.appState.activeWorkflow!.stops == 0,
      "Keep existing hold-mode routing")
let unavailable = Harness()
unavailable.appState.available = false
unavailable.handleHotkeyDown(.other)
check(unavailable.shown == 1 && unavailable.appState.starts == 0,
      "Keep missing-setup presentation when idle")

// Enumerate all normal toggle states with both shortcut choices, model availability,
// and popover visibility. Keep presentation behavior unchanged outside running work.
let states: [(WorkflowPhase?, Bool)] = [
    (nil, false), (.idle, false), (.running("Recording"), true),
    (.running("Processing"), false), (.done("Text"), false), (.error("Failure"), false)
]
for (phase, recording) in states {
    for requested in [WorkflowType.original, .other] {
        for available in [false, true] {
            for visible in [false, true] {
                let h = Harness()
                let w = Workflow()
                if let phase {
                    w.phase = phase
                    w.isRecording = recording
                    h.appState.activeWorkflow = w
                }
                h.appState.available = available
                h.popover.isShown = visible
                let running: Bool
                if case .running? = phase { running = true } else { running = false }
                h.handleHotkeyDown(requested)
                check(w.stops == (running && recording ? 1 : 0), "Only finish active recording")
                check(h.appState.starts == (!running && available ? 1 : 0), "Start only when ready")
                let shouldPresent = !running && (available || !visible)
                check(h.shown == (shouldPresent ? 1 : 0), "Preserve popover routing")
                let stopsBeforeRelease = w.stops
                h.handleHotkeyUp(requested)
                check(w.stops == stopsBeforeRelease, "Toggle key release never stops processing")
            }
        }
    }
}
// Repeated presses after the recording ends must never invoke stop again.
let repeated = Harness()
let pending = Workflow()
repeated.appState.activeWorkflow = pending
repeated.handleHotkeyDown(.other)
for index in 0..<100 {
    repeated.handleHotkeyDown(index.isMultiple(of: 2) ? .original : .other)
}
check(pending.stops == 1 && repeated.appState.starts == 0, "Preserve processing through repeated presses")

print("PASS: \(checks) hotkey checks, including done/error for both shortcuts")
'''
with tempfile.TemporaryDirectory(prefix='blitztext-pr-hotkey-') as directory:
    tmp = Path(directory)
    swift = tmp / 'main.swift'
    swift.write_text(fixture.replace('__HANDLER__', handler).replace('__PHASE__', phase))
    executable = tmp / 'check'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(tmp / 'cache'),
                    str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
