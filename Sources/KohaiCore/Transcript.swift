import Foundation

// Claude Code transcripts: `<configDir>/projects/<slug>/<sessionId>.jsonl` for the main session and
// `<sessionId>/subagents/agent-<agentId>.jsonl` (+ `.meta.json`) per subagent. Append-only JSONL,
// one complete JSON object per line. The format is undocumented: everything here is read
// tolerantly, unknown record types and fields are ignored.

/// How the parent launched a subagent (input of its `Agent` tool call).
public struct AgentSpawn: Sendable, Equatable {
    public var description: String?
    public var agentType: String?
    public var background: Bool

    public init(description: String?, agentType: String?, background: Bool) {
        self.description = description
        self.agentType = agentType
        self.background = background
    }
}

/// Final status of a background subagent, from the parent's `<task-notification>`.
public enum AgentFinish: String, Sendable, Equatable {
    case completed
    case failed
    case killed
    case blocked
}

/// What one transcript line means for the agent map. Thinking blocks and bookkeeping records
/// produce nothing.
public enum TranscriptEntry: Sendable, Equatable {
    /// A prompt for this agent: the human's prompt in the main session or the task in a
    /// subagent. `continuation` marks a follow-up message that continues a finished subagent.
    case prompt(at: Date, text: String, continuation: Bool)
    /// Assistant text. One API message can be split over several lines that share `messageID`.
    case text(at: Date, messageID: String?, text: String)
    case toolCall(at: Date, id: String, name: String, summary: String, spawn: AgentSpawn?)
    /// `spawnedAgentID` is set when the result launched a subagent (`toolUseResult.agentId`);
    /// `agentResult` carries a foreground subagent's returned text.
    case toolResult(at: Date, toolUseID: String, isError: Bool, errorLine: String?, spawnedAgentID: String?, agentResult: String?)
    /// A subagent's final report, as delivered to the parent (peer hand-back) or written by the
    /// subagent itself (`SubagentHandback` tool call).
    case handback(at: Date, agentID: String, text: String)
    case agentFinished(at: Date, agentID: String, status: AgentFinish)
    case interrupted(at: Date)
}

extension TranscriptEntry {
    public var at: Date {
        switch self {
        case .prompt(let at, _, _), .text(let at, _, _), .toolCall(let at, _, _, _, _),
             .toolResult(let at, _, _, _, _, _), .handback(let at, _, _), .agentFinished(let at, _, _),
             .interrupted(let at):
            return at
        }
    }
}

/// Sidecar `agent-<id>.meta.json`.
public struct AgentMeta: Sendable, Equatable {
    public var agentType: String?
    public var description: String?
    public var name: String?
    public var toolUseID: String?
    public var parentAgentID: String?
    public var spawnDepth: Int?
    public var background: Bool

    public init(
        agentType: String? = nil, description: String? = nil, name: String? = nil, toolUseID: String? = nil,
        parentAgentID: String? = nil, spawnDepth: Int? = nil, background: Bool = false
    ) {
        self.agentType = agentType
        self.description = description
        self.name = name
        self.toolUseID = toolUseID
        self.parentAgentID = parentAgentID
        self.spawnDepth = spawnDepth
        self.background = background
    }

    public static func parse(_ data: Data) -> AgentMeta? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return AgentMeta(
            agentType: TranscriptParser.string(object["agentType"]),
            description: TranscriptParser.string(object["description"]),
            name: TranscriptParser.string(object["name"]),
            toolUseID: TranscriptParser.string(object["toolUseId"]),
            parentAgentID: TranscriptParser.string(object["parentAgentId"]),
            spawnDepth: object["spawnDepth"] as? Int,
            background: (object["requestShape"] as? String) == "background")
    }
}

public enum TranscriptParser {
    /// Step summaries are short: what the tool did, never its output.
    public static let maxSummaryLength = 160
    /// Assistant text and results keep more, but still bounded.
    public static let maxTextLength = 20_000

    /// Tool names that launch a subagent.
    static let spawnTools: Set<String> = ["Agent", "Task"]
    static let handbackTool = "SubagentHandback"

    /// Parses one JSONL line. Malformed lines and lines without a timestamp yield nothing.
    public static func entries(fromLine line: Data) -> [TranscriptEntry] {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String,
              let at = date(record["timestamp"])
        else { return [] }

        switch type {
        case "assistant":
            return assistantEntries(record, at: at)
        case "user":
            return userEntries(record, at: at)
        case "queue-operation", "attachment":
            // Background completions are queued before they reach the transcript as a user record.
            return notificationEntries(in: record, at: at)
        default:
            return []
        }
    }

    // MARK: Records

