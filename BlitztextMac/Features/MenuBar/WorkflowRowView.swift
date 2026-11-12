import SwiftUI

struct WorkflowRowView: View {
    let type: WorkflowType
    let enabled: Bool
    var customName: String? = nil
    var subtitle: String? = nil
    var hotkeyLabel: String? = nil
    /// One line per mode for the main page: the name and its shortcut, the description is
    /// the tooltip. Seven modes then fit without a list that scrolls inside the page.
    var compact = false
    let action: () -> Void

    @State private var isHovered = false

    private var badgeLabel: String { hotkeyLabel ?? type.hotkeyLabel }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ModeIcon(type: type, size: compact ? 26 : 34)
                    .opacity(enabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    Text(customName ?? type.displayName)
                        .font(.ui(13.5, .semibold))
                        .foregroundStyle(enabled ? .primary : .tertiary)
                        .lineLimit(1)

                    if !compact {
                        Text(subtitle ?? type.subtitle)
                            .font(.ui(11.5))
                            .foregroundStyle(enabled ? .secondary : .quaternary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                // An own mode without its own shortcut has none to show.
                if !badgeLabel.isEmpty {
                    HotkeyBadge(label: badgeLabel, enabled: enabled)
                        .opacity(enabled ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 5 : 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered && enabled ? Color.primary.opacity(0.05) : Color.clear)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(compact ? (subtitle ?? type.subtitle) : "Startet \(customName ?? type.displayName)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct HotkeyBadge: View {
    let label: String
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(label.components(separatedBy: " + "), id: \.self) { key in
                Text(key)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(keyBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(keyStrokeColor, lineWidth: 0.8)
                    )
                    .shadow(color: keyShadowColor, radius: 1.2, y: 0.6)
            }
        }
    }

    private var keyTextColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.34)
                : Color.black.opacity(0.26)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.84)
            : Color.black.opacity(0.72)
    }

    private var keyBackgroundColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color.black.opacity(0.035)
        }

        return BlitztextTheme.inset
    }

    private var keyStrokeColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.16)
    }

    private var keyShadowColor: Color {
        guard enabled else { return .clear }

        return colorScheme == .dark
            ? Color.black.opacity(0.10)
            : Color.black.opacity(0.06)
    }
}
