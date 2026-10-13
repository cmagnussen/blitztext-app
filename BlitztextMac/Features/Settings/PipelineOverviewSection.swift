import SwiftUI

/// "So arbeitet Blitztext": which model does what, as it is set up right now.
struct PipelineOverviewSection: View {
    @Bindable var appState: AppState

    var body: some View {
        SettingsSection(title: "So arbeitet Blitztext") {
            row(
                step: "1",
                title: "Spracherkennung",
                model: appState.selectedLocalModelDisplayName,
                detail: appState.selectedLocalModelIsInstalled
                    ? "Immer lokal auf diesem Mac. Die Sprache verl\u{00E4}sst ihn nie."
                    : "Noch nicht installiert. Unter Modelle, Spracherkennung laden.",
                ready: appState.selectedLocalModelIsInstalled
            )
            row(
                step: "2",
                title: "KI-Modi (Blitztext+, $%&!, :))",
                model: aiModel,
                detail: aiDetail,
                ready: appState.canRewrite
            )
        }
    }

    private var runsLocally: Bool {
        TextRewriter.runsLocally(engine: appState.appSettings.rewriteEngine)
    }

    private var aiModel: String {
        if runsLocally { return "Apple Intelligence" }
        if let provider = appState.providerInUse { return provider }
        return "Nicht eingerichtet"
    }

    private var aiDetail: String {
        if runsLocally {
            return "Lokal auf diesem Mac, ohne Internet."
        }
        if appState.providerInUse != nil {
            // Must match the setting: with cursor context on, that text goes along too.
            return appState.appSettings.aiSeesFieldContext
                ? "\u{00DC}ber deinen API-Key. Der erkannte Text und der Text am Cursor gehen an den Anbieter, nie die Sprache."
                : "\u{00DC}ber deinen API-Key. Nur der erkannte Text geht an den Anbieter, nie die Sprache."
        }
        return "Apple Intelligence einschalten oder unter Modelle einen Modell-Anbieter mit API-Key hinterlegen. Wortgenaues Diktieren geht auch ohne."
    }

    private func row(step: String, title: String, model: String, detail: String, ready: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(BlitztextTheme.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(BlitztextTheme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ready ? BlitztextTheme.ready : BlitztextTheme.danger)
                    Text(model)
                        .font(.system(size: 12.5, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
