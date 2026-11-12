import AppKit
import SwiftUI

/// "Eigene Modi": own writing modes with name, symbol, colour, an instruction for the
/// language model and an optional shortcut, like the modes of the iOS app.
struct CustomModesSection: View {
    @Bindable var appState: AppState
    @State private var expandedID: String?

    #if DEBUG
    /// Mode the snapshot renderer shows open; nil in normal use.
    static var debugExpandedID: String?
    #endif

    private var modes: [CustomMode] { appState.appSettings.customModes }

    /// Templates whose name is not taken yet, as on iOS.
    private var openTemplates: [CustomModeTemplate] {
        let names = Set(modes.map(\.name))
        return CustomModeTemplate.all.filter { !names.contains($0.name) }
    }

    var body: some View {
        SettingsSection(title: "Eigene Modi") {
            Text("Deine eigenen Modi mit einer Anweisung für das KI-Modell, etwa eine E-Mail oder Stichpunkte. Sie stehen im Menü neben den anderen Modi und lassen sich unter „Modus je App“ wählen.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(modes) { mode in
                VStack(alignment: .leading, spacing: 12) {
                    row(mode)
                    if expandedID == mode.id {
                        CustomModeEditor(appState: appState, modeID: mode.id) {
                            expandedID = nil
                        }
                    }
                }
                // The same inset open or closed, so a row does not jump when it opens.
                .padding(.horizontal, 8)
                .padding(.vertical, expandedID == mode.id ? 8 : 0)
                .background {
                    if expandedID == mode.id {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(BlitztextTheme.subtleStroke, lineWidth: 1)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    add(.new(name: "Neuer Modus"))
                } label: {
                    Label("Neuer Modus", systemImage: "plus")
                }
                .buttonStyle(.glassAction)

                if !openTemplates.isEmpty {
                    Menu {
                        ForEach(openTemplates) { template in
                            Button(template.name) { add(template.makeMode()) }
                        }
                    } label: {
                        Label("Aus Vorlage", systemImage: "square.on.square")
                            .font(.ui(11, .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Legt eine fertige Anweisung als eigenen Modus an. Danach kannst du sie anpassen.")
                }
            }
        }
        .onAppear {
            #if DEBUG
            if let id = Self.debugExpandedID { expandedID = id }
            #endif
        }
    }

    private func row(_ mode: CustomMode) -> some View {
        let type = WorkflowType.custom(mode.id)
        let isExpanded = expandedID == mode.id
        let shortcut = appState.appSettings.customHotkey(for: type)?.displayLabel

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                expandedID = isExpanded ? nil : mode.id
            }
        } label: {
            HStack(spacing: 10) {
                ModeIcon(icon: mode.icon, tint: mode.colorChoice.source.primary, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(WorkflowType.customName(mode))
                        .font(.ui(12.5, .semibold))
                        .lineLimit(1)
                    Text(Self.summary(of: mode))
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut.replacingOccurrences(of: " + ", with: ""))
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.ui(10, .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Zuklappen" : "Bearbeiten")
        .accessibilityLabel("\(WorkflowType.customName(mode)) bearbeiten")
    }

    /// The start of the instruction, so modes are easy to tell apart.
    private static func summary(of mode: CustomMode) -> String {
        guard mode.hasInstruction else { return "Ohne Anweisung: wortgenau" }
        return mode.prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
    }

    private func add(_ mode: CustomMode) {
        let id = appState.addCustomMode(mode)
        withAnimation(.easeOut(duration: 0.15)) {
            expandedID = id.customModeID
        }
    }
}

/// Name, symbol, colour, instruction and shortcut of one own mode. Changes are saved as you type.
private struct CustomModeEditor: View {
    @Bindable var appState: AppState
    let modeID: String
    let onDelete: () -> Void

    private var type: WorkflowType { .custom(modeID) }

    private var mode: Binding<CustomMode> {
        Binding(
            get: { appState.appSettings.customModes.first { $0.id == modeID } ?? CustomMode(id: modeID, name: "", icon: "wand.and.stars", prompt: "") },
            set: { appState.updateCustomMode($0) }
        )
    }

    private static let symbolColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name") {
                TextField("z. B. Als E-Mail", text: mode.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.ui(12))
            }

            field("Symbol") {
                LazyVGrid(columns: Self.symbolColumns, spacing: 6) {
                    ForEach(CustomMode.symbols, id: \.self) { symbol in
                        symbolButton(symbol)
                    }
                }
            }

            field("Farbe") {
                HStack(spacing: 10) {
                    ForEach(CustomModeColor.allCases) { color in
                        colorButton(color)
                    }
                    Text(mode.wrappedValue.colorChoice.displayName)
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                }
            }

            field("Anweisung") {
                PromptEditor(
                    text: mode.prompt,
                    placeholder: "z. B. „Formuliere den Text als kurze, freundliche Antwort an einen Kunden.“",
                    height: 96
                )
                Text("Geht mit deinem gesprochenen Text an das KI-Modell. Ohne Anweisung bleibt der Text wortgenau.")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let engineNote {
                    Text(engineNote.text)
                        .font(.ui(11))
                        .foregroundStyle(engineNote.isProblem ? BlitztextTheme.danger : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            field("Kürzel") {
                HStack(spacing: 8) {
                    Text("Ohne eigenes Kürzel startet der Modus über das Menü oder „Modus je App“.")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    HotkeyRecorderButton(appState: appState, type: type)
                }
            }

            Button(role: .destructive) {
                confirmDelete()
            } label: {
                Label("Modus löschen", systemImage: "trash")
                    .font(.ui(11.5, .medium))
                    .foregroundStyle(BlitztextTheme.danger)
            }
            .buttonStyle(SubtleButtonStyle())
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ui(12))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = mode.wrappedValue.icon == symbol
        let tint = mode.wrappedValue.colorChoice.source.primary
        return Button {
            mode.wrappedValue.icon = symbol
        } label: {
            Image(systemName: symbol)
                .font(.ui(13, .semibold))
                .foregroundStyle(isSelected ? tint : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.16) : BlitztextTheme.inset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? tint : .clear, lineWidth: 1.2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ color: CustomModeColor) -> some View {
        let isSelected = mode.wrappedValue.colorChoice == color
        return Button {
            mode.wrappedValue.colorChoice = color
        } label: {
            Circle()
                .fill(color.source.primary)
                .frame(width: 20, height: 20)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.ui(9, .bold))
                            .foregroundStyle(BlitztextTheme.onAccent)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? color.source.primary : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.displayName)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Where the instruction runs, as in "KI-Modi" under Allgemein.
    private var engineNote: (text: String, isProblem: Bool)? {
        guard mode.wrappedValue.hasInstruction else { return nil }
        guard appState.canRewrite else {
            return ("Braucht Apple Intelligence oder einen API-Key unter Allgemein. Bis dahin lässt sich der Modus nicht starten.", true)
        }
        if let provider = appState.providerInUse {
            return ("Läuft über deinen Modell-Anbieter (\(provider)).", false)
        }
        return ("Läuft mit Apple Intelligence auf diesem Mac. Der Text verlässt den Mac nicht.", false)
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "„\(WorkflowType.customName(mode.wrappedValue))“ löschen?"
        alert.informativeText = "Das eigene Kürzel wird entfernt. Apps und Websites mit diesem Modus nutzen wieder Blitztext."
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDelete()
        appState.deleteCustomMode(id: modeID)
    }
}
