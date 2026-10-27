import Foundation
import Testing
@testable import KohaiCore

// Fixtures in Fixtures/transcripts are hand-written: a main session that launched one subagent, that
// subagent's file and its meta.json. Record types, keys and nesting mirror what Claude Code 2.1.311
// writes; every id, timestamp and text is made up.

enum TranscriptFixture {
    static let sessionID = "5e551011-0000-4000-8000-00000000c0de"
    static let agentID = "a0000000000000001"
    static let spawnToolUseID = "toolu_01SPAWN0000000000000001"

    static func data(_ relativePath: String) throws -> Data {
        let base = try #require(Bundle.module.resourceURL, "no test resources")
        return try Data(contentsOf: base.appendingPathComponent("Fixtures/transcripts/\(relativePath)"))
    }

    static func lines(_ relativePath: String) throws -> [Data] {
        try data(relativePath).split(separator: 0x0A).map { Data($0) }
    }

    static var main: String { "\(sessionID).jsonl" }
    static var child: String { "\(sessionID)/subagents/agent-\(agentID).jsonl" }
    static var meta: String { "\(sessionID)/subagents/agent-\(agentID).meta.json" }

    static func entries(_ relativePath: String) throws -> [TranscriptEntry] {
        try lines(relativePath).flatMap { TranscriptParser.entries(fromLine: $0) }
    }
}

private func line(_ json: String) -> [TranscriptEntry] {
    TranscriptParser.entries(fromLine: Data(json.utf8))
}

private let ts = "2026-10-01T01:05:13.464Z"
private let tsDate = Date(timeIntervalSince1970: 1_790_816_713.464)

@Suite("Transcript fixtures")
struct TranscriptFixtureTests {
    @Test func mainSessionLines() throws {
        let entries = try TranscriptFixture.entries(TranscriptFixture.main)
        guard entries.count == 8 else {
            Issue.record("expected 8 entries, got \(entries.count): \(entries)")
            return
        }
        guard case .prompt(_, "Plan the agent map", false) = entries[0] else { Issue.record("\(entries[0])"); return }
        guard case .text(_, let messageID, "Looking into the transcript format first.") = entries[1] else { Issue.record("\(entries[1])"); return }
        #expect(messageID?.hasPrefix("msg_") == true)
        guard case .toolCall(_, TranscriptFixture.spawnToolUseID, "Agent", "Research transcripts", let spawn?) = entries[2] else {
            Issue.record("\(entries[2])"); return
        }
        #expect(spawn == AgentSpawn(description: "Research transcripts", agentType: "general-purpose", background: false))
        guard case .toolResult(_, TranscriptFixture.spawnToolUseID, false, .none, .some(TranscriptFixture.agentID), .none) = entries[3] else {
            Issue.record("\(entries[3])"); return
        }
        guard case .text = entries[4] else { Issue.record("\(entries[4])"); return }
        // Queued notification, then the peer hand-back, then the notification as a user record.
        guard case .agentFinished(_, TranscriptFixture.agentID, .completed) = entries[5] else { Issue.record("\(entries[5])"); return }
        guard case .handback(_, TranscriptFixture.agentID, "Transcripts are JSONL, one record per line.") = entries[6] else { Issue.record("\(entries[6])"); return }
        guard case .agentFinished(_, TranscriptFixture.agentID, .completed) = entries[7] else { Issue.record("\(entries[7])"); return }
    }

    @Test func subagentLines() throws {
        let entries = try TranscriptFixture.entries(TranscriptFixture.child)
        // prompt, (thinking: nothing), Bash call, its result, an error result, text, hand-back call + report, its result
        let kinds = entries.map { entry -> String in
            switch entry {
            case .prompt: "prompt"
            case .text: "text"
            case .toolCall(_, _, let name, _, _): "call:\(name)"
            case .toolResult(_, _, let isError, _, _, _): isError ? "error" : "result"
            case .handback: "handback"
            case .agentFinished: "finished"
            case .interrupted: "interrupted"
            }
        }
        #expect(kinds == ["prompt", "call:Bash", "result", "error", "text", "call:SubagentHandback", "handback", "result"])
        guard case .handback(_, TranscriptFixture.agentID, "Transcripts are JSONL; subagents live next to the session.") = entries[6] else { Issue.record("\(entries[6])"); return }
        guard case .toolResult(_, _, true, .some("Exit code 2"), .none, .none) = entries[3] else { Issue.record("\(entries[3])"); return }
    }

    @Test func meta() throws {
        let meta = try #require(AgentMeta.parse(try TranscriptFixture.data(TranscriptFixture.meta)))
        #expect(meta.agentType == "general-purpose")
        #expect(meta.description == "Research task")
        #expect(meta.toolUseID == TranscriptFixture.spawnToolUseID)
        #expect(meta.spawnDepth == 1)
        #expect(meta.background == false)
    }

    @Test func timestampsKeepMilliseconds() throws {
        let entries = try TranscriptFixture.entries(TranscriptFixture.main)
        #expect(abs(entries[3].at.timeIntervalSince(tsDate)) < 0.001)
    }
}

