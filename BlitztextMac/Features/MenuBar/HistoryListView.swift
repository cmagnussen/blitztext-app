import SwiftUI

struct HistoryListView: View {
    @Bindable var appState: AppState

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        let entries = appState.history.entries

        VStack(alignment: .leading, spacing: 0) {
            if appState.appSettings.historyRetention == .off {
                emptyState(
                    icon: "clock.badge.xmark",
                    title: "Verlauf ist aus",
                    detail: "In den Einstellungen unter \u{201E}Einf\u{00FC}gen & Verlauf\u{201C} einschalten."
                )
            } else if entries.isEmpty {
                emptyState(
                    icon: "clock",
                    title: "Noch nichts im Verlauf",
                    detail: "Ergebnisse bleiben \(retentionHint) nur auf diesem Mac, verschl\u{00FC}sselt."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            HistoryRow(
                                entry: entry,
                                workflowName: appState.displayName(for: entry.workflow),
                                timestamp: Self.relativeFormatter.localizedString(for: entry.createdAt, relativeTo: Date()),
                                onPaste: { appState.pasteFromHistory(entry) },
                                onCopy: { appState.copyToClipboard(entry.text) },
                                onDelete: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        appState.history.remove(entry)
                                    }
                                }
                            )
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 360)

                HStack {
                    Text("Nur auf diesem Mac, \(retentionHint).")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Alles l\u{00F6}schen") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            appState.history.clear()
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(SubtleButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }

    private var retentionHint: String {
        switch appState.appSettings.historyRetention {
        case .off: return ""
        case .day: return "24 Stunden"
        case .week: return "7 Tage"
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

private struct HistoryRow: View {
    let entry: TranscriptHistoryEntry
    let workflowName: String
    let timestamp: String
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: entry.workflow.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(workflowName)
                    .font(.system(size: 10.5, weight: .medium))
                Text(timestamp)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .help("Eintrag l\u{00F6}schen")
                }
            }
            .foregroundStyle(.secondary)

            Text(entry.text)
                .font(.system(size: 11.5))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button(action: onPaste) {
                    Label("Einf\u{00FC}gen", systemImage: "text.insert")
                }
                Button {
                    onCopy()
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopy = false }
                } label: {
                    Label(didCopy ? "Kopiert" : "Kopieren", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                Spacer()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(BlitztextTheme.accent)
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0.03))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
