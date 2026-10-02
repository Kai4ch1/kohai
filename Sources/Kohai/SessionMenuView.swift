import AppKit
import KohaiCore
import SwiftUI

// The app is the only place that sees both KohaiCore and the design system: Core sessions are
// mapped to the design's presentation models here, so the views never import Core.

/// Menu bar status item: template mascot head, filled with a count when sessions need input.
struct MenuBarLabel: View {
    let needsInput: Int

    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        HStack(spacing: KohaiSpacing.xs) {
            if let image = MenuBarImages.image(filled: needsInput > 0) {
                Image(nsImage: image)
            }
            if needsInput > 0 {
                Text(needsInput > 9 ? "9+" : "\(needsInput)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            needsInput > 0
                ? Copy.menuBarSome.text(tone, ["n": "\(needsInput)"])
                : Copy.menuBarNone.text(tone))
    }
}

/// Rendering the template image is not free and the label re-renders on every store change.
@MainActor
private enum MenuBarImages {
    private static var cache: [Bool: NSImage] = [:]

    static func image(filled: Bool) -> NSImage? {
        if let cached = cache[filled] { return cached }
        let image = MenuBarIconImage.make(filled: filled)
        cache[filled] = image
        return image
    }
}

struct SessionMenuView: View {
    let model: AppModel

    /// The user opened the connect screen from the footer or the hint.
    @State private var showingConnect = false

    @Environment(\.kohaiCopyTone) private var tone

    private var connections: AgentConnections { model.connections }

    var body: some View {
        VStack(spacing: 0) {
            content
            // Every screen, errors included: click the icon, click Quit.
            DropdownFooter(
                onAgents: isShowingConnect ? nil : { showingConnect = true },
                onQuit: { NSApp.terminate(nil) })
        }
        .background {
            // ⌘Q while the dropdown has focus.
            Button(Copy.quit.text(tone)) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .hidden()
        }
        .onAppear { model.refreshConnections() }
        .kohaiThemed()
    }

    private var isShowingConnect: Bool {
        model.listenerError == nil && !model.automationDenied && (showingConnect || needsOnboarding)
    }

    /// First run: nothing connected yet and nothing to show, so ask instead of showing "All quiet".
    private var needsOnboarding: Bool {
        !model.onboardingDismissed && model.store.sessions.isEmpty
            && !connections.hasConnectedAccount && connections.pendingCount > 0
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.listenerError {
            KohaiStateDropdown(kind: .socketError, detail: error) {
                model.stop()
                _ = model.start()
            }
        } else if model.automationDenied {
            KohaiStateDropdown(kind: .automationDenied) {
                model.automationDenied = false
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if showingConnect || needsOnboarding {
            ConnectAgentsDropdown(
                accounts: connections.accounts.map { AccountRowModel(account: $0, state: connections.states[$0.id], home: model.home) },
                notice: noticeText,
                onConnect: { ids in
                    connections.connect(ids)
                    showingConnect = true // stay to show the restart reminder
                },
                onDisconnect: { id in
                    connections.disconnect(id)
                    showingConnect = true
                },
                onAddFolder: {
                    connections.addFolder()
                    showingConnect = true
                },
                onDone: {
                    connections.declinePending()
                    model.onboardingDismissed = true
                    showingConnect = false
                })
            // A fresh selection whenever the set of accounts or their states change.
            .id(connections.accounts.map { "\($0.id)=\(String(describing: connections.states[$0.id]))" })
        } else if model.store.sessions.isEmpty {
            KohaiStateDropdown(kind: .empty)
        } else {
            // Rows show static "seconds in status", so re-map once a second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let rows = model.store.sessions.values.map {
                    SessionRowModel(session: $0, now: context.date, home: model.home)
                }
                KohaiDropdown(
                        sessions: rows,
                        hint: connections.pendingCount > 0 ? .accountsPending(connections.pendingCount) : nil,
                        onJump: { row in
                            if let key = SessionRowModel.key(forID: row.id) { model.jump(to: key) }
                        },
                        onClear: { row in
                            if let key = SessionRowModel.key(forID: row.id) { model.clear(key) }
                        },
                        onDismissHint: { showingConnect = true })
            }
        }
    }

    private var noticeText: String? {
        switch connections.notice {
        case nil:
            return nil
        case .connected:
            return Copy.connectRestart.text(tone)
        case .failed(let failures):
            return failures
                .map { Copy.connectFailed.text(tone, ["file": $0.file, "reason": $0.reason]) }
                .joined(separator: "\n")
        }
    }
}

extension AccountRowModel {
    init(account: AgentAccount, state: HookConnection?, home: String) {
        let mapped: AccountConnectionState = switch state ?? .notConnected {
        case .notConnected: .notConnected
        case .connected: .connected
        case .needsUpdate: .needsUpdate
        case .unreadable(let reason): .unreadable(reason)
        }
        self.init(
            id: account.id,
            agent: AgentKind(account.agent),
            path: abbreviateHome(account.configDir, home: home),
            state: mapped)
    }
}

extension SessionRowModel {
    init(session: Session, now: Date, home: String) {
        self.init(
            id: Self.id(for: session.key),
            agent: AgentKind(session.agent),
            project: session.projectName,
            sessionName: Self.name(for: session),
            account: session.accountLabel(home: home),
            status: SessionStatus(session.status),
            secondsInStatus: max(0, Int(now.timeIntervalSince(session.statusSince))),
            lastMessage: session.message ?? "")
    }

    /// Session ids are only unique per agent, so the row id carries both.
    static func id(for key: SessionKey) -> String {
        "\(key.agent.rawValue):\(key.sessionID)"
    }

    static func key(forID id: String) -> SessionKey? {
        guard let colon = id.firstIndex(of: ":"),
              let agent = Agent(rawValue: String(id[..<colon]))
        else { return nil }
        return SessionKey(agent: agent, sessionID: String(id[id.index(after: colon)...]))
    }

    /// Hooks carry no session title. Use the working directory when the agent runs in a
    /// subfolder of the project, otherwise a short session id.
    private static func name(for session: Session) -> String {
        let prefix = session.projectDir.hasSuffix("/") ? session.projectDir : session.projectDir + "/"
        if session.cwd.hasPrefix(prefix) {
            return String(session.cwd.dropFirst(prefix.count))
        }
        return String(session.key.sessionID.prefix(8))
    }
}

extension AgentKind {
    init(_ agent: Agent) {
        switch agent {
        case .claude: self = .claudeCode
        case .codex: self = .codex
        }
    }
}

extension SessionStatus {
    init(_ status: KohaiCore.SessionStatus) {
        switch status {
        case .needsInput: self = .needsInput
        case .working: self = .working
        case .done: self = .done
        }
    }
}
