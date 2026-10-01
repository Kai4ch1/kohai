import Foundation
import Testing
@testable import KohaiCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

private func event(
    _ kind: EventKind,
    at seconds: TimeInterval,
    session: String = "s1",
    agent: Agent = .claude,
    project: String = "/Users/me/dev/alpha",
    configDir: String = "/Users/me/.claude",
    message: String? = nil,
    toolKey: String? = nil,
    tty: String? = "/dev/ttys001"
) -> AgentEvent {
    AgentEvent(
        agent: agent, kind: kind, sessionID: session, projectDir: project, cwd: project,
        configDir: configDir, terminal: TerminalInfo(termProgram: "iTerm.app", tty: tty),
        timestamp: t0.addingTimeInterval(seconds), message: message, toolKey: toolKey
    )
}

private func status(_ store: SessionStore, _ session: String = "s1", agent: Agent = .claude) -> SessionStatus? {
    store.sessions[SessionKey(agent: agent, sessionID: session)]?.status
}

@Suite("State transitions")
struct TransitionTests {
    @Test func happyPath() {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 0))
        #expect(status(store) == .done)
        store.apply(event(.promptSubmit, at: 1, message: "fix the bug"))
        #expect(status(store) == .working)
        store.apply(event(.permissionRequest, at: 2, message: "Permission: Bash — rm x", toolKey: "k1"))
        #expect(status(store) == .needsInput)
        #expect(store.needsInputCount == 1)
        store.apply(event(.toolFinished, at: 3, toolKey: "k1"))
        #expect(status(store) == .working)
        #expect(store.needsInputCount == 0)
        store.apply(event(.stop, at: 4, message: "Fixed."))
        #expect(status(store) == .done)
        #expect(store.sessions.first?.value.message == "Fixed.")
        store.apply(event(.sessionEnd, at: 5))
        #expect(store.sessions.isEmpty)
    }

    /// Every (current status, event) pair with the expected next status.
    @Test(arguments: [
        (SessionStatus.done, EventKind.sessionStart, SessionStatus?.some(.done)),
        (.working, .sessionStart, .working),
        (.needsInput, .sessionStart, .needsInput),
        (.done, .promptSubmit, .working),
        (.working, .promptSubmit, .working),
        (.needsInput, .promptSubmit, .working),
        (.done, .permissionRequest, .needsInput),
        (.working, .permissionRequest, .needsInput),
        (.needsInput, .permissionRequest, .needsInput),
        (.done, .toolFinished, .done),
        (.working, .toolFinished, .working),
        (.needsInput, .toolFinished, .working), // matching tool key
        (.done, .stop, .done),
        (.working, .stop, .done),
        (.needsInput, .stop, .done),
        (.done, .sessionEnd, nil),
        (.working, .sessionEnd, nil),
        (.needsInput, .sessionEnd, nil),
    ])
    func table(from: SessionStatus, kind: EventKind, expected: SessionStatus?) {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 0))
        switch from {
        case .done: break
        case .working: store.apply(event(.promptSubmit, at: 1))
        case .needsInput: store.apply(event(.permissionRequest, at: 1, toolKey: "k"))
        }
        #expect(status(store) == from)
        store.apply(event(kind, at: 2, toolKey: "k"))
        #expect(status(store) == expected)
    }

    @Test func statusSinceChangesOnlyWithStatus() throws {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 10))
        store.apply(event(.toolFinished, at: 20, toolKey: "other"))
        store.apply(event(.promptSubmit, at: 30))
        let session = try #require(store.sessions.values.first)
        #expect(session.status == .working)
        #expect(session.statusSince == t0.addingTimeInterval(10))
        #expect(session.lastEventAt == t0.addingTimeInterval(30))
    }

    @Test func eventsWithoutMessageKeepThePreviousOne() {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 1, message: "first"))
        store.apply(event(.toolFinished, at: 2, toolKey: "x"))
        #expect(store.sessions.values.first?.message == "first")
    }

    @Test func sessionsStartedBeforeKohaiAppearOnTheirNextEvent() {
        var store = SessionStore()
        store.apply(event(.permissionRequest, at: 1, session: "a", toolKey: "k"))
        store.apply(event(.toolFinished, at: 1, session: "b", toolKey: "k"))
        store.apply(event(.stop, at: 1, session: "c"))
        #expect(status(store, "a") == .needsInput)
        #expect(status(store, "b") == .working)
        #expect(status(store, "c") == .done)
    }

    @Test func latestEventUpdatesTerminalAndProject() throws {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 1, tty: "/dev/ttys001"))
        store.apply(event(.promptSubmit, at: 2, configDir: "/Users/me/.claude-work", tty: "/dev/ttys009"))
        let session = try #require(store.sessions.values.first)
        #expect(session.terminal.tty == "/dev/ttys009")
        #expect(session.configDir == "/Users/me/.claude-work")
    }
}

