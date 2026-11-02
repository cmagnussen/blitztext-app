import AppKit
import XCTest

final class CustomModeTests: XCTestCase {
    override func tearDown() {
        CustomModeCatalog.modes = []
        super.tearDown()
    }

    private let ctrlOptionD = KeyCombo(
        keyCode: 2,
        modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "D"
    )
    private let f13 = KeyCombo(keyCode: 105, modifierFlags: 0, keyLabel: "F13")

    // MARK: - Built-in modes

    func testBuiltInRawValuesStayTheSame() throws {
        let expected: [(WorkflowType, String)] = [
            (.tapTalk, "tapTalk"),
            (.localTapTalk, "localTapTalk"),
            (.textImprover, "textImprover"),
            (.dampfAblassen, "dampfAblassen"),
            (.emojiText, "emojiText"),
        ]
        for (type, raw) in expected {
            XCTAssertEqual(type.rawValue, raw)
            XCTAssertEqual(WorkflowType(rawValue: raw), type)
            XCTAssertTrue(type.isBuiltIn)
            let json = try JSONEncoder().encode(type)
            XCTAssertEqual(String(data: json, encoding: .utf8), "\"\(raw)\"")
        }
        XCTAssertEqual(WorkflowType.builtIn.map(\.rawValue), expected.map(\.1))
    }

    // MARK: - Settings written before own modes existed

    /// The relevant part of settings.json as Blitztext 1.15 wrote it.
    private let oldSettingsJSON = """
    {
      "app": {
        "hotkeyMode": "toggle",
        "customHotkeys": {
          "textImprover": { "keyCode": 2, "modifierFlags": 786432, "keyLabel": "D" },
          "tapTalk": { "keyCode": 105, "modifierFlags": 0, "keyLabel": "F13" }
        },
        "appModeRules": [
          { "bundleID": "com.apple.mail", "appName": "Mail", "mode": "textImprover" },
          { "bundleID": "com.tinyspeck.slackmacgap", "appName": "Slack", "mode": "emojiText" }
        ],
        "websiteModeRules": [
          { "host": "mail.google.com", "mode": "dampfAblassen" }
        ]
      },
      "transcription": { "language": "de" }
    }
    """

    private struct StoredSettings: Decodable {
        struct App: Decodable {
            var customHotkeys: [String: KeyCombo]
            var appModeRules: [AppModeRule]
            var websiteModeRules: [WebsiteModeRule]
            var customModes: [CustomMode]?
        }
        var app: App
    }

    func testOldSettingsKeepTheirRulesAndShortcuts() throws {
        let settings = try JSONDecoder().decode(StoredSettings.self, from: Data(oldSettingsJSON.utf8)).app

        XCTAssertNil(settings.customModes)
        XCTAssertEqual(settings.appModeRules.map(\.mode), [.textImprover, .emojiText])
        XCTAssertEqual(settings.websiteModeRules.map(\.mode), [.dampfAblassen])
        XCTAssertEqual(settings.customHotkeys["textImprover"], ctrlOptionD)

        let resolved = CustomModeLinks.resolvedHotkeys(settings.customHotkeys, modes: [])
        XCTAssertEqual(resolved, [.textImprover: ctrlOptionD, .tapTalk: f13])

        // Nothing to tidy: every mode in the old file is a built-in one.
        var hotkeys = settings.customHotkeys
        var appRules = settings.appModeRules
        var websiteRules = settings.websiteModeRules
        CustomModeLinks.removeOrphans(modes: [], hotkeys: &hotkeys, appRules: &appRules, websiteRules: &websiteRules)
        XCTAssertEqual(hotkeys, settings.customHotkeys)
        XCTAssertEqual(appRules, settings.appModeRules)
        XCTAssertEqual(websiteRules, settings.websiteModeRules)
    }

