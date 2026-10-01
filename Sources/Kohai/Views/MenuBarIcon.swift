import AppKit
import SwiftUI

// =============================================================================
// Menu bar icon. See Design/MenuBarIconSpec.md for the full spec.
//
//  - Monochrome TEMPLATE image (black + clear). The system recolors it for
//    light/dark bars, transparency and the selected state.
//  - Silhouette is a placeholder head (round head, two eye cut-outs). Final
//    mascot art replaces `MascotHeadIcon` later; the spec stays.
//  - needs_input = FILLED variant + count text. NOT color.
// =============================================================================

/// Round head. `filled`: solid silhouette, eyes cut out (needs input).
/// Not filled: outline head, eyes as dots (idle).
struct MascotHeadIcon: View {
    let filled: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let stroke = max(1.5, side * 0.085)  // >= 1.5 pt so it survives a transparent bar
            ZStack {
                if filled {
                    HeadShape().fill(color)
                    EyesShape().fill(color).blendMode(.destinationOut)
                } else {
                    HeadShape().inset(by: stroke / 2).stroke(color, lineWidth: stroke)
                    EyesShape().fill(color)
                }
            }
            .compositingGroup()
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

private struct HeadShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let head = CGRect(
            x: rect.minX + rect.width * 0.06,
            y: rect.minY + rect.height * 0.08,
            width: rect.width * 0.88,
            height: rect.height * 0.84
        ).insetBy(dx: insetAmount, dy: insetAmount)
        return Path(ellipseIn: head)
    }

    func inset(by amount: CGFloat) -> HeadShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct EyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let eyeW = w * 0.13
        let eyeH = h * 0.17
        for cx in [0.34, 0.66] {
            path.addEllipse(in: CGRect(
                x: rect.minX + w * cx - eyeW / 2,
                y: rect.minY + h * 0.50 - eyeH / 2,
                width: eyeW,
                height: eyeH))
        }
        return path
    }
}

/// Icon + optional count, as it sits in the menu bar. Use for previews; the
/// real status item uses `MenuBarIconImage` (a true template NSImage).
struct MenuBarIconLabel: View {
    let count: Int
    let color: Color

    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        HStack(spacing: KohaiSpacing.xs) {
            MascotHeadIcon(filled: count > 0, color: color)
                .frame(width: KohaiMetrics.menuBarIconCanvas, height: KohaiMetrics.menuBarIconCanvas)
            if count > 0 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(KohaiType.menuBarCount)
                    .foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            count > 0
                ? Copy.menuBarSome.text(tone, ["n": "\(count)"])
                : Copy.menuBarNone.text(tone))
    }
}

/// Builds the real template image for the status item.
@MainActor
enum MenuBarIconImage {
    static func make(filled: Bool, scale: CGFloat = 3) -> NSImage? {
        let content = MascotHeadIcon(
            filled: filled,
            color: KohaiPalette.dark.icon.templateInk.color
        )
        .frame(width: KohaiMetrics.menuBarIconCanvas, height: KohaiMetrics.menuBarIconCanvas)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Sheet for review: both variants on dark / light / mid bars, 1x and 4x.
struct MenuBarIconSheet: View {
    @Environment(\.kohaiPalette) private var palette

    private struct Bar {
        let name: String
        let background: KohaiColor
        let icon: KohaiColor
    }

    private var bars: [Bar] {
        [
            Bar(name: "dark bar", background: palette.preview.barDark, icon: palette.preview.iconOnDarkBar),
            Bar(name: "light bar", background: palette.preview.barLight, icon: palette.preview.iconOnLightBar),
            Bar(name: "mid bar (worst case)", background: palette.preview.barMid, icon: palette.preview.iconOnLightBar),
        ]
    }

    private let counts = [0, 2, 12]

    var body: some View {
        VStack(alignment: .leading, spacing: KohaiSpacing.lg) {
            ForEach(bars, id: \.name) { bar in
                VStack(alignment: .leading, spacing: KohaiSpacing.xs) {
                    Text(bar.name)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.tertiary.color)
                    HStack(spacing: KohaiSpacing.xl) {
                        ForEach(counts, id: \.self) { count in
                            MenuBarIconLabel(count: count, color: bar.icon.color)
                        }
                        Spacer(minLength: 0)
                        ForEach(counts, id: \.self) { count in
                            MenuBarIconLabel(count: count, color: bar.icon.color)
                                .scaleEffect(3, anchor: .center)
                                .frame(width: 96, height: 60)
                        }
                    }
                    .padding(.horizontal, KohaiSpacing.md)
                    .padding(.vertical, KohaiSpacing.sm)
                    .background(bar.background.color)
                }
            }
        }
        .frame(width: 560)
    }
}

/// Sheet for review: 5 mascot states x 3 slot sizes.
struct MascotSheet: View {
    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: KohaiSpacing.xl, verticalSpacing: KohaiSpacing.lg) {
            GridRow {
                ForEach(MascotState.allCases, id: \.self) { state in
                    Text(state.title)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.secondary.color)
                }
            }
            ForEach(MascotSize.allCases, id: \.self) { size in
                GridRow {
                    ForEach(MascotState.allCases, id: \.self) { state in
                        MascotPlaceholder(state: state, size: size)
                    }
                }
            }
        }
        .padding(KohaiSpacing.xl)
    }
}
