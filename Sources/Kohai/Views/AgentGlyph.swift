import SwiftUI

/// The one icon on a row. Generic SF Symbols, no brand marks.
struct AgentGlyph: View {
    let kind: AgentKind

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(KohaiType.symbol(size: 13))
            .foregroundStyle(palette.text.secondary.color)
            .frame(width: KohaiMetrics.agentGlyph, height: KohaiMetrics.agentGlyph)
            .accessibilityLabel(kind.displayName(tone))
    }
}
