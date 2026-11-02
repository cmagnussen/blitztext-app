import Foundation

/// Carbon hotkey ids for the own shortcuts. Built-in modes keep the ids they always had; an
/// own mode gets the next free id the first time it registers and keeps it while Blitztext
/// runs. Ids are never handed out twice, so adding or deleting a mode never moves another
/// mode's shortcut to a different id, not even for a key release still on its way.
/// Foundation only, so the tests compile it.
struct HotkeyIDs {
    private static let builtIn: [WorkflowType: UInt32] = [
        .tapTalk: 1, .localTapTalk: 2, .textImprover: 3, .dampfAblassen: 4, .emojiText: 5,
    ]
    static let firstCustomID: UInt32 = 100

    private var custom: [String: UInt32] = [:]
    private var nextCustomID = Self.firstCustomID

    /// The id for `type`, handing out a new one for an own mode seen for the first time.
    mutating func id(for type: WorkflowType) -> UInt32 {
        guard let modeID = type.customModeID else { return Self.builtIn[type] ?? 0 }
        if let id = custom[modeID] { return id }
        let id = nextCustomID
        nextCustomID += 1
        custom[modeID] = id
        return id
    }

    /// The mode an incoming hotkey event belongs to.
    func type(for id: UInt32) -> WorkflowType? {
        if let builtIn = Self.builtIn.first(where: { $0.value == id }) { return builtIn.key }
        return custom.first { $0.value == id }.map { WorkflowType.custom($0.key) }
    }
}
