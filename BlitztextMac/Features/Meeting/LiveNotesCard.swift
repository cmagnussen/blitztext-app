import AppKit
import SwiftUI

/// The live notes during a recording, with "Was habe ich verpasst?".
struct LiveNotesCard: View {
    let live: LiveNotesController
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Live-Notizen", systemImage: "list.bullet.rectangle")
                    .font(.ui(12.5, .semibold))
                    .foregroundStyle(BlitztextTheme.accent)
                BetaBadge()
                Spacer(minLength: 4)
                if live.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(status)
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !live.notes.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(live.notes, forType: .string)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Notizen kopieren")
                }
            }

            if live.notes.isEmpty {
                Text("Die ersten Notizen kommen nach etwa zweieinhalb Minuten.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(ListDisplay.bullets(live.notes))
                        .font(.ui(12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }

            if let catchUp = live.catchUp {
                VStack(alignment: .leading, spacing: 6) {
                    Text(catchUp)
                        .font(.ui(12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Schlie\u{00DF}en") { live.dismissCatchUp() }
                        .buttonStyle(.subtle)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            if let problem = live.problem {
                Text(problem)
                    .font(.ui(11))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(live.isCatchingUp ? "Fasse zusammen ..." : "Was habe ich verpasst?") {
                    live.catchUpOnLastMinutes()
                }
                .buttonStyle(.subtle)
                .disabled(live.isCatchingUp)
                Button("Jetzt aktualisieren") { live.update() }
                    .buttonStyle(.subtle)
                    .disabled(live.isUpdating)
            }
        }
        .padding(14)
        .glassPanel()
        .onChange(of: live.notes) { copied = false }
    }

    private var status: String {
        guard let updatedAt = live.updatedAt else { return live.modelName ?? "" }
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        return live.modelName.map { "Stand \(time), \($0)" } ?? "Stand \(time)"
    }
}
