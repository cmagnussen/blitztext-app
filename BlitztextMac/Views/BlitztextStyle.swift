import SwiftUI
import AppKit

// The Blitztext look of the iOS app on the Mac: Blackboat surfaces (a quiet page, white
// cards by day, night surfaces in dark mode), Public Sans, the accent only for actions
// and selection. Structure follows Material 3 like on iOS.

enum BlitztextTheme {
    /// Blackboat tokens shared with iOS (BlitztextShared/Design): day in light, night in dark.
    static let accent = BlackboatColor.accent
    /// Text and icons on a filled accent: white by day, the night contrast ink on lilac.
    static let onAccent = BlackboatColor.dynamic(light: 0xFFFFFF, dark: 0x0F1116)

    static let ready = BlackboatColor.successForeground
    static let danger = BlackboatColor.error

    /// Page behind the cards: surface hover by day, surface base at night.
    static let page = BlackboatColor.dynamic(light: 0xF5F5F5, dark: 0x050722)
    /// Cards and grouped rows: surface elevated.
    static let card = BlackboatColor.surfaceElevated
    /// Fills inside a card: fields, tracks.
    static let inset = BlackboatColor.dynamic(light: 0xF5F5F5, dark: 0x191B46)
    /// Selected and tonal elements: the tertiary accent at low strength.
    static let tonal = BlackboatColor.dynamic(light: 0x70A5FF, dark: 0xBB84DF).opacity(0.26)
    static let onTonal = BlackboatColor.dynamic(light: 0x0B0EC1, dark: 0xFFFFFF)
    /// The lilac of Blackboat's night accents, for the recording indicator.
    static let lilac = BlackboatColor.dynamic(light: 0x8337A8, dark: 0xBB84DF)

    static let cardShadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .clear : NSColor(srgbRed: 0.05, green: 0.07, blue: 0.11, alpha: 0.07)
    })
    static let cardEdge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : .clear
    })

    static let subtleFill = Color.primary.opacity(0.04)
    static let subtleStroke = Color.primary.opacity(0.08)
}

extension Font {
    /// Public Sans at a fixed size (the Mac has no Dynamic Type). Medium maps to
    /// SemiBold, the closest weight the app bundles.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: BlackboatType.Weight
        switch weight {
        case .bold, .heavy, .black: face = .bold
        case .semibold, .medium: face = .semibold
        default: face = .regular
        }
        return .custom(face.rawValue, fixedSize: size)
    }
}

// MARK: - Surfaces

enum BlitztextSurface {
    @ViewBuilder
    static var windowBackground: some View {
        Rectangle()
            .fill(BlitztextTheme.page)
    }

    static var border: Color {
        BlitztextTheme.subtleStroke
    }
}

private struct CardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(BlitztextTheme.card)
                    .shadow(color: BlitztextTheme.cardShadow, radius: 3, x: 0, y: 1)
            }
            .overlay {
                shape.strokeBorder(BlitztextTheme.cardEdge, lineWidth: 1)
            }
            .clipShape(shape)
    }
}

private struct TonalCapsuleModifier: ViewModifier {
    let tint: Color
    let fillOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(tint.opacity(min(fillOpacity * 1.6, 1))))
            .clipShape(Capsule())
    }
}

private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardModifier(cornerRadius: 14))
    }
}

extension View {
    /// A card on the page. The name stays from the glass days; the parameters beyond the
    /// radius are no longer used.
    func glassPanel(cornerRadius: CGFloat = 14, tintOpacity: Double = 0, shadowOpacity: Double = 0) -> some View {
        modifier(CardModifier(cornerRadius: max(cornerRadius, 12)))
    }

    func glassCapsule(tint: Color, fillOpacity: Double = 0.11) -> some View {
        modifier(TonalCapsuleModifier(tint: tint, fillOpacity: fillOpacity))
    }

    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Building Blocks

/// Section title above a card: neutral, so the accent stays with actions.
struct SectionHeader: View {
    let title: String
    var isBeta = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if isBeta { BetaBadge() }
        }
        .padding(.horizontal, 2)
    }
}

/// Marks a feature that is new and still being tried out.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.ui(10, .semibold))
            .foregroundStyle(BlitztextTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(BlitztextTheme.accent.opacity(0.12)))
            .help("Neu und noch in Erprobung. R\u{00FC}ckmeldungen gern \u{00FC}ber \u{201E}Feedback senden\u{201C}.")
            .accessibilityLabel("Beta, noch in Erprobung")
    }
}

