import Foundation
import Testing
@testable import KohaiCore

@Suite("Agent tree layout")
struct AgentTreeLayoutTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let s1 = SessionKey(agent: .claude, sessionID: "s1")
    private let s2 = SessionKey(agent: .claude, sessionID: "s2")

    private func spawn(_ graph: inout AgentGraph, _ parent: AgentRef, _ toolUseID: String, _ agentID: String, at seconds: TimeInterval) {
        graph.apply([
            .toolCall(at: t0.addingTimeInterval(seconds), id: toolUseID, name: "Agent", summary: "",
                      spawn: AgentSpawn(description: agentID, agentType: "qa", background: false)),
            .toolResult(at: t0.addingTimeInterval(seconds), toolUseID: toolUseID, isError: false, errorLine: nil,
                        spawnedAgentID: agentID, agentResult: nil),
        ], from: parent)
    }

    @Test func parentCentredOverChildren() throws {
        var graph = AgentGraph()
        let main = AgentRef(session: s1)
        graph.ensureMain(s1, at: t0)
        spawn(&graph, main, "t1", "a", at: 1)
        spawn(&graph, main, "t2", "b", at: 2)
        let layout = AgentTreeLayout(graph: graph, sessions: [s1])
        #expect(layout.positions[AgentRef(session: s1, agentID: "a")] == AgentTreeLayout.Position(column: 0, level: 1))
        #expect(layout.positions[AgentRef(session: s1, agentID: "b")] == AgentTreeLayout.Position(column: 1, level: 1))
        #expect(layout.positions[main] == AgentTreeLayout.Position(column: 0.5, level: 0))
        #expect(layout.columns == 2)
        #expect(layout.levels == 2)
        #expect(layout.edges.count == 2)
    }

    @Test func nestedAgentsGoDeeper() {
        var graph = AgentGraph()
        let main = AgentRef(session: s1)
        graph.ensureMain(s1, at: t0)
        spawn(&graph, main, "t1", "a", at: 1)
        spawn(&graph, AgentRef(session: s1, agentID: "a"), "t2", "a-child", at: 2)
        let layout = AgentTreeLayout(graph: graph, sessions: [s1])
        #expect(layout.levels == 3)
        #expect(layout.positions[AgentRef(session: s1, agentID: "a-child")]?.level == 2)
    }

    @Test func sessionsSideBySideWithAGap() {
        var graph = AgentGraph()
        graph.ensureMain(s1, at: t0)
        graph.ensureMain(s2, at: t0)
        spawn(&graph, AgentRef(session: s2), "t1", "x", at: 1)
        let layout = AgentTreeLayout(graph: graph, sessions: [s1, s2])
        #expect(layout.positions[AgentRef(session: s1)]?.column == 0)
        #expect(layout.positions[AgentRef(session: s2)]?.column == 2)
        #expect(layout.columns == 3)
    }

    @Test func sessionsWithoutANodeAreSkipped() {
        var graph = AgentGraph()
        graph.ensureMain(s2, at: t0)
        let layout = AgentTreeLayout(graph: graph, sessions: [s1, s2])
        #expect(layout.positions[AgentRef(session: s2)]?.column == 0)
        #expect(layout.positions.count == 1)
    }

    @Test func parentCycleStillShowsEveryAgent() {
        var graph = AgentGraph()
        graph.ensureMain(s1, at: t0)
        let a = AgentRef(session: s1, agentID: "a")
        let b = AgentRef(session: s1, agentID: "b")
        graph.apply(meta: AgentMeta(agentType: "qa", parentAgentID: "b"), for: a, at: t0)
        graph.apply(meta: AgentMeta(agentType: "qa", parentAgentID: "a"), for: b, at: t0)
        let layout = AgentTreeLayout(graph: graph, sessions: [s1])
        #expect(layout.positions[a] != nil)
        #expect(layout.positions[b] != nil)
        #expect(layout.positions.count == 3)
    }
}