@Suite("Pending permissions")
struct PendingPermissionTests {
    @Test func unrelatedToolResultDoesNotClearNeedsInput() {
        // A parallel tool (or subagent) finishing must not hide a blocked prompt.
        var store = SessionStore()
        store.apply(event(.permissionRequest, at: 1, toolKey: "bash-rm"))
        store.apply(event(.toolFinished, at: 2, toolKey: "read-file"))
        #expect(status(store) == .needsInput)
        store.apply(event(.toolFinished, at: 3, toolKey: "bash-rm"))
        #expect(status(store) == .working)
    }

    @Test func twoPendingRequestsNeedBothResults() {
        var store = SessionStore()
        store.apply(event(.permissionRequest, at: 1, toolKey: "a"))
        store.apply(event(.permissionRequest, at: 2, toolKey: "b"))
        store.apply(event(.toolFinished, at: 3, toolKey: "a"))
        #expect(status(store) == .needsInput)
        store.apply(event(.toolFinished, at: 4, toolKey: "b"))
        #expect(status(store) == .working)
    }

    @Test func promptAndStopResetPending() {
        var store = SessionStore()
        store.apply(event(.permissionRequest, at: 1, toolKey: "a"))
        store.apply(event(.promptSubmit, at: 2)) // e.g. after Esc rejected the prompt
        #expect(store.sessions.values.first?.pendingPermissions.isEmpty == true)
        store.apply(event(.permissionRequest, at: 3, toolKey: "b"))
        store.apply(event(.stop, at: 4))
        #expect(store.sessions.values.first?.pendingPermissions.isEmpty == true)
    }
}

@Suite("Out-of-order events")
struct OrderingTests {
    @Test func lateOlderEventIsDropped() {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 1))
        store.apply(event(.stop, at: 3))
        let changed = store.apply(event(.permissionRequest, at: 2, toolKey: "k"))
        #expect(!changed)
        #expect(status(store) == .done)
    }

    @Test func equalTimestampsApplyInArrivalOrder() {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 1))
        store.apply(event(.permissionRequest, at: 1, toolKey: "k"))
        #expect(status(store) == .needsInput)
    }

    @Test func lateEventAfterSessionEndDoesNotResurrect() {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 1))
        store.apply(event(.sessionEnd, at: 5))
        let changed1 = store.apply(event(.stop, at: 4))
        #expect(!changed1)
        #expect(store.sessions.isEmpty)
    }

    @Test func newerEventAfterSessionEndRecreates() {
        // `claude --resume` can reuse the session id.
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 1))
        store.apply(event(.sessionEnd, at: 5))
        store.apply(event(.sessionStart, at: 6))
        #expect(status(store) == .done)
    }

    @Test func sessionEndOlderThanLastEventStillRemoves() {
        var store = SessionStore()
        store.apply(event(.promptSubmit, at: 10))
        store.apply(event(.sessionEnd, at: 9))
        #expect(store.sessions.isEmpty)
        // ...and the removal is remembered from the newest time seen.
        let changed2 = store.apply(event(.stop, at: 10))
        #expect(!changed2)
    }

    @Test func sessionEndForUnknownSessionBlocksLateEvents() {
        var store = SessionStore()
        let changed3 = store.apply(event(.sessionEnd, at: 5))
        #expect(!changed3)
        let changed4 = store.apply(event(.permissionRequest, at: 4, toolKey: "k"))
        #expect(!changed4)
        #expect(store.sessions.isEmpty)
    }

    @Test func removalsAreForgottenAfterTheMemoryWindow() {
        var store = SessionStore()
        store.apply(event(.sessionEnd, at: 0, session: "old"))
        // An unrelated event far in the future prunes the removal...
        store.apply(event(.stop, at: SessionStore.removalMemory + 10, session: "other"))
        // ...so a (very) late event for the old session is accepted again.
        store.apply(event(.stop, at: 1, session: "old"))
        #expect(status(store, "old") == .done)
    }
}

