import SwiftUI

/// What changed in this release. Shown once per `version`: on the next popover opening,
/// or right after the first dictation for people who only use the shortcuts.
enum WhatsNew {
    /// Bump together with the items when a release deserves a note.
    static let version = "1.11"

    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let items: [Item] = [
        Item(
            icon: "text.cursor",
            title: "Passt zum Text am Cursor",
            detail: "Leerzeichen und Groß- und Kleinschreibung stimmen jetzt auch mitten im Satz. Auf Wunsch sehen die KI-Modi den Text rund um den Cursor: Einstellungen, Modelle."
        ),
        Item(
            icon: "globe",
            title: "Modus je Website",
            detail: "Gmail, Outlook im Web oder Notion bekommen wie Apps ihren eigenen Modus: Einstellungen, Modi."
        ),
        Item(
            icon: "speaker.slash",
            title: "Ton aus beim Diktieren",
            detail: "Podcast oder Musik sind stumm, solange du diktierst, und danach sofort wieder zu hören. Abschalten unter Einstellungen, Allgemein."
        ),
        Item(
            icon: "checkmark.bubble",
            title: "Weniger Erfundenes",
            detail: "Sätze wie „Untertitel im Auftrag des ZDF“ fliegen raus, und Blitztext+ beantwortet diktierte Fragen nicht mehr, sondern schreibt sie auf."
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
                    .font(.system(size: 12))
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BlitztextTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.detail)
                                .font(.system(size: 11.5))
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
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.glassAction)
                }
                Button {
                    appState.markWhatsNewSeen()
                    appState.page = .main
                } label: {
                    Text("Verstanden")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glassAction)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
