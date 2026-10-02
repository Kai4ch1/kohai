import SwiftUI

// =============================================================================
// Every previewable state, defined ONCE. `KohaiPreviews.swift` shows them in
// the Xcode canvas; `SnapshotTests` renders the same list to PNG.
// =============================================================================

/// Stand-in for the system material, so a state can be seen (and rendered to
/// PNG) outside a real menu bar window. NEVER used in the shipping app.
struct PreviewStage<Content: View>: View {
    let lifted: Bool
    let tone: CopyTone
    let content: Content

    init(lifted: Bool = false, tone: CopyTone = .polite, @ViewBuilder content: () -> Content) {
        self.lifted = lifted
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        let colors = KohaiPalette.dark.preview
        content
            .background(lifted ? colors.materialLifted.color : colors.materialNominal.color)
            .padding(KohaiSpacing.lg)
            .background(colors.stage.color)
            .kohaiThemed()
            .environment(\.kohaiCopyTone, tone)
    }
}

struct PreviewEntry: Identifiable {
    /// File name stem of the PNG, e.g. "03-empty".
    let id: String
    let title: String
    /// Parameter: `forSnapshot` (true = no ScrollView, deterministic layout).
    let make: @MainActor (Bool) -> AnyView
}

enum PreviewCatalog {

    static let main = PreviewEntry(id: "01-main", title: "Dropdown, mixed sessions") { snap in
        AnyView(PreviewStage { KohaiDropdown(sessions: PreviewData.mixed, scrollable: !snap) })
    }

    static let firstRunHint = PreviewEntry(id: "02-first-run-hint", title: "First-run hint (keep icon visible)") { snap in
        AnyView(PreviewStage {
            KohaiDropdown(sessions: PreviewData.mixed, hint: .firstRun, scrollable: !snap)
        })
    }

    static let empty = PreviewEntry(id: "03-empty", title: "Empty") { _ in
        AnyView(PreviewStage { KohaiStateDropdown(kind: .empty) })
    }

    static let hooksNotInstalled = PreviewEntry(id: "04-hooks-not-installed", title: "Hooks not installed") { _ in
        AnyView(PreviewStage { KohaiStateDropdown(kind: .hooksNotInstalled) })
    }

    static let socketError = PreviewEntry(id: "05-socket-error", title: "App / socket error") { _ in
        AnyView(PreviewStage { KohaiStateDropdown(kind: .socketError) })
    }

    static let automationDenied = PreviewEntry(id: "06-automation-denied", title: "Automation permission denied") { _ in
        AnyView(PreviewStage { KohaiStateDropdown(kind: .automationDenied) })
    }

    static let manySessions = PreviewEntry(id: "07-many-sessions", title: "20+ sessions") { snap in
        AnyView(PreviewStage { KohaiDropdown(sessions: PreviewData.many, scrollable: !snap) })
    }

    static let longNames = PreviewEntry(id: "08-long-project-names", title: "Very long project names") { snap in
        AnyView(PreviewStage { KohaiDropdown(sessions: PreviewData.longNames, scrollable: !snap) })
    }

    static let unknownAgent = PreviewEntry(id: "09-unknown-agent", title: "Unknown agent type") { snap in
        AnyView(PreviewStage { KohaiDropdown(sessions: PreviewData.unknownAgent, scrollable: !snap) })
    }

    /// Icon hidden in the menu bar overflow: the notification still reaches the
    /// user, and the dropdown (opened from the overflow) explains it in one line.
    static let overflowHidden = PreviewEntry(id: "10-icon-hidden-overflow", title: "Icon hidden in menu bar overflow") { snap in
        AnyView(PreviewStage {
            VStack(spacing: KohaiSpacing.lg) {
                NotificationBannerMock(project: "yheat", agent: "Claude Code", session: "popup-heatmap-fix")
                KohaiDropdown(sessions: PreviewData.mixed, hint: .overflow, scrollable: !snap)
            }
        })
    }

    static let menuBarIcon = PreviewEntry(id: "11-menu-bar-icon", title: "Menu bar icon (template), idle vs needs input") { _ in
        AnyView(PreviewStage { MenuBarIconSheet() })
    }

    static let mascotSheet = PreviewEntry(id: "12-mascot-placeholders", title: "Mascot placeholders 16/32/64 x 5 states") { _ in
        AnyView(PreviewStage { MascotSheet() })
    }

    static let mainIncreasedContrast = PreviewEntry(id: "13-main-increase-contrast", title: "Dropdown, Increase Contrast") { snap in
        AnyView(
            PreviewStage { KohaiDropdown(sessions: PreviewData.mixed, scrollable: !snap) }
                .environment(\.kohaiContrastOverride, .increased))
    }

    static let mainLifted = PreviewEntry(id: "14-main-lifted-material", title: "Dropdown, worst-case lifted material") { snap in
        AnyView(PreviewStage(lifted: true) { KohaiDropdown(sessions: PreviewData.mixed, scrollable: !snap) })
    }

