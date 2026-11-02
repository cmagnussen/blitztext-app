import SwiftUI

/// Popover page for a transcribed audio file (Voice Memo, WhatsApp voice message, ...).
struct AudioFileView: View {
    @Bindable var appState: AppState

    private var controller: AudioFileController { appState.audioFile }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Audiodatei", onBack: {
                controller.close()
                appState.page = .main
            })

            Divider().opacity(0.16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fileRow

                    switch controller.phase {
                    case .idle:
                        EmptyView()
                    case .working(let message):
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(message)
                                .font(.ui(12.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassPanel()
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.ui(12.5))
                            .foregroundStyle(BlitztextTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassPanel()
                    case .done:
                        result
                    }

                    Text("Die Datei wird auf diesem Mac transkribiert und nicht ver\u{00E4}ndert.")
                        .font(.ui(11))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }

            Divider().opacity(0.16)

            HStack {
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .chooseAudioFile, object: nil)
                } label: {
                    Label("Andere Datei ...", systemImage: "folder")
                        .font(.ui(12, .medium))
                }
                .buttonStyle(.glassAction)
                .disabled(controller.isWorking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 520)
    }

    private var fileRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.ui(15, .semibold))
                .foregroundStyle(BlitztextTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.fileName)
                    .font(.ui(12.5, .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if controller.duration > 0 {
                    Text(durationText)
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var durationText: String {
        let seconds = Int(controller.duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) min"
    }

    /// The AI modes, including own modes with an instruction.
    private var rewriteModes: [WorkflowType] {
        appState.menuModes.filter { appState.needsLanguageModel($0) }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: controller.mode.icon)
                Text(appState.displayName(for: controller.mode))
                Spacer()
                if controller.copied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(BlitztextTheme.ready)
                        Text("In der Zwischenablage")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .font(.ui(11, .semibold))
            .foregroundStyle(.secondary)

            Text(controller.text)
                .font(.ui(13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    controller.copy(appState: appState)
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                        .font(.ui(12, .medium))
                }
                .buttonStyle(.glassAction)

                if appState.canRewrite {
                    Menu {
                        ForEach(rewriteModes.filter { $0 != controller.mode }, id: \.self) { mode in
                            Button(appState.displayName(for: mode)) {
                                controller.rewrite(as: mode, appState: appState)
                            }
                        }
                        if controller.mode != .tapTalk {
                            Divider()
                            Button("Original-Transkript") {
                                controller.showTranscript(appState: appState)
                            }
                        }
                    } label: {
                        Label("Umschreiben als ...", systemImage: "wand.and.stars")
                            .font(.ui(12, .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(14)
        .glassPanel()
    }
}