@Suite("Duplicate session ids")
struct DuplicateTests {
    @Test func repeatedSessionStartKeepsOneRowAndState() throws {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 1))
        store.apply(event(.promptSubmit, at: 2))
        store.apply(event(.sessionStart, at: 3)) // e.g. compact
        #expect(store.sessions.count == 1)
        #expect(status(store) == .working)
        #expect(try #require(store.sessions.values.first).statusSince == t0.addingTimeInterval(2))
    }

    @Test func sameEventTwiceIsIdempotent() {
        var store = SessionStore()
        let request = event(.permissionRequest, at: 1, message: "Permission: Bash", toolKey: "k")
        let changed5 = store.apply(request)
        #expect(changed5)
        let snapshot = store.sessions
        let changed6 = store.apply(request)
        #expect(!changed6)
        #expect(store.sessions == snapshot)
        #expect(store.needsInputCount == 1)
    }

    @Test func sameIdFromAnotherConfigDirIsTheSameSession() throws {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 1, configDir: "/Users/me/.claude"))
        store.apply(event(.promptSubmit, at: 2, configDir: "/Users/me/.claude-work"))
        #expect(store.sessions.count == 1)
        #expect(try #require(store.sessions.values.first).configDir == "/Users/me/.claude-work")
    }

    @Test func sameIdFromDifferentAgentsAreDifferentSessions() {
        var store = SessionStore()
        store.apply(event(.sessionStart, at: 1, agent: .claude))
        store.apply(event(.permissionRequest, at: 1, agent: .codex, toolKey: "k"))
        #expect(store.sessions.count == 2)
        #expect(status(store, agent: .claude) == .done)
        #expect(status(store, agent: .codex) == .needsInput)
    }
}

@Suite("Manual clear")
struct ClearTests {
    @Test func clearRemovesAndLaterEventRecreates() {
        var store = SessionStore()
        store.apply(event(.permissionRequest, at: 1, toolKey: "k"))
        store.clear(SessionKey(agent: .claude, sessionID: "s1"), at: t0.addingTimeInterval(2))
        #expect(store.sessions.isEmpty)
        #expect(store.needsInputCount == 0)
        let changed7 = store.apply(event(.toolFinished, at: 1.5, toolKey: "k"))
        #expect(!changed7) // older than the clear
        store.apply(event(.promptSubmit, at: 3))
        #expect(status(store) == .working)
    }

    @Test func clearingUnknownSessionDoesNothing() {
        var store = SessionStore()
        store.clear(SessionKey(agent: .claude, sessionID: "nope"), at: t0)
        store.apply(event(.stop, at: -100, session: "nope"))
        #expect(status(store, "nope") == .done)
    }
}

@Suite("Grouping and display helpers")
struct GroupingTests {
    @Test func groupsByProjectAndSortsByUrgency() {
        var store = SessionStore()
        store.apply(event(.stop, at: 1, session: "b-done", project: "/w/beta"))
        store.apply(event(.promptSubmit, at: 2, session: "a-working", project: "/w/alpha"))
        store.apply(event(.permissionRequest, at: 3, session: "a-blocked", project: "/w/alpha", toolKey: "k"))
        store.apply(event(.stop, at: 4, session: "a-done", project: "/w/alpha"))
        store.apply(event(.promptSubmit, at: 0, session: "a-working-older", project: "/w/alpha"))

        let groups = store.groups
        #expect(groups.map(\.name) == ["alpha", "beta"])
        #expect(groups[0].sessions.map(\.key.sessionID) == ["a-blocked", "a-working-older", "a-working", "a-done"])
        #expect(groups[1].sessions.map(\.key.sessionID) == ["b-done"])
    }

    @Test func sameNameDifferentPathAreSeparateGroups() {
        var store = SessionStore()
        store.apply(event(.stop, at: 1, session: "1", project: "/a/app"))
        store.apply(event(.stop, at: 1, session: "2", project: "/b/app"))
        #expect(store.groups.map(\.projectDir) == ["/a/app", "/b/app"])
    }

    @Test(arguments: [
        (0.0, "0s"), (-5, "0s"), (45.9, "45s"), (60, "1m 0s"), (192, "3m 12s"), (3600, "1h 00m"), (7500, "2h 05m"),
    ])
    func elapsed(seconds: Double, expected: String) {
        #expect(formatElapsed(seconds) == expected)
    }

    @Test func homeAbbreviation() {
        #expect(abbreviateHome("/Users/me/.claude-work", home: "/Users/me") == "~/.claude-work")
        #expect(abbreviateHome("/Users/me", home: "/Users/me") == "~")
        #expect(abbreviateHome("/Users/meg/.claude", home: "/Users/me") == "/Users/meg/.claude")
        #expect(abbreviateHome("/opt/cfg", home: "/Users/me/") == "/opt/cfg")
    }
}
