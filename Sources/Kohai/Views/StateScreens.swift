import SwiftUI

enum KohaiStateKind: String, CaseIterable, Sendable {
    case empty
    case hooksNotInstalled
    case socketError
    case automationDenied
}

/// Message block used by every non-list state: mascot (64 pt slot), title,
/// one explanatory line, optional mono detail (a path), optional link-style action.
struct StateMessage: View {
    let mascot: MascotState
    let title: String
    let message: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var onAction: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        VStack(spacing: KohaiSpacing.md) {
            MascotPlaceholder(state: mascot, size: .large)

            VStack(spacing: KohaiSpacing.xs) {
                Text(title)
                    .font(KohaiType.rowTitle)
                    .foregroundStyle(palette.text.primary.color)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .multilineTextAlignment(.center)
            }

            if let detail {
                Text(detail)
                    .font(KohaiType.monoPath)
                    .foregroundStyle(palette.text.tertiary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(KohaiType.body)
                        .underline()
                        .foregroundStyle(palette.text.primary.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(KohaiSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// empty / hooks not installed / socket error / Automation permission denied.
struct KohaiStateDropdown: View {
    let kind: KohaiStateKind
    /// Mono detail line for `.socketError` (the socket path).
    var detail: String? = nil
    var onAction: () -> Void = {}

    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        DropdownShell(header: header) {
            stateBody(for: kind)
        }
    }

    private var header: DropdownHeader {
        switch kind {
        case .empty:
            return DropdownHeader(title: Copy.summaryNone.text(tone))
        default:
            return DropdownHeader(title: Copy.appName.text(tone))
        }
    }

    @ViewBuilder
    private func stateBody(for kind: KohaiStateKind) -> some View {
        switch kind {
        case .empty:
            StateMessage(
                mascot: .sleeping,
                title: Copy.emptyTitle.text(tone),
                message: Copy.emptyBody.text(tone))
        case .hooksNotInstalled:
            StateMessage(
                mascot: .apologizing,
                title: Copy.hooksTitle.text(tone),
                message: Copy.hooksBody.text(tone),
                actionTitle: Copy.hooksAction.text(tone),
                onAction: onAction)
        case .socketError:
            StateMessage(
                mascot: .apologizing,
                title: Copy.socketTitle.text(tone),
                message: Copy.socketBody.text(tone),
                detail: detail ?? "~/.kohai/kohai.sock",  // placeholder path for the preview
                actionTitle: Copy.socketAction.text(tone),
                onAction: onAction)
        case .automationDenied:
            StateMessage(
                mascot: .raisingHand,
                title: Copy.automationTitle.text(tone),
                message: Copy.automationBody.text(tone),
                actionTitle: Copy.automationAction.text(tone),
                onAction: onAction)
        }
    }
}

/// Schematic of the notification that MUST accompany every needs_input, so a
/// session that needs the user is still surfaced when macOS 27 hides the status
/// item in the menu bar overflow. The real banner is drawn by the system; this
/// only previews the copy.
struct NotificationBannerMock: View {
    let project: String
    let agent: String
    let session: String

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: KohaiSpacing.xs) {
            Text(Copy.notificationMockLabel.text(tone))
                .font(KohaiType.secondary)
                .foregroundStyle(palette.text.tertiary.color)
            HStack(alignment: .top, spacing: KohaiSpacing.md) {
                MascotPlaceholder(state: .raisingHand, size: .medium)
                VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                    Text(Copy.notificationTitle.text(tone, ["project": project]))
                        .font(KohaiType.rowTitle)
                        .foregroundStyle(palette.text.primary.color)
                        .lineLimit(2)
                    Text(Copy.notificationBody.text(tone, ["agent": agent, "session": session]))
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.secondary.color)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(KohaiSpacing.md)
            .background(.regularMaterial)
        }
        .frame(width: KohaiMetrics.dropdownWidth)
        .accessibilityElement(children: .combine)
    }
}
