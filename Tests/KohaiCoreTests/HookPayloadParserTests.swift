import Foundation
import Testing
@testable import KohaiCore

private let now = Date(timeIntervalSince1970: 1_790_000_000)
private let terminal = TerminalInfo(termProgram: "iTerm.app", itermSessionID: "GUID-1", tty: "/dev/ttys004")
private let claudeEnv = ["HOME": "/Users/tester", "CLAUDE_PROJECT_DIR": "/Users/tester/dev/kohai-demo"]
private let codexEnv = ["HOME": "/Users/tester"]

func fixture(_ agent: String, _ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(agent)"),
        "missing fixture \(agent)/\(name).json"
    )
    return try Data(contentsOf: url)
}

private func parseEvent(_ data: Data, agent: Agent = .claude, env: [String: String]? = nil) throws -> AgentEvent {
    let result = HookPayloadParser.parse(data, agent: agent, environment: env ?? (agent == .claude ? claudeEnv : codexEnv), terminal: terminal, now: now)
    guard case .event(let event) = result else {
        Issue.record("expected an event, got \(result)")
        throw CancellationError()
    }
    return event
}

private func parse(_ text: String, agent: Agent = .claude) -> ParseResult {
    HookPayloadParser.parse(Data(text.utf8), agent: agent, environment: claudeEnv, terminal: terminal, now: now)
}

@Suite("Claude Code fixtures (captured from CLI 2.1.286)")
struct ClaudeFixtureTests {
    let sessionID = "dff5891b-76a1-482f-9357-a38ebac4e571"

    @Test(arguments: [
        ("SessionStart", EventKind.sessionStart),
        ("UserPromptSubmit", .promptSubmit),
        ("PermissionRequest", .permissionRequest),
        ("PostToolUse", .toolFinished),
        ("PostToolUseFailure", .toolFinished),
        ("Stop", .stop),
        ("SessionEnd", .sessionEnd),
    ])
    func mapsUsedEvents(name: String, kind: EventKind) throws {
        let event = try parseEvent(try fixture("claude", name))
        #expect(event.kind == kind)
        #expect(event.agent == .claude)
        #expect(event.sessionID == sessionID)
        #expect(event.cwd == "/Users/tester/dev/kohai-demo")
        #expect(event.projectDir == "/Users/tester/dev/kohai-demo")
        #expect(event.configDir == "/Users/tester/.claude-work")
        #expect(event.terminal == terminal)
        #expect(event.timestamp == now)
    }

    @Test(arguments: ["PreToolUse", "SubagentStop", "Notification-permission_prompt", "Notification-idle_prompt"])
    func ignoresUnusedEvents(name: String) throws {
        let result = HookPayloadParser.parse(try fixture("claude", name), agent: .claude, environment: claudeEnv, terminal: terminal, now: now)
        guard case .ignored = result else {
            Issue.record("expected .ignored, got \(result)")
            return
        }
    }

    @Test func messages() throws {
        #expect(try parseEvent(try fixture("claude", "UserPromptSubmit")).message
            == "Use the Bash tool to run exactly this command: touch kohai-perm-test.txt -- then reply with the single word done.")
        #expect(try parseEvent(try fixture("claude", "PermissionRequest")).message == "Permission: Bash — touch kohai-perm-test.txt")
        #expect(try parseEvent(try fixture("claude", "Stop")).message == "done")
        #expect(try parseEvent(try fixture("claude", "SessionStart")).message == nil)
        #expect(try parseEvent(try fixture("claude", "PostToolUse")).message == nil)
    }

    @Test func permissionAndToolResultShareToolKey() throws {
        let request = try parseEvent(try fixture("claude", "PermissionRequest"))
        let result = try parseEvent(try fixture("claude", "PostToolUse"))
        let failure = try parseEvent(try fixture("claude", "PostToolUseFailure"))
        #expect(request.toolKey != nil)
        #expect(request.toolKey == result.toolKey)
        #expect(request.toolKey == failure.toolKey)
    }

    @Test func toolKeyIgnoresKeyOrderButNotValues() {
        let a = HookPayloadParser.makeToolKey(toolName: "Bash", toolInput: ["command": "ls", "description": "x"])
        let b = HookPayloadParser.makeToolKey(toolName: "Bash", toolInput: ["description": "x", "command": "ls"])
        let c = HookPayloadParser.makeToolKey(toolName: "Bash", toolInput: ["command": "ls -la", "description": "x"])
        let d = HookPayloadParser.makeToolKey(toolName: "Edit", toolInput: ["command": "ls", "description": "x"])
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        #expect(a.count == 16)
    }

    @Test func projectDirFallsBackToCwd() throws {
        let event = try parseEvent(try fixture("claude", "Stop"), env: ["HOME": "/Users/tester"])
        #expect(event.projectDir == "/Users/tester/dev/kohai-demo")
    }
}

@Suite("Codex fixtures (built from codex-rs hook schemas, not live-captured)")
struct CodexFixtureTests {
    @Test(arguments: [
        ("SessionStart", EventKind.sessionStart),
        ("UserPromptSubmit", .promptSubmit),
        ("PermissionRequest", .permissionRequest),
        ("PostToolUse", .toolFinished),
        ("Stop", .stop),
        ("SessionEnd", .sessionEnd),
    ])
    func mapsEvents(name: String, kind: EventKind) throws {
        let event = try parseEvent(try fixture("codex", name), agent: .codex)
        #expect(event.kind == kind)
        #expect(event.agent == .codex)
        #expect(event.sessionID == "0199a8e2-4c1b-7d10-9a3e-6f2b8c1d0e55")
        #expect(event.projectDir == "/Users/tester/dev/api-server")
        #expect(event.configDir == "/Users/tester/.codex")
    }

