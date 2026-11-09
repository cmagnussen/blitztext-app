import SwiftUI

/// What changed in this release. Shown once per `version`: on the next popover opening,
/// or right after the first dictation for people who only use the shortcuts.
enum WhatsNew {
    /// Bump together with the items when a release deserves a note.
    static let version = "1.17"

    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let items: [Item] = [
        Item(
            icon: "person.2.wave.2",
            title: "Meetings",
            detail: "Ein Klick auf den Titel benennt ein Meeting um. Nach langen Online-Meetings bleibt der Mac fl\u{00FC}ssig, und die Aufnahmen landen nicht mehr im Backup."
        ),
        Item(
            icon: "textformat",
            title: "Schreibweise",
            detail: "Uhrzeiten stehen als 16:45 Uhr da. Unter Allgemein gibt es Deutsch (Schweiz) mit ss, 12\u{2019}500 und \u{00AB}\u{2026}\u{00BB}, auf Macs in der Schweiz automatisch."
        ),
        Item(
            icon: "lock.shield",
            title: "Datenschutz",
            detail: "Tastendr\u{00FC}cke anderer Apps sieht Blitztext nur noch w\u{00E4}hrend eines Diktats, f\u{00FC}r Escape. Ein API-Key geht nie unverschl\u{00FC}sselt per http an einen anderen Rechner."
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
