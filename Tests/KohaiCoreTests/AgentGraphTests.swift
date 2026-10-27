import Foundation
import Testing
@testable import KohaiCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private let session = SessionKey(agent: .claude, sessionID: "s1")
private let main = AgentRef(session: session)
private func child(_ id: String) -> AgentRef { AgentRef(session: session, agentID: id) }

private func hook(_ kind: EventKind, _ seconds: TimeInterval, agent: String? = nil, type: String? = nil,
                  message: String? = nil, toolKey: String? = nil) -> AgentEvent {
    AgentEvent(
        agent: .claude, kind: kind, sessionID: session.sessionID, projectDir: "/p", cwd: "/p", configDir: "/c",
        terminal: TerminalInfo(), timestamp: at(seconds), message: message, toolKey: toolKey,
        agentID: agent, agentType: type)
}

private func spawnCall(_ id: String, _ seconds: TimeInterval, description: String? = "Write tests", type: String = "qa",
                       background: Bool = false) -> TranscriptEntry {
    .toolCall(at: at(seconds), id: id, name: "Agent", summary: description ?? "",
              spawn: AgentSpawn(description: description, agentType: type, background: background))
}

private func launched(_ toolUseID: String, _ agentID: String, _ seconds: TimeInterval) -> TranscriptEntry {
    .toolResult(at: at(seconds), toolUseID: toolUseID, isError: false, errorLine: nil, spawnedAgentID: agentID, agentResult: nil)
}

@Suite("Agent graph: linking")
struct AgentGraphLinkTests {
    @Test func fixtureBuildsParentAndChild() throws {
        var graph = AgentGraph()
        let key = SessionKey(agent: .claude, sessionID: TranscriptFixture.sessionID)
        let mainRef = AgentRef(session: key)
        let childRef = AgentRef(session: key, agentID: TranscriptFixture.agentID)
        graph.apply(try TranscriptFixture.entries(TranscriptFixture.main), from: mainRef)
        graph.apply(try TranscriptFixture.entries(TranscriptFixture.child), from: childRef)
        let meta = try #require(AgentMeta.parse(try TranscriptFixture.data(TranscriptFixture.meta)))
        graph.apply(meta: meta, for: childRef, at: Date())

        let node = try #require(graph.node(childRef))
        #expect(node.parent == mainRef)
        #expect(node.toolUseID == TranscriptFixture.spawnToolUseID)
        #expect(node.name == "Research task")
        #expect(node.agentType == "general-purpose")
        #expect(node.status == .done)
        #expect(node.result?.source == .handback)
        #expect(graph.children(of: mainRef).map(\.id) == [childRef])

        let kinds = node.steps.map(\.kind)
        #expect(kinds.first == .prompt)
        #expect(kinds.contains(.tool))
        #expect(kinds.contains(.message))
        #expect(kinds.contains(.handback))
        #expect(!node.steps.contains { $0.name == "SubagentHandback" })
        let bash = try #require(node.steps.first { $0.name == "Bash" })
        #expect(bash.finishedAt != nil)
        #expect(!bash.isError)

        // The main session's own log has the spawn call, finished once the launch returned.
        let spawn = try #require(graph.node(mainRef)?.steps.first { $0.id == TranscriptFixture.spawnToolUseID })
        #expect(spawn.name == "Agent")
        #expect(spawn.finishedAt != nil)
    }

    @Test func readingTheSameFileTwiceAddsNothing() throws {
        var graph = AgentGraph()
        let key = SessionKey(agent: .claude, sessionID: TranscriptFixture.sessionID)
        let childRef = AgentRef(session: key, agentID: TranscriptFixture.agentID)
        let entries = try TranscriptFixture.entries(TranscriptFixture.child)
        graph.apply(entries, from: childRef)
        let once = graph.node(childRef)?.steps
        graph.apply(entries, from: childRef)
        #expect(graph.node(childRef)?.steps == once)
    }

