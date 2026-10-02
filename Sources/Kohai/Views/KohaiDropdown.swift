import SwiftUI

enum KohaiHint: Sendable {
    /// First launch: keep the menu bar icon visible.
    case firstRun
    /// Shown when the icon was found hidden in the menu bar overflow.
    case overflow
    /// Some found agent accounts are not connected (or point at an old app). Its button connects.
    case accountsPending(Int)
}

/// The ~360 pt menu bar dropdown: header, optional one-line hint, sessions
/// grouped by project with needs_input pinned to the top.
///
/// Keyboard: Up / Down move the selection, Return "jumps" (calls `onJump`).
/// No business logic: `onJump` / `onClear` / `onDismissHint` are closures supplied by the app.
struct KohaiDropdown: View {
    let sessions: [SessionRowModel]
    var hint: KohaiHint?
    /// false = render the first `listMaxHeight` points without a ScrollView
    /// (used for PNG snapshots, where ScrollView content is unreliable).
    var scrollable: Bool
    var onJump: (SessionRowModel) -> Void
    /// nil = no "Clear" item in the row context menu.
    var onClear: ((SessionRowModel) -> Void)?
    var onDismissHint: () -> Void

    @State private var selection: SessionRowModel.ID?
    @FocusState private var focused: Bool

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        sessions: [SessionRowModel],
        hint: KohaiHint? = nil,
        scrollable: Bool = true,
        initialSelection: SessionRowModel.ID? = nil,
        onJump: @escaping (SessionRowModel) -> Void = { _ in },
        onClear: ((SessionRowModel) -> Void)? = nil,
        onDismissHint: @escaping () -> Void = {}
    ) {
        self.sessions = sessions
        self.hint = hint
        self.scrollable = scrollable
        self.onJump = onJump
        self.onClear = onClear
        self.onDismissHint = onDismissHint
        let first = SessionGrouping.groups(sessions).first?.sessions.first?.id
        _selection = State(initialValue: initialSelection ?? first)
    }

    private var groups: [ProjectGroup] { SessionGrouping.groups(sessions) }
    private var flat: [SessionRowModel] { groups.flatMap { $0.sessions } }
    private var needsCount: Int { sessions.filter { $0.status == .needsInput }.count }

    var body: some View {
        DropdownShell(header: header) {
            if let hint {
                HintRow(
                    text: hintText(hint),
                    dismissLabel: hintButton(hint),
                    onDismiss: onDismissHint)
                KohaiSeparator()
            }
            list
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            move(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1)
            return .handled
        }
        .onKeyPress(.return) {
            jumpSelected()
        }
        .onAppear { focused = true }
    }

    // MARK: Header

    private var header: DropdownHeader {
        let n = needsCount
        let title: String
        switch n {
        case 0: title = Copy.summaryNone.text(tone)
        case 1: title = Copy.summaryOne.text(tone)
        default: title = Copy.summaryMany.text(tone, ["n": "\(n)"])
        }
        let mascot: MascotState = n > 0 ? .raisingHand : (sessions.isEmpty ? .sleeping : .typing)
        return DropdownHeader(
            title: title,
            subtitle: Copy.sessionCount.text(tone, ["n": "\(sessions.count)"]),
            mascot: mascot,
            badgeCount: n)
    }

    private func hintText(_ hint: KohaiHint) -> String {
        switch hint {
        case .firstRun: return Copy.firstRunHint.text(tone)
        case .overflow: return Copy.overflowHint.text(tone)
        case .accountsPending(let n): return Copy.hintAccountsPending.text(tone, ["n": "\(n)"])
        }
    }

    private func hintButton(_ hint: KohaiHint) -> String {
        if case .accountsPending = hint { return Copy.hintConnect.text(tone) }
        return Copy.hintDismiss.text(tone)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if scrollable {
            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .frame(maxHeight: KohaiMetrics.listMaxHeight)
                .onChange(of: selection) { _, newValue in
                    guard let newValue else { return }
                    if reduceMotion {
                        proxy.scrollTo(newValue)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newValue)
                        }
                    }
                }
            }
        } else {
            rows
                .frame(maxHeight: KohaiMetrics.listMaxHeight, alignment: .top)
                .clipped()
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                ProjectHeader(project: group.project, count: group.sessions.count)
                ForEach(group.sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: session.id == selection,
                        onJump: {
                            selection = session.id
                            onJump(session)
                        }
                    )
                    .id(session.id)
                    .contextMenu {
                        if let onClear {
                            Button(Copy.clearSession.text(tone)) { onClear(session) }
                        }
                    }
                }
            }
        }
        .padding(.bottom, KohaiSpacing.sm)
    }

    // MARK: Keyboard

    private func move(_ delta: Int) {
        let ids = flat.map { $0.id }
        guard !ids.isEmpty else { return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = delta > 0 ? ids.first : ids.last
            return
        }
        selection = ids[min(max(index + delta, 0), ids.count - 1)]
    }

    private func jumpSelected() -> KeyPress.Result {
        guard let id = selection, let session = flat.first(where: { $0.id == id }) else {
            return .ignored
        }
        onJump(session)
        return .handled
    }
}
