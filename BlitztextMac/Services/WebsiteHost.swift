import Foundation

/// Website addresses for "Modus je App": what people type, what browsers report.
enum WebsiteHost {
    /// "https://www.Mail.google.com/mail/u/0" or "mail.google.com" -> "mail.google.com".
    /// Nil for anything that is not a host name.
    static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var host = URL(string: withScheme)?.host, host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    /// A rule for "google.com" also covers "mail.google.com", not "notgoogle.com".
    static func matches(_ host: String, rule: String) -> Bool {
        let host = host.lowercased()
        return host == rule || host.hasSuffix("." + rule)
    }
}
