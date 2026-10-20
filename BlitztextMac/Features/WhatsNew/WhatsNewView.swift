import SwiftUI

/// What changed in this release. Shown once per `version`: on the next popover opening,
/// or right after the first dictation for people who only use the shortcuts.
enum WhatsNew {
    /// Bump together with the items when a release deserves a note.
    static let version = "1.15"

    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let items: [Item] = [
        Item(
            icon: "video.fill",
            title: "Online-Meetings (Beta)",
            detail: "Mit dem Schalter \u{201E}Online-Meeting\u{201C} nimmt Blitztext auch den Ton des Macs auf, etwa aus Teams, Zoom oder Meet, und trennt die anderen nach Stimme. Live-Notizen zeigen schon w\u{00E4}hrend des Meetings Themen, Entscheidungen und To-dos. Bitte vorher alle fragen."
        ),
        Item(
            icon: "cpu",
            title: "Lokales Sprachmodell (Beta)",
            detail: "Unter Einstellungen > Modelle l\u{00E4}sst sich Gemma 4 laden. Es fasst lange Meetings genauer zusammen als Apple Intelligence, ganz auf diesem Mac. Blitztext zeigt, welche Gr\u{00F6}\u{00DF}e zu deinem Mac passt."
        ),
        Item(
            icon: "text.cursor",
            title: "Text landet am richtigen Ort",
            detail: "Klickst du in ein anderes Feld, w\u{00E4}hrend ein KI-Modus noch arbeitet, kommt der Text in die Zwischenablage statt ins falsche Feld. Nach einem KI-Modus bietet das Men\u{00FC} \u{201E}Wortgenau statt \u{2026}\u{201C} an. Das erste Wort bleibt erhalten, und Blitztext sagt, wenn das Mikrofon fehlt oder sehr leise ist."
        ),
    ]
}

struct WhatsNewView: View {
    @Bindable var appState: AppState

    private var needsSetup: Bool {
        !appState.isConfigured || !appState.canRewrite
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Neu in Blitztext \(WhatsNew.version)")
                    .font(BlackboatType.publicSans(20, .bold, relativeTo: .title3))
                Text("Einmal kurz, dann geht es weiter wie gewohnt.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.16)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(WhatsNew.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.ui(14, .semibold))
                            .foregroundStyle(BlitztextTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.ui(13, .semibold))
                            Text(item.detail)
                                .font(.ui(11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !appState.isConfigured {
                    NoticeRow(
                        icon: "arrow.down.circle",
                        title: "Noch ein Schritt",
                        detail: "Lade einmal ein lokales Sprachmodell, sonst kann Blitztext nicht transkribieren."
                    )
                } else if !appState.canRewrite {
                    NoticeRow(
                        icon: "key",
                        title: "KI-Modi einrichten",
                        detail: "Ohne Apple Intelligence brauchen Blitztext+, $%&! und :) einen eigenen API-Key."
                    )
                }
            }
            .padding(16)

            Divider().opacity(0.16)

            HStack(spacing: 8) {
                Spacer()
                if needsSetup {
                    Button {
                        appState.markWhatsNewSeen()
                        appState.page = .settings
                    } label: {
                        Text("Einrichten")
                            .font(.ui(12, .medium))
                    }
                    .buttonStyle(.glassAction)
                }
                Button {
                    appState.markWhatsNewSeen()
                    appState.page = .main
                } label: {
                    Text("Verstanden")
                        .font(.ui(12, .semibold))
                }
                .buttonStyle(.glassAction)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