    @Test func spawnBeforeLaunchResult() throws {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1), launched("t1", "a1", 2)], from: main)
        let node = try #require(graph.node(child("a1")))
        #expect(node.parent == main)
        #expect(node.name == "Write tests")
        #expect(node.agentType == "qa")
        #expect(node.status == .running)
        #expect(node.startedAt == at(1))
    }

    @Test func childFileAndMetaBeforeTheParentLine() throws {
        var graph = AgentGraph()
        graph.apply([.prompt(at: at(2), text: "do it", continuation: false)], from: child("a1"))
        graph.apply(meta: AgentMeta(agentType: "qa", toolUseID: "t1"), for: child("a1"), at: at(2))
        #expect(graph.node(child("a1"))?.name == "qa")
        graph.apply([spawnCall("t1", 1, description: "Write tests")], from: main)
        let node = try #require(graph.node(child("a1")))
        #expect(node.name == "Write tests")
        #expect(node.parent == main)
    }

    @Test func nestedAgentFromMeta() throws {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1), launched("t1", "a1", 2)], from: main)
        graph.apply([spawnCall("t2", 3, description: "Sub task"), launched("t2", "a2", 4)], from: child("a1"))
        graph.apply(meta: AgentMeta(agentType: "qa", toolUseID: "t2", parentAgentID: "a1", spawnDepth: 2), for: child("a2"), at: at(4))
        #expect(graph.node(child("a2"))?.parent == child("a1"))
        #expect(graph.children(of: child("a1")).map(\.id) == [child("a2")])
        #expect(graph.children(of: main).map(\.id) == [child("a1")])
    }

    @Test func childWithUnknownParentHangsUnderMain() {
        var graph = AgentGraph()
        graph.apply(meta: AgentMeta(agentType: "qa", parentAgentID: "ghost"), for: child("a2"), at: at(1))
        #expect(graph.children(of: main).map(\.id) == [child("a2")])
    }

    @Test func nameFallsBackToTypeThenID() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        #expect(graph.node(child("a1"))?.name == "a1")
        graph.apply(hook: hook(.toolFinished, 2, agent: "a1", type: "Explore"))
        #expect(graph.node(child("a1"))?.name == "Explore")
        graph.apply(meta: AgentMeta(agentType: "Explore", description: "Find callers", name: "scout"), for: child("a1"), at: at(3))
        #expect(graph.node(child("a1"))?.name == "scout")
    }

    @Test func childrenInLaunchOrder() {
        var graph = AgentGraph()
        graph.apply([spawnCall("t2", 5), launched("t2", "b", 6), spawnCall("t1", 1), launched("t1", "z", 2)], from: main)
        #expect(graph.children(of: main).map(\.id.agentID) == ["z", "b"])
    }
}

@Suite("Agent graph: status")
struct AgentGraphStatusTests {
    @Test func hookLifecycle() throws {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1", type: "qa"))
        #expect(graph.node(child("a1"))?.status == .running)
        graph.apply(hook: hook(.permissionRequest, 2, agent: "a1", toolKey: "k1"))
        #expect(graph.node(child("a1"))?.status == .needsInput)
        #expect(graph.summary(of: session) == AgentGraph.Summary(total: 1, running: 0, needsInput: 1))
        graph.apply(hook: hook(.toolFinished, 3, agent: "a1", toolKey: "other"))
        #expect(graph.node(child("a1"))?.status == .needsInput)
        graph.apply(hook: hook(.toolFinished, 4, agent: "a1", toolKey: "k1"))
        #expect(graph.node(child("a1"))?.status == .running)
        graph.apply(hook: hook(.subagentStop, 5, agent: "a1", message: "short summary"))
        let node = try #require(graph.node(child("a1")))
        #expect(node.status == .done)
        #expect(node.endedAt == at(5))
        #expect(node.result == AgentResult(text: "short summary", at: at(5), source: .finalMessage))
    }

    @Test func mainSessionEventsDontTouchSubagents() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply(hook: hook(.permissionRequest, 2, toolKey: "k"))
        graph.apply(hook: hook(.stop, 3))
        #expect(graph.node(child("a1"))?.status == .running)
    }

    @Test func olderEvidenceDoesNotOverrideNewer() {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1), launched("t1", "a1", 2)], from: main)
        graph.apply([.agentFinished(at: at(10), agentID: "a1", status: .completed)], from: main)
        // A late hook from before the finish.
        graph.apply(hook: hook(.permissionRequest, 5, agent: "a1", toolKey: "k"))
        #expect(graph.node(child("a1"))?.status == .done)
    }

    @Test func finishedAgentReopensOnlyOnContinuation() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply(hook: hook(.subagentStop, 2, agent: "a1"))
        graph.apply([.prompt(at: at(3), text: "a reminder", continuation: false)], from: child("a1"))
        #expect(graph.node(child("a1"))?.status == .done)
        graph.apply([.prompt(at: at(4), text: "one more thing", continuation: true)], from: child("a1"))
        #expect(graph.node(child("a1"))?.status == .running)
        #expect(graph.node(child("a1"))?.endedAt == nil)
        // SubagentStart also reopens (continue via SendMessage).
        graph.apply(hook: hook(.subagentStop, 5, agent: "a1"))
        graph.apply(hook: hook(.subagentStart, 6, agent: "a1"))
        #expect(graph.node(child("a1"))?.status == .running)
    }

    @Test(arguments: [
        (AgentFinish.completed, AgentStatus.done), (.failed, .error), (.killed, .interrupted), (.blocked, .needsInput),
    ])
    func notificationStatus(finish: AgentFinish, expected: AgentStatus) {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1, background: true), launched("t1", "a1", 2)], from: main)
        graph.apply([.agentFinished(at: at(3), agentID: "a1", status: finish)], from: main)
        #expect(graph.node(child("a1"))?.status == expected)
        #expect(graph.node(child("a1"))?.background == true)
    }

    @Test func notificationForUnknownTaskIsIgnored() {
        var graph = AgentGraph()
        graph.apply([.agentFinished(at: at(3), agentID: "b7shell", status: .completed)], from: main)
        #expect(graph.node(child("b7shell")) == nil)
    }

    @Test func failedLaunchMarksTheChild() {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1),
                     .toolResult(at: at(2), toolUseID: "t1", isError: true, errorLine: "boom", spawnedAgentID: "a1", agentResult: nil)],
                    from: main)
        #expect(graph.node(child("a1"))?.status == .error)
        #expect(graph.node(main)?.steps.first?.errorLine == "boom")
    }

    @Test func foregroundResultFinishesTheChild() {
        var graph = AgentGraph()
        graph.apply([spawnCall("t1", 1),
                     .toolResult(at: at(9), toolUseID: "t1", isError: false, errorLine: nil, spawnedAgentID: "a1", agentResult: "answer")],
                    from: main)
        #expect(graph.node(child("a1"))?.status == .done)
        #expect(graph.node(child("a1"))?.result?.text == "answer")
    }

    @Test func interruption() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply([.interrupted(at: at(2))], from: child("a1"))
        #expect(graph.node(child("a1"))?.status == .interrupted)
    }

    @Test func sessionEndRemovesTheSession() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        let other = SessionKey(agent: .claude, sessionID: "s2")
        graph.ensureMain(other, at: at(1))
        graph.apply(hook: hook(.sessionEnd, 2))
        #expect(graph.node(child("a1")) == nil)
        #expect(graph.node(main) == nil)
        #expect(graph.node(AgentRef(session: other)) != nil)
    }
}