    func testOldHistoryEntriesKeepTheirMode() throws {
        let json = """
        [
          { "id": "6F1A2B3C-0000-4000-8000-000000000001", "createdAt": 800000000, "workflow": "textImprover", "text": "Hallo" },
          { "id": "6F1A2B3C-0000-4000-8000-000000000002", "createdAt": 800000100, "workflow": "custom-6F1A", "text": "Liebe Jana" }
        ]
        """
        let entries = try JSONDecoder().decode([TranscriptHistoryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.map(\.workflow), [.textImprover, .custom("custom-6F1A")])
    }

    // MARK: - Going back to a build without own modes

    /// What 1.15 and older decode: the five built-in modes only, one unknown value fails a list.
    private enum OldMode: String, Codable { case tapTalk, localTapTalk, textImprover, dampfAblassen, emojiText }
    private struct OldEntry: Decodable { let workflow: OldMode; let text: String }
    private struct OldAppRule: Decodable { let bundleID: String; let mode: OldMode }
    private struct OldWebsiteRule: Decodable { let host: String; let mode: OldMode }

    /// Before, one own-mode entry made an older build drop the whole history and delete the
    /// file on its next save.
    func testOwnModeEntriesStayReadableForOlderBuilds() throws {
        let entries = [
            TranscriptHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 800_000_000), workflow: .tapTalk, text: "Hallo"),
            TranscriptHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 800_000_100), workflow: .custom("custom-6F1A"), text: "Liebe Jana"),
        ]
        let data = try JSONEncoder().encode(entries)

        let old = try JSONDecoder().decode([OldEntry].self, from: data)
        XCTAssertEqual(old.map(\.workflow), [.tapTalk, .textImprover])

        let again = try JSONDecoder().decode([TranscriptHistoryEntry].self, from: data)
        XCTAssertEqual(again, entries)
    }

    /// Before, one rule for an own mode made an older build drop all rules.
    func testOwnModeRulesStayReadableForOlderBuilds() throws {
        let appRules = [
            AppModeRule(bundleID: "com.apple.mail", appName: "Mail", mode: .textImprover),
            AppModeRule(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", mode: .custom("custom-6F1A")),
        ]
        let websiteRules = [WebsiteModeRule(host: "mail.google.com", mode: .custom("custom-6F1A"))]
        let appData = try JSONEncoder().encode(appRules)
        let websiteData = try JSONEncoder().encode(websiteRules)

        // Older builds read the own mode as Blitztext, so the rule does nothing there.
        XCTAssertEqual(try JSONDecoder().decode([OldAppRule].self, from: appData).map(\.mode), [.textImprover, .tapTalk])
        XCTAssertEqual(try JSONDecoder().decode([OldWebsiteRule].self, from: websiteData).map(\.mode), [.tapTalk])

        XCTAssertEqual(try JSONDecoder().decode([AppModeRule].self, from: appData), appRules)
        XCTAssertEqual(try JSONDecoder().decode([WebsiteModeRule].self, from: websiteData), websiteRules)
    }

    /// Older builds rewrite settings.json without the modes; their own file keeps them.
    func testCustomModeFileKeepsTheModes() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-modes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(CustomModeFile.load(from: url))

        let modes = [CustomMode.new(name: "Konzept", prompt: "Mach ein Konzept daraus.")]
        CustomModeFile.save(modes, to: url)
        XCTAssertEqual(CustomModeFile.load(from: url), modes)

        // Deleting every mode is remembered too, so the templates do not come back.
        CustomModeFile.save([], to: url)
        XCTAssertEqual(CustomModeFile.load(from: url), [])
    }

    // MARK: - Own modes

    func testCustomModeRoundTrip() throws {
        var mode = CustomMode.new(name: "Konzept", icon: "lightbulb.fill", prompt: "Mach ein Konzept daraus.")
        mode.colorChoice = .night
        XCTAssertTrue(mode.id.hasPrefix("custom-"))

        let decoded = try JSONDecoder().decode(CustomMode.self, from: JSONEncoder().encode(mode))
        XCTAssertEqual(decoded, mode)
        XCTAssertEqual(decoded.colorChoice, .night)

        // The mode's id is its raw value, in rules and shortcuts alike.
        let type = WorkflowType.custom(mode.id)
        XCTAssertEqual(type.rawValue, mode.id)
        XCTAssertEqual(WorkflowType(rawValue: mode.id), type)
        XCTAssertFalse(type.isBuiltIn)
        let rule = AppModeRule(bundleID: "com.apple.mail", appName: "Mail", mode: type)
        XCTAssertEqual(try JSONDecoder().decode(AppModeRule.self, from: JSONEncoder().encode(rule)), rule)
        XCTAssertEqual(CustomModeLinks.resolvedHotkeys([mode.id: ctrlOptionD], modes: [mode]), [type: ctrlOptionD])
    }

    /// Modes stored by the iOS app have no colour; they keep their JSON shape.
    func testModesWithoutColourKeepTheirShape() throws {
        let json = #"[{"id":"custom-1","name":"Als E-Mail","icon":"envelope.fill","prompt":"Schreib eine Mail."}]"#
        let modes = try JSONDecoder().decode([CustomMode].self, from: Data(json.utf8))
        XCTAssertEqual(modes.first?.colorChoice, .evening)
        XCTAssertNil(modes.first?.color)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(modes)) as? [[String: Any]]
        XCTAssertEqual(encoded?.first.map { Set($0.keys) }, ["id", "name", "icon", "prompt"])
    }

    func testCatalogNamesOwnModes() {
        var mode = CustomMode.new(name: "  Antworten ", icon: "arrowshape.turn.up.left.fill", prompt: "Antworte kurz.")
        mode.colorChoice = .day
        CustomModeCatalog.modes = [mode]

        let type = WorkflowType.custom(mode.id)
        XCTAssertEqual(type.displayName, "Antworten")
        XCTAssertEqual(type.icon, "arrowshape.turn.up.left.fill")
        XCTAssertEqual(type.customMode, mode)
        XCTAssertEqual(type.hotkeyLabel, "", "own modes have no fn shortcut")
    }

    func testUnknownOrDeletedModeFallsBack() throws {
        // A deleted mode, and a mode name from some later version.
        for raw in ["custom-gone", "meetingNotes"] {
            let rule = try JSONDecoder().decode(
                WebsiteModeRule.self,
                from: Data(#"{"host":"mail.google.com","mode":"\#(raw)"}"#.utf8)
            )
            XCTAssertEqual(rule.mode, .custom(raw))
            XCTAssertEqual(rule.mode.displayName, "Eigener Modus")
            XCTAssertEqual(rule.mode.icon, "wand.and.stars")
            XCTAssertNil(rule.mode.customMode)
        }

        var hotkeys = ["custom-gone": ctrlOptionD, "emojiText": f13]
        var appRules = [AppModeRule(bundleID: "com.apple.mail", appName: "Mail", mode: .custom("custom-gone"))]
        var websiteRules = [WebsiteModeRule(host: "mail.google.com", mode: .custom("custom-gone"))]
        XCTAssertEqual(CustomModeLinks.resolvedHotkeys(hotkeys, modes: []), [.emojiText: f13])

        CustomModeLinks.removeOrphans(modes: [], hotkeys: &hotkeys, appRules: &appRules, websiteRules: &websiteRules)
        XCTAssertEqual(hotkeys, ["emojiText": f13])
        XCTAssertEqual(appRules.map(\.mode), [.tapTalk])
        XCTAssertEqual(websiteRules.map(\.mode), [.tapTalk])
    }

    func testDeleteRemovesShortcutAndTurnsRulesBackToBlitztext() {
        let mail = CustomMode.new(name: "Als E-Mail", prompt: "Mail")
        let bullets = CustomMode.new(name: "Stichpunkte", prompt: "Liste")
        var modes = [mail, bullets]
        var hotkeys = [mail.id: ctrlOptionD, bullets.id: f13, "textImprover": KeyCombo(keyCode: 3, modifierFlags: 0, keyLabel: "F")]
        var appRules = [
            AppModeRule(bundleID: "com.apple.mail", appName: "Mail", mode: .custom(mail.id)),
            AppModeRule(bundleID: "com.apple.Notes", appName: "Notizen", mode: .custom(bullets.id)),
            AppModeRule(bundleID: "com.apple.Pages", appName: "Pages", mode: .textImprover),
        ]
        var websiteRules = [WebsiteModeRule(host: "mail.google.com", mode: .custom(mail.id))]

        CustomModeLinks.delete(id: mail.id, modes: &modes, hotkeys: &hotkeys, appRules: &appRules, websiteRules: &websiteRules)

        XCTAssertEqual(modes, [bullets])
        XCTAssertNil(hotkeys[mail.id])
        XCTAssertEqual(hotkeys[bullets.id], f13)
        XCTAssertNotNil(hotkeys["textImprover"])
        XCTAssertEqual(appRules.map(\.mode), [.tapTalk, .custom(bullets.id), .textImprover])
        XCTAssertEqual(appRules.map(\.appName), ["Mail", "Notizen", "Pages"], "rules stay, only their mode changes")
        XCTAssertEqual(websiteRules.map(\.mode), [.tapTalk])
    }

    // MARK: - Shortcut ids

    func testBuiltInHotkeyIDsKeepTheirValues() {
        var ids = HotkeyIDs()
        // Own modes registered first change nothing for the built-in ones.
        _ = ids.id(for: .custom("custom-a"))
        XCTAssertEqual(WorkflowType.builtIn.map { ids.id(for: $0) }, [1, 2, 3, 4, 5])
        XCTAssertEqual(ids.type(for: 3), .textImprover)
    }

    func testHotkeyIDsStayStableWhenModesComeAndGo() {
        var ids = HotkeyIDs()
        let a = ids.id(for: .custom("custom-a"))
        let b = ids.id(for: .custom("custom-b"))
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(min(a, b), HotkeyIDs.firstCustomID)

        // "a" was deleted (it no longer registers), "c" was added: "b" keeps its id and "c"
        // does not take over the id "a" had.
        let c = ids.id(for: .custom("custom-c"))
        XCTAssertEqual(ids.id(for: .custom("custom-b")), b)
        XCTAssertFalse([a, b].contains(c))
        XCTAssertFalse((1...5).contains(c))

        XCTAssertEqual(ids.type(for: b), .custom("custom-b"))
        XCTAssertEqual(ids.type(for: c), .custom("custom-c"))
        XCTAssertNil(ids.type(for: 999))
    }
}