    @Test func codexHomeIsTheAccount() throws {
        let event = try parseEvent(try fixture("codex", "Stop"), agent: .codex, env: ["HOME": "/Users/tester", "CODEX_HOME": "/Users/tester/.codex-work/"])
        #expect(event.configDir == "/Users/tester/.codex-work")
        #expect(event.message == "All 42 tests pass.")
    }

    @Test func permissionMatchesToolResult() throws {
        let request = try parseEvent(try fixture("codex", "PermissionRequest"), agent: .codex)
        let result = try parseEvent(try fixture("codex", "PostToolUse"), agent: .codex)
        #expect(request.toolKey == result.toolKey)
        #expect(request.message == "Permission: Bash — npm test")
    }
}

@Suite("Malformed and unknown input")
struct MalformedInputTests {
    @Test(arguments: [
        ("", "empty input"),
        ("   ", "malformed JSON"),
        ("{\"session_id\": \"a\", ", "malformed JSON"),
        ("not json", "malformed JSON"),
        ("[1, 2, 3]", "not a JSON object"),
        ("\"Stop\"", "malformed JSON"),
        ("{}", "missing hook_event_name"),
        ("{\"hook_event_name\": 42, \"session_id\": \"a\", \"cwd\": \"/x\"}", "missing hook_event_name"),
        ("{\"hook_event_name\": \"Stop\", \"cwd\": \"/x\"}", "missing session_id"),
        ("{\"hook_event_name\": \"Stop\", \"session_id\": 7, \"cwd\": \"/x\"}", "missing session_id"),
        ("{\"hook_event_name\": \"Stop\", \"session_id\": \"\", \"cwd\": \"/x\"}", "missing session_id"),
        ("{\"hook_event_name\": \"Stop\", \"session_id\": \"a\"}", "missing cwd"),
    ])
    func rejected(input: String, reason: String) {
        let result = parse(input)
        // A bare JSON string is either rejected by the parser or reported as a non-object.
        if input == "\"Stop\"" {
            #expect(result == .invalid("malformed JSON") || result == .invalid("not a JSON object"))
        } else {
            #expect(result == .invalid(reason))
        }
    }

    @Test func unknownEventIsIgnored() {
        #expect(parse("{\"hook_event_name\": \"SomethingNew\", \"session_id\": \"a\", \"cwd\": \"/x\"}") == .ignored("SomethingNew"))
    }

    @Test func unknownEventWithoutOtherFieldsIsIgnored() {
        #expect(parse("{\"hook_event_name\": \"Notification\"}") == .ignored("Notification"))
    }

    @Test func wrongTypedOptionalFieldsAreTolerated() throws {
        let result = parse("{\"hook_event_name\": \"Stop\", \"session_id\": \"a\", \"cwd\": \"/x\", \"last_assistant_message\": 5, \"transcript_path\": null}")
        guard case .event(let event) = result else {
            Issue.record("expected event, got \(result)")
            return
        }
        #expect(event.message == nil)
        #expect(event.configDir == "/Users/tester/.claude")
    }

    @Test func nonUTF8BytesAreRejected() {
        let result = HookPayloadParser.parse(Data([0xFF, 0xFE, 0x00]), agent: .claude, environment: claudeEnv, terminal: terminal, now: now)
        #expect(result == .invalid("malformed JSON"))
    }
}

@Suite("Account (config dir) derivation")
struct ConfigDirTests {
    @Test(arguments: [
        ("/Users/me/.claude/projects/-Users-me-p/s.jsonl", [String: String](), "/Users/me/.claude"),
        ("/Users/me/projects/cfg/projects/-Users-me-projects-p/s.jsonl", [:], "/Users/me/projects/cfg"),
        ("/weird/path.jsonl", ["CLAUDE_CONFIG_DIR": "/Users/me/.claude-b/"], "/Users/me/.claude-b"),
        ("", ["HOME": "/Users/me"], "/Users/me/.claude"),
    ])
    func claude(path: String, env: [String: String], expected: String) {
        #expect(HookPayloadParser.configDir(agent: .claude, transcriptPath: path.isEmpty ? nil : path, environment: env) == expected)
    }
}

@Suite("Message normalization")
struct MessageTests {
    @Test func collapsesWhitespace() {
        #expect(HookPayloadParser.normalizeMessage("  a\n\n b\t c  ") == "a b c")
        #expect(HookPayloadParser.normalizeMessage(" \n ") == nil)
    }

    @Test func truncates() throws {
        let long = String(repeating: "x", count: 1000)
        let message = try #require(HookPayloadParser.normalizeMessage(long))
        #expect(message.count == HookPayloadParser.maxMessageLength)
        #expect(message.hasSuffix("…"))
        let exact = String(repeating: "y", count: HookPayloadParser.maxMessageLength)
        #expect(HookPayloadParser.normalizeMessage(exact) == exact)
    }
}

@Suite("Wire codec")
struct WireCodecTests {
    @Test func roundTrip() throws {
        let event = AgentEvent(
            agent: .codex, kind: .permissionRequest, sessionID: "s", projectDir: "/p", cwd: "/p/sub",
            configDir: "/c", terminal: terminal, timestamp: Date(timeIntervalSince1970: 1_790_000_000.123),
            message: "m", toolKey: "k"
        )
        let decoded = try WireCodec.decode(try WireCodec.encode(event))
        #expect(decoded.sessionID == event.sessionID)
        #expect(decoded.kind == event.kind)
        #expect(decoded.terminal == event.terminal)
        #expect(abs(decoded.timestamp.timeIntervalSince(event.timestamp)) < 0.000_01)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try WireCodec.decode(Data("{\"agent\":\"vim\"}".utf8)) }
        #expect(throws: (any Error).self) { try WireCodec.decode(Data([0x00, 0x01])) }
    }
}