    private static func assistantEntries(_ record: [String: Any], at: Date) -> [TranscriptEntry] {
        let message = record["message"] as? [String: Any] ?? [:]
        let messageID = string(message["id"])
        var entries: [TranscriptEntry] = []
        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String ?? "" {
            case "text":
                if let text = clipped(string(block["text"]), to: maxTextLength) {
                    entries.append(.text(at: at, messageID: messageID, text: text))
                }
            case "tool_use":
                guard let id = string(block["id"]), let name = string(block["name"]) else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                if name == handbackTool, let agentID = string(record["agentId"]) {
                    entries.append(.toolCall(at: at, id: id, name: name, summary: "", spawn: nil))
                    if let text = clipped(longestString(in: input), to: maxTextLength) {
                        entries.append(.handback(at: at, agentID: agentID, text: text))
                    }
                    continue
                }
                var spawn: AgentSpawn?
                if spawnTools.contains(name) {
                    spawn = AgentSpawn(
                        description: string(input["description"]),
                        agentType: string(input["subagent_type"]),
                        background: input["run_in_background"] as? Bool ?? false)
                }
                entries.append(.toolCall(at: at, id: id, name: name, summary: toolSummary(input), spawn: spawn))
            default:
                continue // thinking, images, unknown blocks
            }
        }
        return entries
    }

    private static func userEntries(_ record: [String: Any], at: Date) -> [TranscriptEntry] {
        let origin = record["origin"] as? [String: Any]
        let originKind = origin?["kind"] as? String
        let content = (record["message"] as? [String: Any])?["content"]

        if originKind == "peer", origin?["handback"] as? Bool == true, let from = string(origin?["from"]) {
            let text = string(content) ?? string(origin?["body"]) ?? ""
            return [.handback(at: at, agentID: from, text: clipped(text, to: maxTextLength) ?? "")]
        }
        if originKind == "task-notification" || (string(content)?.contains("<task-notification>") ?? false) {
            return notificationEntries(inText: string(content) ?? "", at: at)
        }

        if let text = string(content) {
            if text.contains("[Request interrupted by user") { return [.interrupted(at: at)] }
            // Meta records (system reminders, hand-back echoes) are not prompts, except a
            // coordinator message that continues a subagent.
            if record["isMeta"] as? Bool == true, originKind != "coordinator" { return [] }
            return clipped(text, to: maxTextLength).map {
                [.prompt(at: at, text: $0, continuation: originKind == "coordinator")]
            } ?? []
        }

        var entries: [TranscriptEntry] = []
        let result = record["toolUseResult"] as? [String: Any]
        for block in content as? [[String: Any]] ?? [] {
            switch block["type"] as? String ?? "" {
            case "tool_result":
                guard let toolUseID = string(block["tool_use_id"]) else { continue }
                let isError = block["is_error"] as? Bool ?? false
                let text = resultText(block["content"])
                let spawned = string(result?["agentId"])
                let completed = spawned != nil && (result?["status"] as? String) == "completed"
                entries.append(.toolResult(
                    at: at,
                    toolUseID: toolUseID,
                    isError: isError,
                    errorLine: isError ? firstLine(text) : nil,
                    spawnedAgentID: spawned,
                    agentResult: completed ? clipped(nonEmpty(resultText(result?["content"])) ?? text, to: maxTextLength) : nil))
            case "text":
                guard let text = string(block["text"]) else { continue }
                if text.contains("[Request interrupted by user") {
                    entries.append(.interrupted(at: at))
                } else if record["isMeta"] as? Bool != true, let text = clipped(text, to: maxTextLength) {
                    entries.append(.prompt(at: at, text: text, continuation: originKind == "coordinator"))
                }
            default:
                continue
            }
        }
        return entries
    }

    private static func notificationEntries(in record: [String: Any], at: Date) -> [TranscriptEntry] {
        var found: [TranscriptEntry] = []
        func visit(_ value: Any) {
            if let text = value as? String, text.contains("<task-notification>") {
                found += notificationEntries(inText: text, at: at)
            } else if let object = value as? [String: Any] {
                object.values.forEach(visit)
            } else if let array = value as? [Any] {
                array.forEach(visit)
            }
        }
        visit(record["content"] as Any)
        visit(record["attachment"] as Any)
        return found
    }

    /// `<task-notification><task-id>…</task-id>…<status>completed</status>…</task-notification>`.
    /// Several notifications can share one string.
    static func notificationEntries(inText text: String, at: Date) -> [TranscriptEntry] {
        text.components(separatedBy: "<task-notification>").dropFirst().compactMap { chunk in
            guard let id = tag("task-id", in: chunk), let raw = tag("status", in: chunk),
                  let status = AgentFinish(rawValue: raw)
            else { return nil }
            return .agentFinished(at: at, agentID: id, status: status)
        }
    }

    // MARK: Helpers

    static func tag(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
        else { return nil }
        let value = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// What a tool call did, in one line: the first meaningful input field.
    static func toolSummary(_ input: [String: Any]) -> String {
        for field in ["description", "command", "file_path", "path", "pattern", "url", "query", "prompt"] {
            if let value = string(input[field]),
               let line = HookPayloadParser.normalizeMessage(value) {
                return String(line.prefix(maxSummaryLength))
            }
        }
        return ""
    }

    static func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    }

    static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return clipped(line.trimmingCharacters(in: .whitespaces), to: maxSummaryLength)
    }

    static func longestString(in object: [String: Any]) -> String? {
        object.values.compactMap { $0 as? String }.max { $0.count < $1.count }
    }

    static func clipped(_ text: String?, to limit: Int) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }

    static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// ISO 8601 with or without fractional seconds ("2026-10-01T01:05:13.464Z").
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return (try? fractionalISO.parse(text)) ?? (try? plainISO.parse(text))
    }

    // Format styles are Sendable values, so they can be shared (unlike ISO8601DateFormatter).
    private static let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO = Date.ISO8601FormatStyle()
}
