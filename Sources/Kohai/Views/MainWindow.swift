import SwiftUI

// =============================================================================
// Main window columns: spaces | sessions grouped by project | detail.
// PRESENTATION-ONLY, like the dropdown. Each column is plain SwiftUI so it can
// be rendered to PNG; the app wraps them in a NavigationSplitView.
// =============================================================================

enum SpaceSelection: Hashable, Sendable {
    case all
    case unsorted
    case space(UUID)
}

struct SpaceItemModel: Identifiable, Hashable, Sendable {
    let id: SpaceSelection
    let name: String
    let symbol: String
    /// nil for All / Unsorted.
    let tone: LabelTone?
    let sessionCount: Int
    let needsInputCount: Int
    var muted: Bool = false
}

struct SessionDetailModel: Hashable, Sendable {
    let row: SessionRowModel
    /// Project folder, home shortened to "~".
    let folder: String
    let gitRemote: String?
    let spaceName: String
    let spaceSymbol: String
    let spaceTone: LabelTone?
    /// "Terminal.app · /dev/ttys004", "Claude app", …
    let terminal: String
}

// MARK: Sidebar

struct SpacesSidebar: View {
    let items: [SpaceItemModel]
    @Binding var selection: SpaceSelection
    var onNewSpace: () -> Void = {}
    var onEdit: (UUID) -> Void = { _ in }
    var onToggleMute: (UUID) -> Void = { _ in }
    var onMove: (UUID, Int) -> Void = { _, _ in }
    /// false = no ScrollView (PNG snapshots).
    var scrollable: Bool = true

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    private var fixed: [SpaceItemModel] { items.filter { if case .space = $0.id { false } else { true } } }
    private var spaces: [SpaceItemModel] { items.filter { if case .space = $0.id { true } else { false } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if scrollable {
                ScrollView { list }
            } else {
                list
                Spacer(minLength: 0)
            }
            KohaiSeparator()
            LinkButton(title: Copy.sidebarNewSpace.text(tone), action: onNewSpace)
                .padding(.horizontal, KohaiSpacing.md)
                .padding(.vertical, KohaiSpacing.sm)
        }
        .frame(width: KohaiMetrics.sidebarWidth)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
            ForEach(fixed) { row($0) }
            sectionTitle(Copy.sidebarSpaces.text(tone))
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .contextMenu { spaceMenu(item, index: index) }
            }
        }
        .padding(KohaiSpacing.sm)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(KohaiType.groupHeader)
            .foregroundStyle(palette.text.tertiary.color)
            .padding(.horizontal, KohaiSpacing.sm)
            .padding(.top, KohaiSpacing.md)
            .padding(.bottom, KohaiSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: SpaceItemModel) -> some View {
        let isSelected = item.id == selection
        return Button { selection = item.id } label: {
            HStack(spacing: KohaiSpacing.sm) {
                Image(systemName: item.symbol)
                    .font(KohaiType.symbol(size: 13))
                    .foregroundStyle((item.tone.map { palette.label($0) } ?? palette.text.secondary).color)
                    .frame(width: KohaiMetrics.agentGlyph)
                Text(item.name)
                    .font(KohaiType.body)
                    .foregroundStyle(palette.text.primary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if item.muted {
                    Image(systemName: "bell.slash")
                        .font(KohaiType.symbol(size: 10))
                        .foregroundStyle(palette.text.tertiary.color)
                        .accessibilityLabel(Copy.spaceMutedLabel.text(tone))
                }
                Spacer(minLength: KohaiSpacing.xs)
                if item.needsInputCount > 0 {
                    // Vermilion only because it IS the needs-input count, as in the dropdown header.
                    Text("\(item.needsInputCount)")
                        .font(KohaiType.badge)
                        .foregroundStyle(palette.text.onSeal.color)
                        .padding(.horizontal, KohaiSpacing.xs + KohaiSpacing.xxs)
                        .background(Capsule().fill(palette.seal.needsInput.color))
                } else if item.sessionCount > 0 {
                    Text("\(item.sessionCount)")
                        .font(KohaiType.mono)
                        .foregroundStyle(palette.text.tertiary.color)
                }
            }
            .padding(.horizontal, KohaiSpacing.sm)
            .padding(.vertical, KohaiSpacing.xs + KohaiSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: KohaiSpacing.xs, style: .continuous)
                        .fill(palette.surface.rowHighlight.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private func spaceMenu(_ item: SpaceItemModel, index: Int) -> some View {
        if case .space(let id) = item.id {
            Button(Copy.spaceEdit.text(tone)) { onEdit(id) }
            Button(item.muted ? Copy.spaceUnmute.text(tone) : Copy.spaceMute.text(tone)) { onToggleMute(id) }
            Divider()
            Button(Copy.spaceMoveUp.text(tone)) { onMove(id, -1) }
                .disabled(index == 0)
            Button(Copy.spaceMoveDown.text(tone)) { onMove(id, 1) }
                .disabled(index == spaces.count - 1)
        }
    }
}

// MARK: Sessions

struct SessionColumn: View {
    let title: String
    let sessions: [SessionRowModel]
    @Binding var selection: SessionRowModel.ID?
    var onJump: (SessionRowModel) -> Void = { _ in }
    /// false = no ScrollView (PNG snapshots).
    var scrollable: Bool = true

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone
    @FocusState private var focused: Bool

    private var groups: [ProjectGroup] { SessionGrouping.groups(sessions) }
    private var flat: [SessionRowModel] { groups.flatMap(\.sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(KohaiType.headerTitle)
                    .foregroundStyle(palette.text.primary.color)
                    .lineLimit(1)
                Spacer()
                Text(Copy.sessionCount.text(tone, ["n": "\(sessions.count)"]))
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
            }
            .padding(KohaiSpacing.lg)
            KohaiSeparator()
            if sessions.isEmpty {
                StateMessage(
                    mascot: .sleeping,
                    title: Copy.sessionsEmptyTitle.text(tone),
                    message: Copy.sessionsEmptyBody.text(tone))
                Spacer(minLength: 0)
            } else if scrollable {
                ScrollView { rows }
            } else {
                rows
                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: KohaiMetrics.sessionColumnWidth)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            guard let id = selection, let row = flat.first(where: { $0.id == id }) else { return .ignored }
            onJump(row)
            return .handled
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
                            focused = true
                        },
                        actionHint: Copy.detailSelectHint.text(tone))
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onJump(session) })
                }
            }
        }
        .padding(.bottom, KohaiSpacing.sm)
    }

    private func move(_ delta: Int) {
        let ids = flat.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = delta > 0 ? ids.first : ids.last
            return
        }
        selection = ids[min(max(index + delta, 0), ids.count - 1)]
    }
}

