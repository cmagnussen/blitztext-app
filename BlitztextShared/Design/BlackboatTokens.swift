import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Blackboat design tokens for the native apps.
// Source of truth: bOS-1 design-system/tokens/design.json. Values are copied, not invented:
// light = "day" mode, dark = "night" mode (the only dark mode in the system).
// When design.json changes, update this file; do not add colours elsewhere in the apps.

enum BlackboatColor {
    // MARK: Surfaces and text

    static let surfaceBase = dynamic(light: 0xFCFCFC, dark: 0x050722)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x0E102F)
    static let surfaceHover = dynamic(light: 0xF5F5F5, dark: 0x191B46)
    static let textPrimary = dynamic(light: 0x111111, dark: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x5C5C5C, dark: 0xF2F4F8)
    static let border = dynamic(light: 0xCFCECD, dark: 0x4F4D69)

    // MARK: Actions

    /// Primary buttons and the recording action: button.primary of day and night.
    static let buttonPrimary = dynamic(light: 0x3E41F4, dark: 0x8337A8)
    static let buttonPrimaryPressed = dynamic(light: 0x0B0EC1, dark: 0x5F287B)
    static let buttonPrimaryText = Color.white
    /// Accent for text, icons and selection. Night uses its tertiary tone, the
    /// primary is too dark to read on night surfaces.
    static let accent = dynamic(light: 0x3E41F4, dark: 0xBB84DF)
    static let focusRing = dynamic(light: 0x70A5FF, dark: 0xBB84DF)

    // MARK: Feedback

    static let success = dynamic(light: 0x5BDFBD, dark: 0x5BDFBD)
    /// Positive status as text or icon. The success green has too little contrast on
    /// day surfaces, so light mode uses the day accent; night keeps the green.
    static let successForeground = dynamic(light: 0x3E41F4, dark: 0x5BDFBD)
    static let error = dynamic(light: 0xD94C76, dark: 0xD94C76)

    // MARK: Accent sources (day, evening, night)

    /// The three accent families of design.json. Modes use one each; on dark
    /// surfaces the tertiary tone replaces the primary for contrast.
    enum Source {
        case day, evening, night

        var primary: Color {
            switch self {
            case .day: return dynamic(light: 0x3E41F4, dark: 0x70A5FF)
            case .evening: return dynamic(light: 0x593AB6, dark: 0xA592DD)
            case .night: return dynamic(light: 0x8337A8, dark: 0xBB84DF)
            }
        }

        /// Filled surfaces (buttons, the microphone): primary to secondary in every mode.
        var gradient: [Color] {
            switch self {
            case .day: return [hex(0x3E41F4), hex(0x0B0EC1)]
            case .evening: return [hex(0x593AB6), hex(0x3C277C)]
            case .night: return [hex(0x8337A8), hex(0x5F287B)]
            }
        }
    }

    // MARK: - Helpers

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? platformColor(dark) : platformColor(light) })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? platformColor(dark) : platformColor(light)
        })
        #endif
    }

    #if canImport(UIKit)
    static func platformColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    #elseif canImport(AppKit)
    static func platformColor(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    #endif
}

/// Radii of design.json (--radius-*).
enum BlackboatRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

/// Type roles of design.json. Headlines use Public Sans; running text stays in the
/// system font so Dynamic Type and native controls keep working.
enum BlackboatType {
    enum Weight: String {
        case regular = "PublicSans-Regular"
        case semibold = "PublicSans-SemiBold"
        case bold = "PublicSans-Bold"
        case extraBold = "PublicSans-ExtraBold"
    }

    /// Public Sans at a size that scales with Dynamic Type.
    static func publicSans(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// type-heading-xl: 36 / 700
    static let headingXL = publicSans(36, .bold, relativeTo: .largeTitle)
    /// type-heading-l: 30 / 700
    static let headingL = publicSans(30, .bold, relativeTo: .title)
    /// type-heading-m: 24 / 600
    static let headingM = publicSans(24, .semibold, relativeTo: .title2)
    /// Card and section titles: body size, strong weight
    static let title = publicSans(17, .semibold, relativeTo: .headline)
    /// type-subtitle: 13 / 600, uppercase eyebrow with 0.2em tracking
    static let eyebrow = publicSans(13, .semibold, relativeTo: .footnote)
}
