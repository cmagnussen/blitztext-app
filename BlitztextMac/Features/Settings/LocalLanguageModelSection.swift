import SwiftUI

/// "Lokales Sprachmodell für Meetings": which Gemma variants this Mac can run, how large
/// they are, and download, cancel or remove.
struct LocalLanguageModelSection: View {
    private var store: LocalModelStore { .shared }
    private let memoryGB = LocalModelVariant.installedMemoryGB

    var body: some View {
        SettingsSection(title: "Lokales Sprachmodell f\u{00FC}r Meetings", isBeta: true) {
            Text("Optional. Fasst Meetings auf diesem Mac genauer zusammen als Apple Intelligence, vor allem lange. Der Text verl\u{00E4}sst den Mac nicht. Das Modell wird einmal heruntergeladen und belegt nur w\u{00E4}hrend der Zusammenfassung Arbeitsspeicher.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(LocalModelVariant.all) { variant in
                row(variant)
                if variant != LocalModelVariant.all.last {
                    Divider().opacity(0.5)
                }
            }

            Text(footnote)
                .font(.ui(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        let mac = LocalModelVariant.isAppleSilicon
            ? "Dieser Mac hat \(memoryGB) GB Arbeitsspeicher."
            : "Dieser Mac hat keinen Apple-Chip."
        return mac + " Ist ein Modell geladen, nutzen Meetings es automatisch. Gemma 4 von Google, Lizenz Apache 2.0."
    }

    private func row(_ variant: LocalModelVariant) -> some View {
        let support = variant.support()
        let state = store.state(of: variant)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(variant.name)
                    .font(.ui(12.5, .semibold))
                if store.preferredInstalled == variant {
                    badge("Wird genutzt")
                } else if LocalModelVariant.recommended() == variant, state != .installed {
                    badge("Passt zu diesem Mac")
                }
                Spacer(minLength: 8)
                action(variant, state: state, support: support)
            }

            Text(details(variant, support: support))
                .font(.ui(11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch state {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .controlSize(.small)
                Text("\(Int(fraction * 100)) %. Du kannst Blitztext weiter nutzen.")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.ui(11.5))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private func details(_ variant: LocalModelVariant, support: LocalModelVariant.Support) -> String {
        let size = "Download \(LocalModelStore.gigabytes(variant.downloadSize))"
        let memory = String(format: "%.0f", variant.memoryInUse.rounded(.up))
        let needs = "braucht beim Zusammenfassen etwa \(memory) GB Arbeitsspeicher, empfohlen ab \(variant.minimumMemoryGB) GB"
        switch support {
        case .available:
            return "\(variant.purpose). \(size), \(needs)."
        case .unavailable(let reason):
            return "\(variant.purpose). \(size). \(reason)"
        }
    }

    @ViewBuilder
    private func action(_ variant: LocalModelVariant, state: LocalModelStore.State, support: LocalModelVariant.Support) -> some View {
        switch state {
        case .notInstalled, .failed:
            Button(state == .notInstalled ? "Laden" : "Erneut laden") { store.download(variant) }
                .controlSize(.small)
                .disabled(support != .available)
        case .downloading:
            Button("Abbrechen") { store.cancel(variant) }
                .controlSize(.small)
        case .installed:
            Button("Entfernen", role: .destructive) { store.remove(variant) }
                .controlSize(.small)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.ui(10.5, .semibold))
            .foregroundStyle(BlitztextTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(BlitztextTheme.accent.opacity(0.12)))
    }
}