// MARK: Detail

struct SessionDetail: View {
    let model: SessionDetailModel?
    var onJump: () -> Void = {}
    var onClear: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                VStack {
                    Spacer()
                    StateMessage(mascot: .sleeping, title: Copy.detailEmpty.text(tone), message: "")
                    Spacer()
                }
            }
        }
        .frame(minWidth: KohaiMetrics.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(_ model: SessionDetailModel) -> some View {
        let row = model.row
        return VStack(alignment: .leading, spacing: KohaiSpacing.lg) {
            HStack(alignment: .top, spacing: KohaiSpacing.md) {
                AgentGlyph(kind: row.agent)
                VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                    Text(row.sessionName)
                        .font(KohaiType.headerTitle)
                        .foregroundStyle(palette.text.primary.color)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: KohaiSpacing.xs) {
                        Text(row.status.label(tone))
                        Text("·")
                        Text(TimeInStatus.short(row.secondsInStatus)).font(KohaiType.mono)
                    }
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(row.status.label(tone)), \(Copy.inStatusFor.text(tone, ["time": TimeInStatus.spoken(row.secondsInStatus)]))")
                }
                Spacer(minLength: KohaiSpacing.sm)
                StatusSeal(status: row.status)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: KohaiSpacing.md, verticalSpacing: KohaiSpacing.sm) {
                field(Copy.detailProject.text(tone)) { plain(row.project) }
                field(Copy.detailFolder.text(tone)) { mono(model.folder) }
                field(Copy.detailRemote.text(tone)) { mono(model.gitRemote ?? Copy.detailNoRemote.text(tone)) }
                field(Copy.detailAccount.text(tone)) {
                    labelled(row.account ?? Copy.noAccount.text(tone), symbol: nil, tone: row.accountTone)
                }
                field(Copy.detailSpace.text(tone)) {
                    labelled(model.spaceName, symbol: model.spaceSymbol, tone: model.spaceTone)
                }
                field(Copy.detailTerminal.text(tone)) { plain(model.terminal) }
            }

            if !row.lastMessage.isEmpty {
                VStack(alignment: .leading, spacing: KohaiSpacing.xs) {
                    Text(Copy.detailLastMessage.text(tone))
                        .font(KohaiType.groupHeader)
                        .foregroundStyle(palette.text.tertiary.color)
                    Text(row.lastMessage)
                        .font(KohaiType.body)
                        .foregroundStyle(palette.text.primary.color)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: KohaiSpacing.md) {
                // Neutral: vermilion is reserved for needs-input, so no accent-colored button.
                Button(Copy.detailJump.text(tone), action: onJump)
                    .buttonStyle(.bordered)
                    .tint(palette.surface.buttonFill.color)  // default buttons otherwise take the system accent
                    .keyboardShortcut(.defaultAction)
                LinkButton(title: Copy.detailClear.text(tone), action: onClear)
            }
            Spacer(minLength: 0)
        }
        .padding(KohaiSpacing.xl)
    }

    private func field<V: View>(_ name: String, @ViewBuilder value: () -> V) -> some View {
        GridRow {
            Text(name)
                .font(KohaiType.secondary)
                .foregroundStyle(palette.text.tertiary.color)
                .gridColumnAlignment(.trailing)
            value()
        }
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(KohaiType.body)
            .foregroundStyle(palette.text.primary.color)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(KohaiType.monoPath)
            .foregroundStyle(palette.text.secondary.color)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private func labelled(_ text: String, symbol: String?, tone labelTone: LabelTone?) -> some View {
        HStack(spacing: KohaiSpacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(KohaiType.symbol(size: 11))
                    .foregroundStyle((labelTone.map { palette.label($0) } ?? palette.text.secondary).color)
            } else if let labelTone {
                Circle()
                    .fill(palette.label(labelTone).color)
                    .frame(width: KohaiMetrics.labelDot, height: KohaiMetrics.labelDot)
            }
            plain(text)
        }
    }
}

