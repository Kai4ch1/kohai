import SwiftUI

enum MascotState: String, CaseIterable, Sendable {
    case sleeping
    case typing
    case raisingHand
    case bowingWithWork
    case apologizing

    /// PLACEHOLDER symbols. Real art comes later; this only reserves the slot.
    var symbolName: String {
        switch self {
        case .sleeping: return "moon.zzz"
        case .typing: return "keyboard"
        case .raisingHand: return "hand.raised"
        case .bowingWithWork: return "doc.text"
        case .apologizing: return "exclamationmark.bubble"
        }
    }

    var title: String {
        switch self {
        case .sleeping: return "sleeping"
        case .typing: return "typing"
        case .raisingHand: return "raising hand"
        case .bowingWithWork: return "bowing with work"
        case .apologizing: return "apologizing"
        }
    }
}

/// Placeholder slot for the mascot at 16 / 32 / 64 pt. Decorative: the text
/// next to it carries the meaning, so it is hidden from VoiceOver.
struct MascotPlaceholder: View {
    let state: MascotState
    var size: MascotSize = .medium

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.mascot.line.color, lineWidth: max(1, size.rawValue / 32))
            Image(systemName: state.symbolName)
                .font(KohaiType.symbol(size: size.rawValue * 0.45))
                .foregroundStyle(palette.mascot.line.color)
        }
        .frame(width: size.rawValue, height: size.rawValue)
        .accessibilityHidden(true)
    }
}
