import SwiftUI

/// Round stamp marks. needs_input = vermilion seal with 承; done = muted grey
/// seal with 済; working = no seal, just a subtle activity indicator.
/// Status is conveyed by shape + glyph + a VoiceOver label, never by color alone.
struct StatusSeal: View {
    let status: SessionStatus

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        switch status {
        case .needsInput:
            stamp(fill: palette.seal.needsInput, glyph: "承")
        case .done:
            stamp(fill: palette.seal.done, glyph: "済")
        case .working:
            WorkingIndicator()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.label(tone))
        }
    }

    private func stamp(fill: KohaiColor, glyph: String) -> some View {
        ZStack {
            Circle().fill(fill.color)
            Circle()
                .strokeBorder(palette.seal.ring.color, lineWidth: KohaiMetrics.hairline)
                .padding(KohaiSpacing.xxs)
            Text(glyph)
                .font(KohaiType.sealGlyph)
                .foregroundStyle(palette.text.onSeal.color)
        }
        .frame(width: KohaiMetrics.sealDiameter, height: KohaiMetrics.sealDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label(tone))
    }
}

/// The only animation in the app: a short arc that turns slowly.
/// Reduce Motion: the arc stays still (the VoiceOver label still says "working").
struct WorkingIndicator: View {
    @Environment(\.kohaiPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(
                palette.text.tertiary.color,
                style: StrokeStyle(lineWidth: KohaiMetrics.workingStroke, lineCap: .round)
            )
            .frame(width: KohaiMetrics.workingDiameter, height: KohaiMetrics.workingDiameter)
            .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
            .animation(spinAnimation, value: spinning)
            .frame(width: KohaiMetrics.sealDiameter, height: KohaiMetrics.sealDiameter)
            .onAppear { spinning = true }
    }

    private var spinAnimation: Animation? {
        if reduceMotion { return nil }
        return Animation.linear(duration: 1.2).repeatForever(autoreverses: false)
    }
}