    static let mainSerious = PreviewEntry(id: "15-main-serious-mode", title: "Dropdown, serious mode copy") { snap in
        AnyView(PreviewStage(tone: .serious) { KohaiDropdown(sessions: PreviewData.mixed, scrollable: !snap) })
    }

    static let emptySerious = PreviewEntry(id: "16-empty-serious-mode", title: "Empty, serious mode copy") { _ in
        AnyView(PreviewStage(tone: .serious) { KohaiStateDropdown(kind: .empty) })
    }

    static let hooksSerious = PreviewEntry(id: "17-hooks-serious-mode", title: "Hooks not installed, serious mode copy") { _ in
        AnyView(PreviewStage(tone: .serious) { KohaiStateDropdown(kind: .hooksNotInstalled) })
    }

    static let connectFirstRun = PreviewEntry(id: "18-connect-first-run", title: "Connect agents, first run") { _ in
        AnyView(PreviewStage { ConnectAgentsDropdown(accounts: PreviewData.accountsFirstRun) })
    }

    static let connectMixed = PreviewEntry(id: "19-connect-mixed", title: "Connect agents, every account state") { _ in
        AnyView(PreviewStage {
            ConnectAgentsDropdown(
                accounts: PreviewData.accountsMixed,
                notice: Copy.connectRestart.text(.polite),
                onDone: {})
        })
    }

    static let connectNoneFound = PreviewEntry(id: "20-connect-none-found", title: "Connect agents, nothing found") { _ in
        AnyView(PreviewStage { ConnectAgentsDropdown(accounts: [], onDone: {}) })
    }

    static let connectSerious = PreviewEntry(id: "21-connect-serious-mode", title: "Connect agents, serious mode copy") { _ in
        AnyView(PreviewStage(tone: .serious) { ConnectAgentsDropdown(accounts: PreviewData.accountsMixed, onDone: {}) })
    }

    static let mainPendingHint = PreviewEntry(id: "22-main-accounts-pending", title: "Dropdown with not-connected hint and footer") { snap in
        AnyView(PreviewStage {
            VStack(spacing: 0) {
                KohaiDropdown(sessions: PreviewData.mixed, hint: .accountsPending(1), scrollable: !snap)
                DropdownFooter()
            }
        })
    }

    static let mainWindow = PreviewEntry(id: "23-main-window", title: "Main window: Work space, session selected") { _ in
        AnyView(PreviewStage {
            MainWindowColumns(
                items: PreviewData.spaceItems, selectedSpace: .space(PreviewData.workSpaceID), title: "Work",
                sessions: PreviewData.workSessions, selectedSession: PreviewData.workSessions[0].id,
                detail: PreviewData.workDetail)
        })
    }

    static let mainWindowEmpty = PreviewEntry(id: "24-main-window-empty", title: "Main window: empty space, nothing selected") { _ in
        AnyView(PreviewStage {
            MainWindowColumns(
                items: PreviewData.spaceItems, selectedSpace: .unsorted, title: Copy.sidebarUnsorted.text(.polite),
                sessions: [], selectedSession: nil, detail: nil)
        })
    }

    static let mainWindowWarning = PreviewEntry(id: "25-main-window-settings-warning", title: "Main window: unreadable settings banner, serious") { _ in
        AnyView(PreviewStage(tone: .serious) {
            MainWindowColumns(
                items: PreviewData.spaceItems, selectedSpace: .all, title: Copy.sidebarAll.text(.serious),
                sessions: PreviewData.workSessions, selectedSession: nil, detail: nil,
                banner: Copy.warningUnreadable.text(.serious, ["path": "~/Library/Application Support/Kohai/settings.json.bak"]))
        })
    }

    static let spaceEditor = PreviewEntry(id: "26-space-editor", title: "Space editor: Work with three rule kinds (text fields are AppKit: blank in PNG)") { _ in
        AnyView(PreviewStage {
            SpaceEditor(
                draft: .constant(SpaceDraft(name: "Work", tone: .orange, symbol: "briefcase", rules: [
                    RuleDraft(kind: .account, value: "/Users/me/.claude-work"),
                    RuleDraft(kind: .remote, value: "github.com/acme/*"),
                    RuleDraft(kind: .folder, value: "/Users/me/work"),
                ])),
                isNew: false,
                accounts: [
                    AccountOption(id: "/Users/me/.claude", title: "Personal (~/.claude)", tone: .blue),
                    AccountOption(id: "/Users/me/.claude-work", title: "Work (~/.claude-work)", tone: .orange),
                ],
                onDelete: {})
        })
    }

    /// Required states first, then the extra accessibility / tone variants.
    static let all: [PreviewEntry] = [
        main, firstRunHint, empty, hooksNotInstalled, socketError, automationDenied,
        manySessions, longNames, unknownAgent, overflowHidden, menuBarIcon, mascotSheet,
        mainIncreasedContrast, mainLifted, mainSerious, emptySerious, hooksSerious,
        connectFirstRun, connectMixed, connectNoneFound, connectSerious, mainPendingHint,
        mainWindow, mainWindowEmpty, mainWindowWarning, spaceEditor,
    ]
}
