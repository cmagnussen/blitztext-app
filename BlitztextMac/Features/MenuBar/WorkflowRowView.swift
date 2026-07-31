import SwiftUI

struct WorkflowRowView: View {
    let type: WorkflowType
    let enabled: Bool
    let hotkeyLabel: String
    var customName: String? = nil
    var subtitle: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with monochrome background
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0.06))
                        .frame(width: 36, height: 36)

                    Image(systemName: type.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // Name + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(customName ?? type.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(enabled ? .primary : .tertiary)
                        .lineLimit(1)

                    Text(subtitle ?? type.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(enabled ? .secondary : .quaternary)
                        .lineLimit(1)
                }

                Spacer()

                // Hotkey badge
                HotkeyBadge(label: hotkeyLabel, enabled: enabled)
                    .opacity(enabled ? 1 : 0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered && enabled ? Color.primary.opacity(0.05) : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

}

// MARK: - Hotkey Badge

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

        return colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.09)
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
