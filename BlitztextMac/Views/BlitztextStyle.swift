import SwiftUI
import AppKit

// Visual language shared with _Space, Blackboat's design language:
// glass surfaces, calm monochrome type, colour only where it carries meaning.

enum BlitztextTheme {
    /// Blackboat tokens shared with iOS (BlitztextShared/Design): day in light, night in dark.
    static let accent = BlackboatColor.accent

    static let ready = BlackboatColor.successForeground
    static let danger = BlackboatColor.error

    static let subtleFill = Color.primary.opacity(0.04)
    static let subtleStroke = Color.primary.opacity(0.08)
}

// MARK: - Surfaces

enum BlitztextSurface {
    @ViewBuilder
    static var windowBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color(nsColor: .controlBackgroundColor).opacity(0.06),
                        Color.primary.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    static var border: Color {
        Color.primary.opacity(0.10)
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color(nsColor: .controlBackgroundColor).opacity(tintOpacity))
            }
            .overlay {
                shape.strokeBorder(BlitztextSurface.border, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                shape
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
                    .blendMode(.plusLighter)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 16, x: 0, y: 5)
            .clipShape(shape)
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    let tint: Color
    let fillOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(tint.opacity(fillOpacity))
            }
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
            .clipShape(Capsule())
    }
}

private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 12, tintOpacity: Double = 0.075, shadowOpacity: Double = 0.045) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity, shadowOpacity: shadowOpacity))
    }

    func glassCapsule(tint: Color, fillOpacity: Double = 0.11) -> some View {
        modifier(GlassCapsuleModifier(tint: tint, fillOpacity: fillOpacity))
    }

    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Building Blocks

/// Uppercase section title above a card, as in _Space settings.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
    }
}

/// Section title with its content inside a settings card.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .settingsCard()
        }
    }
}

/// Label left, small switch right, so all switches in a settings card line up.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            configuration.label
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

extension ToggleStyle where Self == TrailingSwitchToggleStyle {
    static var trailingSwitch: TrailingSwitchToggleStyle { TrailingSwitchToggleStyle() }
}

/// Title and helper text left, control right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// Status capsule with icon, e.g. "Bereit" or "Lokal".
struct StatusCapsule: View {
    let title: String
    let icon: String
    let tint: Color
    var fillOpacity: Double = 0.07

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint.opacity(0.95))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.84))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCapsule(tint: tint, fillOpacity: fillOpacity)
    }
}

/// Compact notice with icon, text and an optional action.
struct NoticeRow: View {
    let icon: String
    let title: String
    var detail: String?
    var tint: Color = BlitztextTheme.accent
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.subtle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Header for sub pages: back button, centered title, optional trailing view.
struct PageHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Zur\u{00FC}ck")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.subtle)

                Spacer()

                trailing
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack, trailing: { EmptyView() })
    }
}

// MARK: - Buttons

/// No fill except on hover, soft press effect.
struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SubtleButtonBody(configuration: configuration)
    }

    private struct SubtleButtonBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                }
                .opacity(configuration.isPressed ? 0.6 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
}

/// Glass button for the footer bar and primary actions.
struct GlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassActionBody(configuration: configuration)
    }

    private struct GlassActionBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.22 : 0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.095), lineWidth: 1)
                }
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == GlassActionButtonStyle {
    static var glassAction: GlassActionButtonStyle { GlassActionButtonStyle() }
}

// MARK: - Controls

/// Monochrome alternative to `Picker(.segmented)`, same as in _Space.
struct SegmentedToggle<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(0.10))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// One labelled bar for a relative value (0...1).
struct ModelRatingView: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Speed and accuracy bars plus size for a local model.
struct ModelRatingPanel: View {
    let rating: LocalModelRating
    var modelName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModelRatingView(label: "Tempo", value: rating.speed)
            ModelRatingView(label: "Genauigkeit", value: rating.accuracy)
            Text(rating.languages)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(rating.sizeLabel). Richtwerte, nicht auf deutschen Diktaten gemessen.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if modelName == ParakeetTranscriber.modelName {
                // CC BY 4.0 requires attribution.
                HStack(spacing: 4) {
                    Text("Parakeet TDT 0.6B v3 von NVIDIA,")
                    Link("CC BY 4.0", destination: ParakeetTranscriber.licenseURL)
                    Text("via FluidAudio.")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Popover Host

/// Hosts the SwiftUI root in an HUD material, like _Space. The popover height follows the content.
final class GlassPopoverHostingController<Content: View>: NSViewController {
    private let rootView: Content
    private let width: CGFloat

    init(rootView: Content, width: CGFloat) {
        self.rootView = rootView
        self.width = width
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        addChild(hostingController)

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        preferredContentSize = viewController.preferredContentSize
    }
}