@Suite("Agent graph: results and steps")
struct AgentGraphResultTests {
    @Test func resultPriority() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply([.handback(at: at(5), agentID: "a1", text: "full report")], from: main)
        graph.apply(hook: hook(.subagentStop, 6, agent: "a1", message: "short"))
        #expect(graph.node(child("a1"))?.result?.text == "full report")
        graph.attachReport(path: "/p/reports/qa-x.md", text: "# Report", at: at(7), to: child("a1"))
        #expect(graph.node(child("a1"))?.result?.source == .report(path: "/p/reports/qa-x.md"))
        graph.apply([.handback(at: at(8), agentID: "a1", text: "later handback")], from: main)
        #expect(graph.node(child("a1"))?.result?.text == "# Report")
    }

    @Test func handbackFromBothFilesIsOneStep() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply([.handback(at: at(5), agentID: "a1", text: "same report")], from: child("a1"))
        graph.apply([.handback(at: at(6), agentID: "a1", text: "same report")], from: main)
        #expect(graph.node(child("a1"))?.steps.filter { $0.kind == .handback }.count == 1)
    }

    @Test func stepsStayInTimeOrderAcrossFiles() {
        var graph = AgentGraph()
        graph.apply(hook: hook(.subagentStart, 1, agent: "a1"))
        graph.apply([.handback(at: at(5), agentID: "a1", text: "report")], from: main)
        graph.apply([.prompt(at: at(2), text: "task", continuation: false),
                     .text(at: at(3), messageID: "m", text: "thinking aloud")], from: child("a1"))
        #expect(graph.node(child("a1"))?.steps.map(\.kind) == [.prompt, .message, .handback])
    }

    @Test func latestTextAndPendingTool() throws {
        var graph = AgentGraph()
        graph.apply([.text(at: at(1), messageID: "m1", text: "first"),
                     .toolCall(at: at(2), id: "t", name: "Bash", summary: "Run tests", spawn: nil),
                     .text(at: at(3), messageID: "m2", text: "second")], from: child("a1"))
        let node = try #require(graph.node(child("a1")))
        #expect(node.latestText == "second")
        #expect(node.steps.first { $0.id == "t" }?.isPending == true)
    }

    @Test func stepsAreCapped() throws {
        var graph = AgentGraph()
        let entries = (0..<(AgentGraph.maxSteps + 25)).map {
            TranscriptEntry.text(at: at(Double($0)), messageID: "m\($0)", text: "line \($0)")
        }
        graph.apply(entries, from: child("a1"))
        let node = try #require(graph.node(child("a1")))
        #expect(node.steps.count == AgentGraph.maxSteps)
        #expect(node.droppedSteps == 25)
        #expect(node.steps.first?.summary == "line 25")
    }

    @Test func resetStepsAllowsRereading() {
        var graph = AgentGraph()
        let entries: [TranscriptEntry] = [.prompt(at: at(1), text: "task", continuation: false)]
        graph.apply(entries, from: child("a1"))
        graph.resetSteps(of: child("a1"))
        #expect(graph.node(child("a1"))?.steps.isEmpty == true)
        graph.apply(entries, from: child("a1"))
        #expect(graph.node(child("a1"))?.steps.count == 1)
    }
}
