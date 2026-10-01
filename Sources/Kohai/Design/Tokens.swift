import SwiftUI

// =============================================================================
// Kohai design tokens: "Senpai's desk"
//
// SINGLE SOURCE OF TRUTH. This is the only file allowed to contain color
// values, spacing numbers, font definitions and size metrics.
//
//  - Dark theme only for now. Light values slot into `KohaiPalette.resolved`.
//  - Exactly ONE accent: hanko vermilion (`seal.needsInput`). It is used ONLY
//    for "needs input" (status seal and the count badge). Nothing else.
//  - Corner radii are NOT tokens: they come from the system (system materials,
//    system controls, Capsule/Circle shapes). Do not add radius tokens.
//  - Backgrounds are NOT tokens: the menu bar window supplies the system
//    material. The `preview` group exists only to stand in for that material
//    in previews and PNG snapshots.
// =============================================================================

// MARK: - Color value

/// An sRGB color stored as plain numbers so it can be drawn AND measured
/// (contrast tests read `hex` directly).
struct KohaiColor: Sendable, Equatable {
    let hex: UInt32
    let opacity: Double

    init(_ hex: UInt32, opacity: Double = 1) {
        self.hex = hex
        self.opacity = opacity
    }

    var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    var blue: Double { Double(hex & 0xFF) / 255 }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// WCAG relative luminance of the opaque color.
    var relativeLuminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// WCAG contrast ratio between two opaque colors (1...21).
    func contrast(against other: KohaiColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Hue (degrees 0..<360), saturation and brightness (HSV) for palette tests.
    var hsv: (hue: Double, saturation: Double, value: Double) {
        let mx = max(red, green, blue)
        let mn = min(red, green, blue)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == red {
                h = (green - blue) / d
                if h < 0 { h += 6 }
            } else if mx == green {
                h = (blue - red) / d + 2
            } else {
                h = (red - green) / d + 4
            }
            h *= 60
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
}

// MARK: - Palette

struct KohaiPalette: Sendable {

    struct TextColors: Sendable {
        /// Washi white. Titles, primary content.
        let primary: KohaiColor
        /// Washi grey. Account, secondary lines.
        let secondary: KohaiColor
        /// Muted washi. Last message, timers, group headers. Still >= 4.5:1.
        let tertiary: KohaiColor
        /// Sumi ink. Glyphs drawn ON a seal or badge fill.
        let onSeal: KohaiColor
    }

    struct SealColors: Sendable {
        /// Hanko vermilion. THE accent. needs_input only.
        let needsInput: KohaiColor
        /// Muted grey seal. done.
        let done: KohaiColor
        /// Thin inner ring of the stamp.
        let ring: KohaiColor
    }

    struct SurfaceColors: Sendable {
        /// Hairline between header / groups.
        let separator: KohaiColor
        /// Keyboard-selected row. Low-opacity washi over the system material.
        let rowHighlight: KohaiColor
    }

    struct MascotColors: Sendable {
        let line: KohaiColor
    }

    struct IconColors: Sendable {
        /// Template images are black + clear; the system recolors them.
        let templateInk: KohaiColor
    }

    /// Stand-ins for the system material. PREVIEWS AND SNAPSHOTS ONLY.
    struct PreviewColors: Sendable {
        /// Typical dark material.
        let materialNominal: KohaiColor
        /// Worst case: a bright wallpaper lifts the material.
        let materialLifted: KohaiColor
        /// Surround so the window edge is visible in PNGs.
        let stage: KohaiColor
        /// Menu bar backdrops for the icon sheet (opaque approximations).
        let barDark: KohaiColor
        let barLight: KohaiColor
        let barMid: KohaiColor
        /// Icon color the system would pick on each bar.
        let iconOnDarkBar: KohaiColor
        let iconOnLightBar: KohaiColor
    }

    let text: TextColors
    let seal: SealColors
    let surface: SurfaceColors
    let mascot: MascotColors
    let icon: IconColors
    let preview: PreviewColors
    /// 8 desaturated Japanese traditional tones. Hue band 240-320 is forbidden (enforced by TokenTests).
    let projectStripes: [KohaiColor]

    /// Deterministic (FNV-1a) so a project keeps its color across launches.
    /// `hashValue` is randomized per process and must not be used here.
    func stripe(forProject key: String) -> KohaiColor {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return projectStripes[Int(hash % UInt64(projectStripes.count))]
    }
}

extension KohaiPalette {

    private static let ink = KohaiColor(0x1A1613)

    private static let stripes: [KohaiColor] = [
        KohaiColor(0x8A9A5B),  // matcha
        KohaiColor(0xB8944A),  // kincha
        KohaiColor(0x5C9AA3),  // asagi
        KohaiColor(0x9A9A9C),  // nezumi
        KohaiColor(0xA68B76),  // kakishibu (kept desaturated so it never reads as vermilion)
        KohaiColor(0xD9A441),  // yamabuki
        KohaiColor(0x7FA8C2),  // wasurenagusa
        KohaiColor(0xD4A0AB),  // sakura (muted)
    ]

    private static let previewColors = PreviewColors(
        materialNominal: KohaiColor(0x262628),
        materialLifted: KohaiColor(0x3C3C3E),
        stage: KohaiColor(0x111112),
        barDark: KohaiColor(0x1A1A1C),
        barLight: KohaiColor(0xE8E6E1),
        barMid: KohaiColor(0x8A8A8A),
        iconOnDarkBar: KohaiColor(0xF1EEE7),
        iconOnLightBar: KohaiColor(0x1A1613)
    )

    /// Dark theme, default contrast.
    static let dark = KohaiPalette(
        text: TextColors(
            primary: KohaiColor(0xF1EEE7),
            secondary: KohaiColor(0xCBC7BD),
            tertiary: KohaiColor(0xB9B5AB),
            onSeal: ink
        ),
        seal: SealColors(
            needsInput: KohaiColor(0xEE6048),
            done: KohaiColor(0xA19E97),
            ring: KohaiColor(0x1A1613, opacity: 0.45)
        ),
        surface: SurfaceColors(
            separator: KohaiColor(0xF1EEE7, opacity: 0.12),
            rowHighlight: KohaiColor(0xF1EEE7, opacity: 0.10)
        ),
        mascot: MascotColors(line: KohaiColor(0xCBC7BD)),
        icon: IconColors(templateInk: KohaiColor(0x000000)),
        preview: previewColors,
        projectStripes: stripes
    )

    /// Dark theme with the system "Increase Contrast" setting on.
    static let darkIncreasedContrast = KohaiPalette(
        text: TextColors(
            primary: KohaiColor(0xFAF8F3),
            secondary: KohaiColor(0xE4E0D7),
            tertiary: KohaiColor(0xD2CEC4),
            onSeal: ink
        ),
        seal: SealColors(
            needsInput: KohaiColor(0xF2705A),
            done: KohaiColor(0xB4B1AA),
            ring: KohaiColor(0x1A1613, opacity: 0.60)
        ),
        surface: SurfaceColors(
            separator: KohaiColor(0xFAF8F3, opacity: 0.35),
            rowHighlight: KohaiColor(0xFAF8F3, opacity: 0.18)
        ),
        mascot: MascotColors(line: KohaiColor(0xE4E0D7)),
        icon: IconColors(templateInk: KohaiColor(0x000000)),
        preview: previewColors,
        projectStripes: stripes
    )

    /// The one place that maps system appearance settings to a palette.
    /// LIGHT THEME LATER: add `static let light` / `lightIncreasedContrast`
    /// and branch on `scheme` here. Views never need to change.
    static func resolved(scheme: ColorScheme, contrast: ColorSchemeContrast) -> KohaiPalette {
        contrast == .increased ? .darkIncreasedContrast : .dark
    }
}

// MARK: - Environment

private struct KohaiPaletteKey: EnvironmentKey {
    static let defaultValue: KohaiPalette = .dark
}

extension EnvironmentValues {
    var kohaiPalette: KohaiPalette {
        get { self[KohaiPaletteKey.self] }
        set { self[KohaiPaletteKey.self] = newValue }
    }
}

private struct KohaiContrastOverrideKey: EnvironmentKey {
    static let defaultValue: ColorSchemeContrast? = nil
}

extension EnvironmentValues {
    /// PREVIEWS AND SNAPSHOTS ONLY: forces a contrast level so the Increase
    /// Contrast palette can be rendered without flipping the system setting.
    var kohaiContrastOverride: ColorSchemeContrast? {
        get { self[KohaiContrastOverrideKey.self] }
        set { self[KohaiContrastOverrideKey.self] = newValue }
    }
}

private struct KohaiThemeModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.kohaiContrastOverride) private var contrastOverride

