import SwiftUI

/// Hairline between regions.
struct KohaiSeparator: View {
    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.surface.separator.color)
            .frame(height: KohaiMetrics.hairline)
            .accessibilityHidden(true)
    }
}

/// Mascot slot + summary ("2 need you, senpai") + needs-input count badge.
/// The badge is vermilion because it IS the needs-input signal; it also
/// carries the number, so it never relies on color alone.
struct DropdownHeader: View {
    let title: String
    var subtitle: String? = nil
    var mascot: MascotState? = nil
    var badgeCount: Int = 0

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        HStack(spacing: KohaiSpacing.md) {
            if let mascot {
                MascotPlaceholder(state: mascot, size: .medium)
            }
            VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                Text(title)
                    .font(KohaiType.headerTitle)
                    .foregroundStyle(palette.text.primary.color)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.secondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: KohaiSpacing.sm)
            if badgeCount > 0 {
                Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                    .font(KohaiType.badge)
                    .foregroundStyle(palette.text.onSeal.color)
                    .padding(.horizontal, KohaiSpacing.sm)
                    .padding(.vertical, KohaiSpacing.xxs)
                    .frame(minWidth: KohaiMetrics.sealDiameter)
                    .background(Capsule().fill(palette.seal.needsInput.color))
                    .accessibilityHidden(true)  // the summary text already says the number
            }
        }
        .padding(KohaiSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Fixed-width shell shared by the session list and every state screen.
/// It paints NO background: the menu bar window supplies the system material.
struct DropdownShell<Content: View>: View {
    let header: DropdownHeader
    let content: Content

    init(header: DropdownHeader, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            KohaiSeparator()
            content
        }
        .frame(width: KohaiMetrics.dropdownWidth)
    }
}

/// One-line dismissible hint (first run, overflow).
struct HintRow: View {
    let text: String
    let dismissLabel: String
    var onDismiss: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        HStack(spacing: KohaiSpacing.sm) {
            Text(text)
                .font(KohaiType.hint)
                .foregroundStyle(palette.text.secondary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: KohaiSpacing.sm)
            Button(action: onDismiss) {
                Text(dismissLabel)
                    .font(KohaiType.hint)
                    .underline()
                    .foregroundStyle(palette.text.primary.color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KohaiSpacing.md)
        .padding(.vertical, KohaiSpacing.sm)
    }
}
