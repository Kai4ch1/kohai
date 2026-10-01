import Foundation

public enum ParseResult: Equatable, Sendable {
    /// A payload Kohai acts on.
    case event(AgentEvent)
    /// Well-formed payload for an event Kohai does not use (or does not know). The value is the event name.
    case ignored(String)
    /// Not a usable hook payload. The value says why.
    case invalid(String)
}

/// Turns a hook's stdin JSON into an `AgentEvent`. Pure: environment, terminal and clock are passed in.
public enum HookPayloadParser {
    public static let maxMessageLength = 300

    /// Hook event name → normalized kind. Every other event name is ignored.
    static let kinds: [String: EventKind] = [
        "SessionStart": .sessionStart,
        "UserPromptSubmit": .promptSubmit,
        "PermissionRequest": .permissionRequest,
        "PostToolUse": .toolFinished,
        "PostToolUseFailure": .toolFinished,
        "Stop": .stop,
        "SessionEnd": .sessionEnd,
    ]

    public static func parse(
        _ data: Data,
        agent: Agent,
        environment: [String: String],
        terminal: TerminalInfo,
        now: Date
    ) -> ParseResult {
        guard !data.isEmpty else { return .invalid("empty input") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .invalid("malformed JSON")
        }
        guard let payload = object as? [String: Any] else { return .invalid("not a JSON object") }
        guard let eventName = payload["hook_event_name"] as? String, !eventName.isEmpty else {
            return .invalid("missing hook_event_name")
        }
        guard let kind = kinds[eventName] else { return .ignored(eventName) }
        guard let sessionID = payload["session_id"] as? String, !sessionID.isEmpty else {
            return .invalid("missing session_id")
        }
        guard let cwd = payload["cwd"] as? String, !cwd.isEmpty else {
            return .invalid("missing cwd")
        }

        var message: String?
        var toolKey: String?
        switch kind {
        case .promptSubmit:
            message = (payload["prompt"] as? String).flatMap(normalizeMessage)
        case .permissionRequest:
            let toolName = payload["tool_name"] as? String ?? "tool"
            toolKey = makeToolKey(toolName: toolName, toolInput: payload["tool_input"])
            message = normalizeMessage("Permission: " + toolSummary(toolName: toolName, toolInput: payload["tool_input"]))
        case .toolFinished:
            let toolName = payload["tool_name"] as? String ?? "tool"
            toolKey = makeToolKey(toolName: toolName, toolInput: payload["tool_input"])
        case .stop:
            message = (payload["last_assistant_message"] as? String).flatMap(normalizeMessage)
        case .sessionStart, .sessionEnd:
            break
        }

        let projectDir: String
        if agent == .claude, let dir = environment["CLAUDE_PROJECT_DIR"], !dir.isEmpty {
            projectDir = dir
        } else {
            projectDir = cwd
        }

        return .event(AgentEvent(
            agent: agent,
            kind: kind,
            sessionID: sessionID,
            projectDir: projectDir,
            cwd: cwd,
            configDir: configDir(agent: agent, transcriptPath: payload["transcript_path"] as? String, environment: environment),
            terminal: terminal,
            timestamp: now,
            message: message,
            toolKey: toolKey
        ))
    }

    /// The account is the config dir. For Claude it is read from
    /// `<configDir>/projects/<encoded cwd>/<session>.jsonl`, then CLAUDE_CONFIG_DIR, then ~/.claude.
    /// For Codex it is CODEX_HOME, then ~/.codex.
    public static func configDir(agent: Agent, transcriptPath: String?, environment: [String: String]) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        switch agent {
        case .claude:
            if let path = transcriptPath {
                var parts = path.split(separator: "/", omittingEmptySubsequences: false)
                if parts.count >= 4, parts[parts.count - 3] == "projects" {
                    parts.removeLast(3)
                    let dir = parts.joined(separator: "/")
                    if !dir.isEmpty { return dir }
                }
            }
            if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty { return trimTrailingSlash(dir) }
            return home + "/.claude"
        case .codex:
            if let dir = environment["CODEX_HOME"], !dir.isEmpty { return trimTrailingSlash(dir) }
            return home + "/.codex"
        }
    }

    /// Collapses whitespace to single spaces and truncates. Returns nil for blank text.
    public static func normalizeMessage(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxMessageLength else { return collapsed }
        return String(collapsed.prefix(maxMessageLength - 1)) + "…"
    }

    static func toolSummary(toolName: String, toolInput: Any?) -> String {
        guard let input = toolInput as? [String: Any] else { return toolName }
        for field in ["command", "file_path", "path", "url", "pattern"] {
            if let value = input[field] as? String, !value.isEmpty {
                return "\(toolName) — \(value)"
            }
        }
        return toolName
    }

    /// Stable hash of tool name + canonical (key-sorted) tool input. The input itself never leaves the hook.
    public static func makeToolKey(toolName: String, toolInput: Any?) -> String {
        let wrapper: [String: Any] = ["name": toolName, "input": toolInput ?? NSNull()]
        let canonical = (try? JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys])) ?? Data(toolName.utf8)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in canonical {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
