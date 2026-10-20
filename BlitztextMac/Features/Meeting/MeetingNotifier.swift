import Foundation
import UserNotifications

/// Tells the user that a meeting evaluation finished while the menu was closed: a long
/// meeting takes minutes, and nobody keeps the menu open for that. The message names
/// length and number of people, never what was said.
enum MeetingNotifier {
    /// Asked when a meeting starts, so the question never interrupts the end of one.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func finished(_ record: MeetingRecord) {
        let people = record.speakers.count == 1 ? "1 Person" : "\(record.speakers.count) Personen"
        post(title: "Meeting ausgewertet", body: "\(duration(record.duration)), \(people). Im Blitztext-Men\u{00FC} unter Meeting.")
    }

    static func failed(_ message: String) {
        post(title: "Meeting-Auswertung fehlgeschlagen", body: message)
    }

    /// "2 Std. 3 Min." or "45 Min."
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
