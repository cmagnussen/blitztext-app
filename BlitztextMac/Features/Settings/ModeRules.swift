import Foundation

// "Modus je App" and the settings that hang on an own mode. Foundation only, so the tests
// compile it; the settings view is `AppModeRulesSection`.

/// One rule: dictating with the Blitztext shortcut in this app uses `mode` instead.
struct AppModeRule: Codable, Hashable, Identifiable {
    var bundleID: String
    var appName: String
    var mode: WorkflowType

    var id: String { bundleID }
}

/// The same for a website in a browser, e.g. Gmail. `host` matches subdomains too.
struct WebsiteModeRule: Codable, Hashable, Identifiable {
    var host: String
    var mode: WorkflowType

    var id: String { host }
}

// A rule for an own mode reads as Blitztext in builds without own modes, which would otherwise
// drop all rules (`StoredMode`).
extension AppModeRule {
    private enum CodingKeys: String, CodingKey {
        case bundleID, appName, mode, customModeID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleID: try container.decode(String.self, forKey: .bundleID),
            appName: try container.decode(String.self, forKey: .appName),
            mode: try StoredMode.decode(from: container, mode: .mode, customID: .customModeID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(appName, forKey: .appName)
        try StoredMode.encode(mode, standIn: .tapTalk, into: &container, mode: .mode, customID: .customModeID)
    }
}

extension WebsiteModeRule {
    private enum CodingKeys: String, CodingKey {
        case host, mode, customModeID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            host: try container.decode(String.self, forKey: .host),
            mode: try StoredMode.decode(from: container, mode: .mode, customID: .customModeID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try StoredMode.encode(mode, standIn: .tapTalk, into: &container, mode: .mode, customID: .customModeID)
    }
}

/// What hangs on an own mode besides its definition: its own shortcut (keyed by the mode's
/// raw value) and the app and website rules that use it.
enum CustomModeLinks {
    /// Removes the mode and its shortcut; its app and website rules go back to Blitztext.
    static func delete(
        id: String,
        modes: inout [CustomMode],
        hotkeys: inout [String: KeyCombo],
        appRules: inout [AppModeRule],
        websiteRules: inout [WebsiteModeRule]
    ) {
        modes.removeAll { $0.id == id }
        hotkeys.removeValue(forKey: id)
        for index in appRules.indices where appRules[index].mode.customModeID == id {
            appRules[index].mode = .tapTalk
        }
        for index in websiteRules.indices where websiteRules[index].mode.customModeID == id {
            websiteRules[index].mode = .tapTalk
        }
    }

    /// Settings left behind by modes that no longer exist (e.g. after going back to an older
    /// version and forward again) are tidied the same way as on delete.
    static func removeOrphans(
        modes: [CustomMode],
        hotkeys: inout [String: KeyCombo],
        appRules: inout [AppModeRule],
        websiteRules: inout [WebsiteModeRule]
    ) {
        let known = Set(modes.map(\.id))
        for rawValue in hotkeys.keys where !exists(WorkflowType(rawValue: rawValue), known: known) {
            hotkeys.removeValue(forKey: rawValue)
        }
        for index in appRules.indices where !exists(appRules[index].mode, known: known) {
            appRules[index].mode = .tapTalk
        }
        for index in websiteRules.indices where !exists(websiteRules[index].mode, known: known) {
            websiteRules[index].mode = .tapTalk
        }
    }

    /// Own shortcuts of the modes that exist: built-in modes and the current own modes.
    static func resolvedHotkeys(_ hotkeys: [String: KeyCombo], modes: [CustomMode]) -> [WorkflowType: KeyCombo] {
        let known = Set(modes.map(\.id))
        var result: [WorkflowType: KeyCombo] = [:]
        for (rawValue, combo) in hotkeys {
            let type = WorkflowType(rawValue: rawValue)
            if exists(type, known: known) {
                result[type] = combo
            }
        }
        return result
    }

    private static func exists(_ type: WorkflowType, known: Set<String>) -> Bool {
        guard let id = type.customModeID else { return true }
        return known.contains(id)
    }
}