    func body(content: Content) -> some View {
        content
            .environment(\.kohaiPalette, .resolved(scheme: .dark, contrast: contrastOverride ?? systemContrast))
            .preferredColorScheme(.dark)  // dark-first; remove when light theme lands
    }
}

extension View {
    /// Apply once at the root of the dropdown (and the preview stage).
    func kohaiThemed() -> some View {
        modifier(KohaiThemeModifier())
    }
}

// MARK: - Spacing

enum KohaiSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Metrics (sizes, not radii)

enum KohaiMetrics {
    static let dropdownWidth: CGFloat = 360
    /// Height of the scrolling list before it scrolls.
    static let listMaxHeight: CGFloat = 440
    /// Per-project left stripe.
    static let stripeWidth: CGFloat = 3
    static let sealDiameter: CGFloat = 18
    static let agentGlyph: CGFloat = 16
    /// Subtle activity indicator for `working` (a short arc, no seal).
    static let workingDiameter: CGFloat = 12
    static let workingStroke: CGFloat = 1.5
    static let hairline: CGFloat = 1
    /// Right column (seal + timer) width so timers right-align across rows.
    static let statusColumnWidth: CGFloat = 52
    /// Menu bar icon canvas. The macOS menu bar is 24 pt tall (Apple HIG).
    static let menuBarIconCanvas: CGFloat = 18
}

/// Mascot placeholder slot sizes (pt).
enum MascotSize: CGFloat, CaseIterable, Sendable {
    case small = 16
    case medium = 32
    case large = 64
}

// MARK: - Type

/// System SF Pro for UI text; SF Mono (monospaced digits) for paths, session
/// IDs and timers. No custom or web fonts.
enum KohaiType {
    static let headerTitle = Font.system(.headline)
    static let rowTitle = Font.system(.body, weight: .medium)
    static let secondary = Font.system(.caption)
    static let groupHeader = Font.system(.caption, weight: .semibold)
    static let body = Font.system(.callout)
    static let hint = Font.system(.caption)
    static let badge = Font.system(.caption, weight: .bold).monospacedDigit()
    /// Timers.
    static let mono = Font.system(.caption, design: .monospaced).monospacedDigit()
    /// Paths and session IDs.
    static let monoPath = Font.system(.caption, design: .monospaced)
    /// Kanji inside a seal (承 / 済). Falls back to the system CJK face.
    static let sealGlyph = Font.system(size: 11, weight: .bold)
    /// Count next to the menu bar icon.
    static let menuBarCount = Font.system(size: 12, weight: .semibold).monospacedDigit()

    /// Symbol size inside the agent glyph / mascot placeholders.
    static func symbol(size: CGFloat) -> Font {
        Font.system(size: size, weight: .regular)
    }
}
