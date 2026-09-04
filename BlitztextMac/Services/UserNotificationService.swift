import Foundation
import UserNotifications
import OSLog

private let notificationLogger = Logger(subsystem: "app.blitztext.mac", category: "Notifications")

/// Rückmeldung nach einem Diktat. Ohne sichtbare Bestätigung weiß niemand, ob
/// die Zeile angekommen ist, und ein stilles Verschlucken darf es nicht geben.
enum UserNotificationService {
    private static let previewLength = 100

    /// Wird erst beim ersten Diktat aufgerufen, nicht beim App-Start. Wer den
    /// Kanal nicht benutzt, sieht kein Prompt.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                notificationLogger.error(
                    "Benachrichtigungsfreigabe fehlgeschlagen: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        case .denied:
            return false
        default:
            return true
        }
    }

    static func authorizationDenied() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    static func notifyDictationSaved(preview: String, fileName: String) {
        post(
            title: "Diktat gespeichert",
            subtitle: fileName,
            body: shortened(preview)
        )
    }

    static func notifyDictationFailed(reason: String) {
        post(
            title: "Diktat nicht gespeichert",
            subtitle: nil,
            body: "\(reason) Der Text liegt in der Zwischenablage."
        )
    }

    private static func shortened(_ text: String) -> String {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard roh.count > previewLength else { return roh }
        return String(roh.prefix(previewLength)) + " ..."
    }

    private static func post(title: String, subtitle: String?, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                notificationLogger.error(
                    "Benachrichtigung konnte nicht gezeigt werden: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
