import AppKit
import KohaiCore
import SwiftUI

/// The main window: maps Core sessions, settings and space rules onto the design's columns.
struct MainWindowView: View {
    let model: AppModel

    @State private var space: SpaceSelection = .all
    @State private var selectedSession: SessionRowModel.ID?
    @State private var editing: SpaceEditorTarget?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.kohaiCopyTone) private var tone

    private var settings: KohaiSettings { model.settings.settings }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let classified = classify(now: context.date)
            NavigationSplitView {
                SpacesSidebar(
                    items: sidebarItems(classified),
                    selection: $space,
                    onNewSpace: { editing = .new },
                    onEdit: { editing = .existing($0) },
                    onToggleMute: toggleMute,
                    onMove: moveSpace)
                .navigationSplitViewColumnWidth(KohaiMetrics.sidebarWidth)
            } content: {
                SessionColumn(
                    title: title(for: space),
                    sessions: rows(in: space, classified),
                    selection: $selectedSession,
                    onJump: { row in jump(row.id) })
                .navigationSplitViewColumnWidth(min: KohaiMetrics.sessionColumnWidth, ideal: KohaiMetrics.sessionColumnWidth)
            } detail: {
                SessionDetail(
                    model: detail(classified),
                    onJump: { selectedSession.map(jump) },
                    onClear: {
                        if let id = selectedSession, let key = SessionRowModel.key(forID: id) { model.clear(key) }
                    })
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { banner }
        .sheet(item: $editing) { target in
            SpaceEditorSheet(model: model, target: target) { editing = nil }
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            model.openMainWindow = { [openWindow] in openWindow(id: KohaiApp.mainWindowID) }
            updateFocus()
        }
        .onChange(of: selectedSession) { updateFocus() }
        .onChange(of: activeState) { updateFocus() }
        .onDisappear { model.focusedSession = nil }
        .kohaiThemed()
    }

    // MARK: Mapping

    private struct Classified {
        let session: Session
        let row: SessionRowModel
        let space: UUID?
    }

    private func classify(now: Date) -> [Classified] {
        model.store.sessions.values.map { session in
            Classified(
                session: session,
                row: SessionRowModel(
                    session: session, now: now, home: model.home,
                    label: settings.label(forConfigDir: session.configDir)),
                space: model.spaceID(for: session))
        }
    }

    private func rows(in selection: SpaceSelection, _ all: [Classified]) -> [SessionRowModel] {
        all.filter { matches(selection, $0.space) }.map(\.row)
    }

    private func matches(_ selection: SpaceSelection, _ space: UUID?) -> Bool {
        switch selection {
        case .all: true
        case .unsorted: space == nil
        case .space(let id): space == id
        }
    }

    private func sidebarItems(_ all: [Classified]) -> [SpaceItemModel] {
        func counts(_ selection: SpaceSelection) -> (Int, Int) {
            let inside = all.filter { matches(selection, $0.space) }
            return (inside.count, inside.filter { $0.session.status == .needsInput }.count)
        }
        let (allCount, allNeeds) = counts(.all)
        let (unsortedCount, unsortedNeeds) = counts(.unsorted)
        var items = [
            SpaceItemModel(id: .all, name: Copy.sidebarAll.text(tone), symbol: "tray.2", tone: nil,
                           sessionCount: allCount, needsInputCount: allNeeds),
            SpaceItemModel(id: .unsorted, name: Copy.sidebarUnsorted.text(tone), symbol: "questionmark.folder", tone: nil,
                           sessionCount: unsortedCount, needsInputCount: unsortedNeeds),
        ]
        for space in settings.spaces {
            let (count, needs) = counts(.space(space.id))
            items.append(SpaceItemModel(
                id: .space(space.id), name: space.name, symbol: space.symbol, tone: LabelTone(space.color),
                sessionCount: count, needsInputCount: needs,
                muted: settings.notifications.mutedSpaces.contains(space.id)))
        }
        return items
    }

    private func title(for selection: SpaceSelection) -> String {
        switch selection {
        case .all: Copy.sidebarAll.text(tone)
        case .unsorted: Copy.sidebarUnsorted.text(tone)
        case .space(let id): settings.spaces.first { $0.id == id }?.name ?? Copy.sidebarUnsorted.text(tone)
        }
    }

    private func detail(_ all: [Classified]) -> SessionDetailModel? {
        guard let id = selectedSession, let item = all.first(where: { $0.row.id == id }) else { return nil }
        let space = item.space.flatMap { id in settings.spaces.first { $0.id == id } }
        return SessionDetailModel(
            row: item.row,
            folder: abbreviateHome(item.session.projectDir, home: model.home),
            gitRemote: model.gitRemotes.remote(forFolder: item.session.projectDir),
            spaceName: space?.name ?? Copy.sidebarUnsorted.text(tone),
            spaceSymbol: space?.symbol ?? "questionmark.folder",
            spaceTone: space.map { LabelTone($0.color) },
            terminal: TerminalDescription.text(for: item.session.terminal, tone: tone))
    }

    // MARK: Banner

    @ViewBuilder
    private var banner: some View {
        if let text = bannerText {
            VStack(spacing: 0) {
                WarningBanner(text: text, onShowFile: backupPath.map { path in
                    { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }, onDismiss: model.settings.dismissWarning)
                KohaiSeparator()
            }
        }
    }

    private var backupPath: String? {
        switch model.settings.warning {
        case .unreadable(let backup)?, .newerVersion(_, let backup)?: backup.isEmpty ? nil : backup
        case nil: nil
        }
    }

    private var bannerText: String? {
        if let reason = model.settings.saveError {
            return Copy.warningSaveFailed.text(tone, ["reason": reason])
        }
        let path = backupPath.map { abbreviateHome($0, home: model.home) } ?? ""
        switch model.settings.warning {
        case .unreadable?: return Copy.warningUnreadable.text(tone, ["path": path])
        case .newerVersion?: return Copy.warningNewer.text(tone, ["path": path])
        case nil: return nil
        }
    }

    // MARK: Actions

    private func jump(_ rowID: SessionRowModel.ID) {
        if let key = SessionRowModel.key(forID: rowID) { model.jump(to: key) }
    }

    private func toggleMute(_ id: UUID) {
        model.settings.update { s in
            if s.notifications.mutedSpaces.contains(id) {
                s.notifications.mutedSpaces.remove(id)
            } else {
                s.notifications.mutedSpaces.insert(id)
            }
        }
    }

    private func moveSpace(_ id: UUID, by offset: Int) {
        model.settings.update { s in
            guard let index = s.spaces.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard s.spaces.indices.contains(target) else { return }
            s.spaces.swapAt(index, target)
        }
    }

    /// The selected session counts as "being looked at" only while this window is key.
    private func updateFocus() {
        model.focusedSession = activeState == .key ? selectedSession.flatMap(SessionRowModel.key(forID:)) : nil
    }
}

enum SpaceEditorTarget: Identifiable, Hashable {
    case new
    case existing(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let id): id.uuidString
        }
    }
}

/// "Terminal.app · /dev/ttys004", "iTerm2", "tmux %3", "unknown".
enum TerminalDescription {
    static func text(for info: TerminalInfo, tone: CopyTone) -> String {
        var parts: [String] = []
        if let program = info.termProgram {
            let name: String = switch program {
            case "Apple_Terminal": "Terminal.app"
            case "iTerm.app": "iTerm2"
            case "vscode": "VS Code"
            case "WarpTerminal": "Warp"
            default: program
            }
            parts.append(name)
        }
        if let pane = info.tmuxPane { parts.append("tmux \(pane)") }
        if let tty = info.tty { parts.append(tty) }
        return parts.isEmpty ? Copy.terminalUnknown.text(tone) : parts.joined(separator: " · ")
    }
}
