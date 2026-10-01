import SwiftUI

/// One session. Layout, left to right:
/// 3pt project stripe | agent glyph | name / account / last message | seal + timer.
/// Icons: the agent glyph only. No card around the row: the selection
/// highlight is the only surface it ever gets.
struct SessionRow: View {
    let session: SessionRowModel
    var isSelected: Bool = false
    var onJump: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        Button(action: onJump) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(Copy.jumpHint.text(tone))
        .accessibilityAddTraits(traits)
        .help("\(session.project) / \(session.sessionName)")
    }

    private var content: some View {
        HStack(alignment: .top, spacing: KohaiSpacing.sm) {
            AgentGlyph(kind: session.agent)

            VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                Text(session.sessionName)
                    .font(KohaiType.rowTitle)
                    .foregroundStyle(palette.text.primary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondaryLine)
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(session.lastMessage)
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.tertiary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: KohaiSpacing.sm)

            VStack(alignment: .trailing, spacing: KohaiSpacing.xs) {
                StatusSeal(status: session.status)
                Text(TimeInStatus.short(session.secondsInStatus))
                    .font(KohaiType.mono)
                    .foregroundStyle(palette.text.tertiary.color)
                    .lineLimit(1)
            }
            .frame(width: KohaiMetrics.statusColumnWidth, alignment: .trailing)
        }
        .padding(.leading, KohaiSpacing.md + KohaiMetrics.stripeWidth)
        .padding(.trailing, KohaiSpacing.md)
        .padding(.vertical, KohaiSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                Rectangle().fill(palette.surface.rowHighlight.color)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(palette.stripe(forProject: session.project).color)
                .frame(width: KohaiMetrics.stripeWidth)
        }
        .contentShape(Rectangle())
    }

    private var secondaryLine: String {
        var parts: [String] = [session.account ?? Copy.noAccount.text(tone)]
        if case .unknown(let raw) = session.agent {
            let name = Copy.unknownAgent.text(tone)
            parts.append(raw.isEmpty ? name : "\(name) (\(raw))")
        }
        return parts.joined(separator: " · ")
    }

    private var traits: AccessibilityTraits {
        isSelected ? [.isButton, .isSelected] : [.isButton]
    }

    private var spokenLabel: String {
        var parts: [String] = [
            session.sessionName,
            session.project,
            session.agent.displayName(tone),
            session.status.label(tone),
            Copy.inStatusFor.text(tone, ["time": TimeInStatus.spoken(session.secondsInStatus)]),
        ]
        if let account = session.account { parts.append(account) }
        parts.append(session.lastMessage)
        return parts.joined(separator: ", ")
    }
}

/// Group label: project name only. Long names truncate in the middle.
struct ProjectHeader: View {
    let project: String
    let count: Int

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        HStack(spacing: KohaiSpacing.sm) {
            Text(project)
                .font(KohaiType.groupHeader)
                .foregroundStyle(palette.text.tertiary.color)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: KohaiSpacing.sm)
            Text("\(count)")
                .font(KohaiType.mono)
                .foregroundStyle(palette.text.tertiary.color)
        }
        .padding(.horizontal, KohaiSpacing.md)
        .padding(.top, KohaiSpacing.md)
        .padding(.bottom, KohaiSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project), \(count)")
        .accessibilityAddTraits(.isHeader)
        .help(project)
    }
}
