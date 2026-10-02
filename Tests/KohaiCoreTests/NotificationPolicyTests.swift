import Foundation
import Testing
@testable import KohaiCore

/// Drives the real SessionStore and asks the policy after every event, as the app does.
private struct Harness {
    var store = SessionStore()
    var policy = NotificationPolicy()
    var muted = false
    var focused = false
    private(set) var pings = 0
    let key = SessionKey(agent: .claude, sessionID: "s1")
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    mutating func send(_ kind: EventKind, at seconds: TimeInterval, tool: String? = nil, session: String = "s1") {
        let event = AgentEvent(
            agent: .claude, kind: kind, sessionID: session, projectDir: "/p", cwd: "/p", configDir: "/c",
            terminal: TerminalInfo(), timestamp: t0.addingTimeInterval(seconds), message: nil, toolKey: tool)
        guard store.apply(event) else { return }
        let changed = SessionKey(agent: .claude, sessionID: session)
        if policy.shouldNotify(key: changed, after: store.sessions[changed], muted: muted, focused: focused) {
            pings += 1
        }
    }

    mutating func clear(at seconds: TimeInterval) {
        store.clear(key, at: t0.addingTimeInterval(seconds))
        if policy.shouldNotify(key: key, after: store.sessions[key], muted: muted, focused: focused) { pings += 1 }
    }
}

@Suite("Notification policy")
struct NotificationPolicyTests {
    @Test func firesOncePerTransitionIntoNeedsInput() {
        var h = Harness()
        h.send(.sessionStart, at: 0)
        h.send(.promptSubmit, at: 1)
        h.send(.permissionRequest, at: 2, tool: "k1")
        #expect(h.pings == 1)
        // Duplicate delivery of the same request (retry) changes nothing.
        h.send(.permissionRequest, at: 3, tool: "k1")
        #expect(h.pings == 1)
    }

    @Test func nothingForWorkingOrDone() {
        var h = Harness()
        h.send(.sessionStart, at: 0)
        h.send(.promptSubmit, at: 1)
        h.send(.toolFinished, at: 2, tool: "x")
        h.send(.stop, at: 3)
        #expect(h.pings == 0)
    }

    @Test func newPermissionRequestFiresAgain() {
        var h = Harness()
        h.send(.promptSubmit, at: 1)
        h.send(.permissionRequest, at: 2, tool: "k1")
        // A second, different request while the first is still pending.
        h.send(.permissionRequest, at: 3, tool: "k2")
        #expect(h.pings == 2)
        // Answered, back to work, then the same tool asks again: that is a new request.
        h.send(.toolFinished, at: 4, tool: "k1")
        h.send(.toolFinished, at: 5, tool: "k2")
        h.send(.permissionRequest, at: 6, tool: "k1")
        #expect(h.pings == 3)
    }

    @Test func answeringOneOfTwoDoesNotPing() {
        var h = Harness()
        h.send(.permissionRequest, at: 1, tool: "k1")
        h.send(.permissionRequest, at: 2, tool: "k2")
        h.send(.toolFinished, at: 3, tool: "k1") // still needs input for k2
        #expect(h.pings == 2)
    }

    @Test func nothingAfterClear() {
        var h = Harness()
        h.send(.permissionRequest, at: 1, tool: "k1")
        h.clear(at: 2)
        // A late copy of the old request is dropped by the store.
        h.send(.permissionRequest, at: 1.5, tool: "k1")
        #expect(h.pings == 1)
        // A genuinely new request after the clear brings the session back and pings.
        h.send(.permissionRequest, at: 3, tool: "k1")
        #expect(h.pings == 2)
    }

    @Test func mutedSpaceNeverPingsAndDoesNotPingLater() {
        var h = Harness()
        h.muted = true
        h.send(.permissionRequest, at: 1, tool: "k1")
        #expect(h.pings == 0)
        // Unmuting does not replay the request that arrived while muted.
        h.muted = false
        h.send(.permissionRequest, at: 2, tool: "k1")
        #expect(h.pings == 0)
        h.send(.permissionRequest, at: 3, tool: "k2")
        #expect(h.pings == 1)
    }

    @Test func focusedSessionIsSkipped() {
        var h = Harness()
        h.focused = true
        h.send(.permissionRequest, at: 1, tool: "k1")
        h.focused = false
        h.send(.permissionRequest, at: 2, tool: "k1")
        #expect(h.pings == 0)
    }

    @Test func sessionEndForgetsAndOtherSessionsAreIndependent() {
        var h = Harness()
        h.send(.permissionRequest, at: 1, tool: "k1")
        h.send(.permissionRequest, at: 1, tool: "k1", session: "s2")
        #expect(h.pings == 2)
        h.send(.sessionEnd, at: 2)
        h.send(.permissionRequest, at: 3, tool: "k1", session: "s2")
        #expect(h.pings == 2)
    }

    @Test func requestWithoutToolKeyStillPingsOnce() {
        var h = Harness()
        h.send(.permissionRequest, at: 1, tool: nil)
        h.send(.permissionRequest, at: 2, tool: nil)
        #expect(h.pings == 1)
    }
}