@Suite("Transcript line edge cases")
struct TranscriptLineTests {
    @Test(arguments: [
        "", "not json", "[1,2]", "{}",
        #"{"type":"assistant"}"#, // no timestamp
        #"{"type":"assistant","timestamp":"yesterday","message":{"content":[{"type":"text","text":"x"}]}}"#,
        #"{"type":"summary","timestamp":"2026-10-01T01:05:13.464Z","summary":"x"}"#,
        #"{"type":"cost-state","timestamp":"2026-10-01T01:05:13.464Z","totalCostUSD":1}"#,
        #"{"type":"assistant","timestamp":"2026-10-01T01:05:13.464Z","message":{"content":[{"type":"thinking","thinking":"x"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-10-01T01:05:13.464Z","message":{"content":[{"type":"text","text":"   "}]}}"#,
        #"{"type":"user","timestamp":"2026-10-01T01:05:13.464Z","isMeta":true,"message":{"content":"system reminder"}}"#,
    ])
    func producesNothing(json: String) {
        #expect(line(json).isEmpty)
    }

    @Test func timestampWithoutFraction() {
        let entries = line(#"{"type":"user","timestamp":"2026-10-01T01:05:13Z","message":{"content":"hi"}}"#)
        #expect(entries.count == 1)
        #expect(abs(entries[0].at.timeIntervalSince(tsDate.addingTimeInterval(-0.464))) < 0.001)
    }

    @Test func coordinatorMessageIsAContinuation() {
        let entries = line(#"{"type":"user","timestamp":"\#(ts)","isMeta":true,"origin":{"kind":"coordinator"},"message":{"content":"one more thing"}}"#)
        guard case .some(.prompt(_, "one more thing", true)) = entries.first else { Issue.record("\(entries)"); return }
    }

    @Test func interruption() {
        let entries = line(#"{"type":"user","timestamp":"\#(ts)","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#)
        guard case .some(.interrupted) = entries.first else { Issue.record("\(entries)"); return }
    }

    @Test func foregroundAgentResult() {
        let entries = line(#"""
        {"type":"user","timestamp":"\#(ts)","toolUseResult":{"status":"completed","agentId":"a1","content":[{"type":"text","text":"final answer"}]},
         "message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"final answer"}]}]}}
        """#.replacingOccurrences(of: "\n", with: ""))
        guard case .some(.toolResult(_, "t1", false, .none, .some("a1"), .some("final answer"))) = entries.first else { Issue.record("\(entries)"); return }
    }

    @Test(arguments: [("completed", AgentFinish.completed), ("failed", .failed), ("killed", .killed), ("blocked", .blocked)])
    func notificationStatuses(raw: String, expected: AgentFinish) {
        let text = "<task-notification>\\n<task-id>a1</task-id>\\n<status>\(raw)</status>\\n</task-notification>"
        let entries = line(#"{"type":"user","timestamp":"\#(ts)","origin":{"kind":"task-notification"},"message":{"content":"\#(text)"}}"#)
        guard case .some(.agentFinished(_, "a1", expected)) = entries.first else { Issue.record("\(entries)"); return }
    }

    @Test func unknownNotificationStatusIsIgnored() {
        let text = "<task-notification><task-id>a1</task-id><status>exploded</status></task-notification>"
        #expect(line(#"{"type":"queue-operation","operation":"enqueue","timestamp":"\#(ts)","content":"\#(text)"}"#).isEmpty)
    }

    @Test func severalNotificationsInOneQueuedCommand() {
        let text = "<task-notification><task-id>a1</task-id><status>completed</status></task-notification>"
            + "<task-notification><task-id>a2</task-id><status>failed</status></task-notification>"
        let entries = line(#"{"type":"attachment","timestamp":"\#(ts)","attachment":{"type":"queued_command","commandMode":"task-notification","prompt":"\#(text)"}}"#)
        #expect(entries.count == 2)
        guard case .agentFinished(_, "a2", .failed) = entries[1] else { Issue.record("\(entries)"); return }
    }

    @Test func backgroundAgentSpawn() {
        let entries = line(#"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"m1","content":[{"type":"tool_use","id":"t9","name":"Task","input":{"description":"Write tests","subagent_type":"qa","run_in_background":true,"prompt":"long"}}]}}"#)
        guard case .some(.toolCall(_, "t9", "Task", "Write tests", .some(AgentSpawn(description: "Write tests", agentType: "qa", background: true)))) = entries.first else {
            Issue.record("\(entries)"); return
        }
    }

    @Test func toolSummaryIsShortAndOneLine() {
        let long = String(repeating: "x", count: 400)
        let entries = line(#"{"type":"assistant","timestamp":"\#(ts)","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"echo \#(long)\nsecond line"}}]}}"#)
        guard case .some(.toolCall(_, _, _, let summary, .none)) = entries.first else { Issue.record("\(entries)"); return }
        #expect(summary.count <= TranscriptParser.maxSummaryLength)
        #expect(!summary.contains("\n"))
    }

    @Test func peerHandbackFallsBackToBody() {
        let entries = line(#"{"type":"user","timestamp":"\#(ts)","isMeta":true,"origin":{"kind":"peer","from":"a1","handback":true,"body":"report"},"message":{"content":[]}}"#)
        guard case .some(.handback(_, "a1", "report")) = entries.first else { Issue.record("\(entries)"); return }
    }

    @Test func nonHandbackPeerMessageIsIgnored() {
        #expect(line(#"{"type":"user","timestamp":"\#(ts)","isMeta":true,"origin":{"kind":"peer","from":"a1"},"message":{"content":"hi"}}"#).isEmpty)
    }
}
