import AppKit
import ApplicationServices

/// What Blitztext can see of the text field a dictation goes into.
struct FocusedField: Equatable {
    var textBefore = ""
    var selectedText = ""
    var textAfter = ""

    /// The surrounding text for the AI modes, the same shape the iOS keyboard sends.
    var aiContext: String? {
        let parts = [textBefore, selectedText, textAfter]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

/// Reads the focused text field and the browser address through the Accessibility API,
/// which Blitztext already needs for pasting. Password fields are never read. Every call
/// gives up quickly, so an app that hangs cannot hold up a dictation.
enum FocusedFieldReader {
    /// Characters kept on each side of the cursor.
    static let beforeLimit = 2_000
    static let afterLimit = 600

    /// Browsers whose tab address "Modus je Website" can read.
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.brave.Browser", "company.thebrowser.Browser", "company.thebrowser.dia", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "app.zen-browser.zen", "com.kagi.kagimacOS",
    ]

    /// Chromium and Firefox only build their web accessibility tree on request.
    private static let browsersNeedingManualAccessibility: Set<String> = browserBundleIDs
        .subtracting(["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS"])

    static func isBrowser(_ bundleID: String?) -> Bool {
        bundleID.map(browserBundleIDs.contains) ?? false
    }

    /// Text around the cursor in the focused field of `pid`, or nil when the field is a
    /// password field, has no readable text or does not report a cursor.
    static func field(pid: pid_t, bundleID: String?) -> FocusedField? {
        guard prepare() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        enableWebAccessibility(app, bundleID: bundleID)

        guard let focused = element(app, kAXFocusedUIElementAttribute),
              !isSecure(focused),
              let value = string(focused, kAXValueAttribute),
              let range = selectedRange(focused) else {
            return nil
        }

        let text = value as NSString
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.length else {
            return nil
        }
        return FocusedField(
            textBefore: String(text.substring(to: range.location).suffix(beforeLimit)),
            selectedText: text.substring(with: NSRange(location: range.location, length: range.length)),
            textAfter: String(text.substring(from: range.location + range.length).prefix(afterLimit))
        )
    }

    /// Where the focus is: the element, its role and its position on screen.
    struct FocusSpot {
        let element: AXUIElement
        let role: String?
        let position: CGPoint?

        /// The same field, also when the app rebuilt its accessibility object meanwhile;
        /// another field differs in role or place.
        func isSameField(as other: FocusSpot) -> Bool {
            CFEqual(element, other.element) || (role == other.role && position == other.position)
        }
    }

    /// The focused element of `pid`, to check before pasting that the focus is still in the
    /// field the dictation goes into. With `textFieldOnly`, nil unless the element reports a
    /// text cursor: without a real field to compare, nothing is checked. Browsers build their
    /// web tree first, so this read and a later one see the same tree.
    static func focusSpot(pid: pid_t, bundleID: String?, textFieldOnly: Bool) -> FocusSpot? {
        guard prepare() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        enableWebAccessibility(app, bundleID: bundleID)
        guard let focused = element(app, kAXFocusedUIElementAttribute),
              !textFieldOnly || selectedRange(focused) != nil else { return nil }
        return FocusSpot(element: focused, role: role(focused), position: position(focused))
    }

    /// Selects `text` right before the cursor of the focused field, so the next paste
    /// replaces it. False when the field does not report its text and cursor, something is
    /// selected, or the text before the cursor is a different one.
    static func selectBeforeCursor(_ text: String, pid: pid_t) -> Bool {
        guard prepare(),
              let focused = element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              !isSecure(focused),
              let value = string(focused, kAXValueAttribute),
              let range = selectedRange(focused), range.length == 0 else { return false }
        let field = value as NSString
        let length = (text as NSString).length
        guard length > 0, range.location >= length, range.location <= field.length,
              field.substring(with: NSRange(location: range.location - length, length: length)) == text else { return false }
        var selection = CFRange(location: range.location - length, length: length)
        guard let wanted = AXValueCreate(.cfRange, &selection) else { return false }
        return AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, wanted) == .success
    }

    /// Host of the tab in front, e.g. "mail.google.com".
    static func webHost(pid: pid_t, bundleID: String?) -> String? {
        guard prepare() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        enableWebAccessibility(app, bundleID: bundleID)
        let deadline = Date().addingTimeInterval(0.15)

        // The page around the focused field: the usual case while typing in a web app.
        var node = element(app, kAXFocusedUIElementAttribute)
        var steps = 0
        while let current = node, steps < 40, Date() < deadline {
            if let host = pageHost(current) {
                return host
            }
            node = element(current, kAXParentAttribute)
            steps += 1
        }

        // Nothing focused inside the page: search the window, within the time budget.
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 400, Date() < deadline {
            let current = queue.removeFirst()
            visited += 1
            if let host = pageHost(current) {
                return host
            }
            queue.append(contentsOf: children(current))
        }
        // Last resort: some browsers only name the address as the window's document.
        return host(window, kAXDocumentAttribute)
    }

    /// Host of a web page element, nil for anything else.
    private static func pageHost(_ element: AXUIElement) -> String? {
        guard role(element) == "AXWebArea" else { return nil }
        return host(element, kAXURLAttribute) ?? host(element, kAXDocumentAttribute)
    }

    // MARK: - Accessibility helpers

    private static let timeoutIsSet: Void = {
        // Applies to every Accessibility call of this process. The default is six seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.12)
    }()

    private static func prepare() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        _ = timeoutIsSet
        return true
    }

    private static func enableWebAccessibility(_ app: AXUIElement, bundleID: String?) {
        guard let bundleID, browsersNeedingManualAccessibility.contains(bundleID) else { return }
        // The switch Chromium and Electron provide for assistive apps to build the web tree.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let value = attribute(element, kAXChildrenAttribute), CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }
        return (value as! [AnyObject]).compactMap { child in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }

    private static func position(_ element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Native and web password fields both report the secure text field subrole.
    private static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// A URL attribute arrives as CFURL or as a string, depending on the app.
    private static func host(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        let url: URL?
        if CFGetTypeID(value) == CFURLGetTypeID() {
            url = (value as! URL)
        } else if let text = value as? String {
            url = URL(string: text)
        } else {
            url = nil
        }
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
