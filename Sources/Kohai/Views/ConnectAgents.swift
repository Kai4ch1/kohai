import SwiftUI

// =============================================================================
// PRESENTATION-ONLY: the app maps its agent accounts to these. No file access
// here; connecting and disconnecting are closures supplied by the app.
// =============================================================================

enum AccountConnectionState: Hashable, Sendable {
    case notConnected
    case connected
    case needsUpdate
    case unreadable(String)

    /// Can be ticked for "Connect".
    var isConnectable: Bool { self == .notConnected || self == .needsUpdate }
}

struct AccountRowModel: Identifiable, Hashable, Sendable {
    let id: String
    let agent: AgentKind
    /// Config folder as shown, with the home folder shortened to "~".
    let path: String
    let state: AccountConnectionState
}

/// Asks before Kohai writes anything: every found account with a checkbox,
/// connected ones with Disconnect, broken ones explained and left alone.
struct ConnectAgentsDropdown: View {
    let accounts: [AccountRowModel]
    /// One line under the intro: the restart reminder after connecting, or an error.
    var notice: String? = nil
    var onConnect: ([AccountRowModel.ID]) -> Void = { _ in }
    var onDisconnect: (AccountRowModel.ID) -> Void = { _ in }
    var onAddFolder: () -> Void = {}
    /// nil = this is the only thing Kohai can show yet, so there is nowhere to go back to.
    var onDone: (() -> Void)? = nil

    @State private var selection: Set<AccountRowModel.ID>

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    init(
        accounts: [AccountRowModel],
        notice: String? = nil,
        onConnect: @escaping ([AccountRowModel.ID]) -> Void = { _ in },
        onDisconnect: @escaping (AccountRowModel.ID) -> Void = { _ in },
        onAddFolder: @escaping () -> Void = {},
        onDone: (() -> Void)? = nil
    ) {
        self.accounts = accounts
        self.notice = notice
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onAddFolder = onAddFolder
        self.onDone = onDone
        // Everything that can be connected starts ticked: the common case is "yes, all of them".
        _selection = State(initialValue: Set(accounts.filter { $0.state.isConnectable }.map(\.id)))
    }

    /// Ticked rows that are still connectable (a row can change state under the selection).
    private var chosen: [AccountRowModel.ID] {
        accounts.filter { $0.state.isConnectable && selection.contains($0.id) }.map(\.id)
    }

    var body: some View {
        DropdownShell(header: DropdownHeader(title: Copy.connectTitle.text(tone), mascot: .raisingHand)) {
            VStack(alignment: .leading, spacing: KohaiSpacing.sm) {
                Text(accounts.isEmpty ? Copy.connectNoneFound.text(tone) : Copy.connectBody.text(tone))
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let notice {
                    Text(notice)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.primary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, KohaiSpacing.lg)
            .padding(.vertical, KohaiSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !accounts.isEmpty {
                KohaiSeparator()
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        AccountRow(
                            account: account,
                            isSelected: Binding(
                                get: { selection.contains(account.id) },
                                set: { on in
                                    if on { selection.insert(account.id) } else { selection.remove(account.id) }
                                }),
                            onDisconnect: { onDisconnect(account.id) })
                    }
                }
                .padding(.vertical, KohaiSpacing.xs)
            }

            KohaiSeparator()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: KohaiSpacing.md) {
            LinkButton(title: Copy.connectAddFolder.text(tone), action: onAddFolder)
            Spacer(minLength: KohaiSpacing.sm)
            if let onDone, chosen.isEmpty {
                Button(Copy.connectDone.text(tone), action: onDone)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(Copy.connectAction.text(tone, ["n": "\(chosen.count)"])) { onConnect(chosen) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, KohaiSpacing.lg)
        .padding(.vertical, KohaiSpacing.md)
    }
}

private struct AccountRow: View {
    let account: AccountRowModel
    @Binding var isSelected: Bool
    let onDisconnect: () -> Void

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        HStack(alignment: .top, spacing: KohaiSpacing.sm) {
            Group {
                if account.state.isConnectable {
                    // Drawn, not an AppKit checkbox: same look in the menu and in PNG snapshots.
                    Button { isSelected.toggle() } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(KohaiType.symbol(size: 14))
                            .foregroundStyle(palette.text.primary.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(account.path)
                    .accessibilityValue(isSelected ? "selected" : "not selected")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                } else {
                    Color.clear
                }
            }
            .frame(width: KohaiMetrics.agentGlyph, height: KohaiMetrics.agentGlyph)

            AgentGlyph(kind: account.agent)

            VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                Text(account.path)
                    .font(KohaiType.monoPath)
                    .foregroundStyle(palette.text.primary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .lineLimit(2)
            }

            Spacer(minLength: KohaiSpacing.sm)

            if account.state == .connected || account.state == .needsUpdate {
                LinkButton(title: Copy.accountDisconnect.text(tone), action: onDisconnect)
            }
        }
        .padding(.horizontal, KohaiSpacing.lg)
        .padding(.vertical, KohaiSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        let agent = account.agent.displayName(tone)
        let state: String
        switch account.state {
        case .notConnected: state = Copy.accountNotConnected.text(tone)
        case .connected: state = Copy.accountConnected.text(tone)
        case .needsUpdate: state = Copy.accountNeedsUpdate.text(tone)
        case .unreadable(let reason): state = Copy.accountUnreadable.text(tone, ["reason": reason])
        }
        return "\(agent) · \(state)"
    }
}

/// Underlined text button, the style every secondary action in the dropdown uses.
struct LinkButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KohaiType.hint)
                .underline()
                .foregroundStyle(palette.text.primary.color)
        }
        .buttonStyle(.plain)
    }
}

/// Bottom row under the list and the empty state: way back to the connect screen, and Quit.
struct DropdownFooter: View {
    var onAgents: () -> Void = {}
    var onQuit: () -> Void = {}

    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        VStack(spacing: 0) {
            KohaiSeparator()
            HStack {
                LinkButton(title: Copy.footerAgents.text(tone), action: onAgents)
                Spacer()
                LinkButton(title: Copy.quit.text(tone), action: onQuit)
            }
            .padding(.horizontal, KohaiSpacing.md)
            .padding(.vertical, KohaiSpacing.sm)
        }
        .frame(width: KohaiMetrics.dropdownWidth)
    }
}