// MARK: Banner

/// Settings warnings (unreadable / newer file, failed save). Wraps; never truncates the path.
struct WarningBanner: View {
    let text: String
    var onShowFile: (() -> Void)? = nil
    var onDismiss: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KohaiSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(KohaiType.symbol(size: 12))
                .foregroundStyle(palette.text.secondary.color)
            Text(text)
                .font(KohaiType.secondary)
                .foregroundStyle(palette.text.primary.color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: KohaiSpacing.sm)
            if let onShowFile {
                LinkButton(title: Copy.warningShowFile.text(tone), action: onShowFile)
            }
            LinkButton(title: Copy.hintDismiss.text(tone), action: onDismiss)
        }
        .padding(.horizontal, KohaiSpacing.lg)
        .padding(.vertical, KohaiSpacing.sm)
        .background(palette.surface.rowHighlight.color)
    }
}

/// The three columns side by side: what PNG snapshots render, since NavigationSplitView
/// itself is AppKit and cannot be drawn by ImageRenderer.
struct MainWindowColumns: View {
    let items: [SpaceItemModel]
    let selectedSpace: SpaceSelection
    let title: String
    let sessions: [SessionRowModel]
    let selectedSession: SessionRowModel.ID?
    let detail: SessionDetailModel?
    var banner: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                WarningBanner(text: banner, onShowFile: {})
                KohaiSeparator()
            }
            HStack(alignment: .top, spacing: 0) {
                SpacesSidebar(items: items, selection: .constant(selectedSpace), scrollable: false)
                Rectangle().fill(KohaiPalette.dark.surface.separator.color).frame(width: KohaiMetrics.hairline)
                SessionColumn(title: title, sessions: sessions, selection: .constant(selectedSession), scrollable: false)
                    .frame(width: KohaiMetrics.sessionColumnWidth)
                Rectangle().fill(KohaiPalette.dark.surface.separator.color).frame(width: KohaiMetrics.hairline)
                SessionDetail(model: detail)
                    .frame(width: KohaiMetrics.detailMinWidth + KohaiSpacing.xl * 2)
            }
        }
    }
}