/// Section title with its content inside a settings card.
struct SettingsSection<Content: View>: View {
    let title: String
    var isBeta = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, isBeta: isBeta)
            VStack(alignment: .leading, spacing: 12) {
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
                .font(.ui(12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            if MacSnapshots.folder != nil {
                // Offscreen captures draw AppKit switches as off; draw the state instead.
                Capsule()
                    .fill(configuration.isOn ? BlitztextTheme.accent : BlitztextTheme.inset)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 1, y: 0.5).padding(2)
                    }
                    .frame(width: 32, height: 18)
            } else {
                nativeSwitch(configuration)
            }
            #else
            nativeSwitch(configuration)
            #endif
        }
    }

    private func nativeSwitch(_ configuration: Configuration) -> some View {
        Toggle("", isOn: configuration.$isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(BlitztextTheme.accent)
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
                    .font(.ui(13))
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
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
                .font(.ui(11, .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(BlitztextTheme.tonal))
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.ui(12, .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
    }
}

/// Header for sub pages: round back button, centered title, optional trailing view.
struct PageHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.ui(14, .semibold))

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(BlitztextTheme.card))
                        .shadow(color: BlitztextTheme.cardShadow, radius: 2, y: 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Zur\u{00FC}ck")
                .accessibilityLabel("Zur\u{00FC}ck")

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

extension WorkflowType {
    /// Accent family from the Blackboat tokens, as on iOS: day for plain dictation,
    /// evening for the writing modes, night for Dampf ablassen.
    var tint: Color {
        switch self {
        case .tapTalk, .localTapTalk: return BlackboatColor.Source.day.primary
        case .dampfAblassen: return BlackboatColor.Source.night.primary
        case .textImprover, .emojiText: return BlackboatColor.Source.evening.primary
        }
    }
}

/// The mode's symbol in a circle of its colour, as on iOS.
struct ModeIcon: View {
    let type: WorkflowType
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: type.icon)
            .font(.ui(size * 0.42, .semibold))
            .foregroundStyle(type.tint)
            .frame(width: size, height: size)
            .background(Circle().fill(type.tint.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

/// "Blitztext by Blackboat" with the mark.
struct BrandRow: View {
    var body: some View {
        HStack(spacing: 9) {
            BlackboatMark()
                .fill(Color.primary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Blitztext")
                    .font(.ui(15, .bold))
                Text("by Blackboat")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
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

/// Tonal capsule (M3 tonal button) for secondary actions.
struct GlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TonalBody(configuration: configuration, filled: false)
    }
}

/// Filled capsule in the accent for the one main action of a view.
struct FilledActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TonalBody(configuration: configuration, filled: true)
    }
}

private struct TonalBody: View {
    let configuration: ButtonStyleConfiguration
    let filled: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.ui(12, .semibold))
            .foregroundStyle(filled ? BlitztextTheme.onAccent : BlitztextTheme.onTonal)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: configuration.isPressed ? 10 : 100, style: .continuous)
                    .fill(filled ? BlitztextTheme.accent : BlitztextTheme.tonal)
                RoundedRectangle(cornerRadius: configuration.isPressed ? 10 : 100, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == GlassActionButtonStyle {
    static var glassAction: GlassActionButtonStyle { GlassActionButtonStyle() }
}

extension ButtonStyle where Self == FilledActionButtonStyle {
    static var filledAction: FilledActionButtonStyle { FilledActionButtonStyle() }
}

// MARK: - Controls

/// M3 segmented buttons: outlined capsule, the selected segment tonal with a check.
struct SegmentedToggle<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isSelected = option == selection
                if index > 0 {
                    Rectangle().fill(BlitztextTheme.subtleStroke.opacity(2)).frame(width: 1)
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                } label: {
                    HStack(spacing: 4) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.ui(9.5, .bold))
                        }
                        Text(label(option))
                            .font(.ui(11.5, isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? BlitztextTheme.onTonal : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? BlitztextTheme.tonal : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(BlitztextTheme.subtleStroke.opacity(2), lineWidth: 1))
    }
}

/// One labelled bar for a relative value (0...1).
struct ModelRatingView: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.ui(10.5))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(BlitztextTheme.inset)
                    Capsule()
                        .fill(BlitztextTheme.accent)
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
                .font(.ui(10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(rating.sizeLabel). Richtwerte aus veröffentlichten Benchmarks, nicht auf diesem Mac gemessen.")
                .font(.ui(10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if modelName == ParakeetTranscriber.modelName {
                // CC BY 4.0 requires attribution.
                Text((try? AttributedString(markdown: ParakeetTranscriber.attribution)) ?? AttributedString(ParakeetTranscriber.attribution))
                    .font(.ui(10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Popover Host

/// Hosts the SwiftUI root on the page surface. The popover height follows the content.
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
        view = PageView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
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

    override func viewWillAppear() {
        super.viewWillAppear()
        (view as? PageView)?.tintPopoverFrame()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        preferredContentSize = viewController.preferredContentSize
    }
}

/// Root of the popover. Gives the popover's own frame, arrow included, the page colour,
/// again whenever the appearance changes.
private final class PageView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        tintPopoverFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tintPopoverFrame()
    }

    func tintPopoverFrame() {
        guard let frameView = window?.contentView?.superview else { return }
        frameView.wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            frameView.layer?.backgroundColor = NSColor(BlitztextTheme.page).cgColor
        }
    }
}
