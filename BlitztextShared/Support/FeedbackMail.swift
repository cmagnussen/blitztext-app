import Foundation

/// "Feedback senden": a prepared mail to the Blitztext team with the facts that help to
/// understand a report. People see the whole mail before it goes out; the app itself sends
/// nothing and adds no logs.
enum FeedbackMail {
    static let address = "blitztext@blackboat.com"

    /// - Parameter details: lines about this app's setup, e.g. speech model and shortcut mode.
    static func url(details: [String] = []) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let facts = [
            "App: Blitztext \(version) (Build \(build)) für \(platform)",
            "System: \(systemName) \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Gerät: \(deviceModel)",
        ] + details

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Blitztext Feedback (\(platform) \(version), Build \(build))"),
            URLQueryItem(name: "body", value: "\n\n\n---\nBitte oberhalb der Linie schreiben. Diese Angaben helfen uns beim Nachvollziehen, du kannst sie auch löschen:\n" + facts.joined(separator: "\n")),
        ]
        return components.url
    }

    private static var platform: String {
        #if os(macOS)
        return "Mac"
        #else
        return "iPhone"
        #endif
    }

    private static var systemName: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    /// "iPhone17,5" or "Mac16,10, Apple M4": the model identifier, on the Mac with the chip.
    private static var deviceModel: String {
        #if os(macOS)
        let model = sysctl("hw.model") ?? "Mac"
        return [model, sysctl("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: ", ")
        #else
        return sysctl("hw.machine") ?? "iPhone"
        #endif
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
