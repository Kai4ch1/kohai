import Foundation

public enum Agent: String, Codable, Sendable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// Normalized event kinds. Several hook events can map to one kind
/// (PostToolUse and PostToolUseFailure both become `toolFinished`).
public enum EventKind: String, Codable, Sendable, CaseIterable {
    case sessionStart
    case promptSubmit
    case permissionRequest
    case toolFinished
    case stop
    case sessionEnd
}

/// Where the agent runs. Used by `TerminalJump` to focus the session's tab.
public struct TerminalInfo: Codable, Sendable, Equatable {
    /// TERM_PROGRAM, e.g. "iTerm.app", "Apple_Terminal", "tmux".
    public var termProgram: String?
    /// GUID part of ITERM_SESSION_ID (matches AppleScript `unique id of session`).
    public var itermSessionID: String?
    /// Raw TERM_SESSION_ID.
    public var termSessionID: String?
    /// TMUX_PANE when running inside tmux.
    public var tmuxPane: String?
    /// Controlling terminal of the nearest ancestor that has one, e.g. "/dev/ttys003".
    public var tty: String?

    public init(
        termProgram: String? = nil,
        itermSessionID: String? = nil,
        termSessionID: String? = nil,
        tmuxPane: String? = nil,
        tty: String? = nil
    ) {
        self.termProgram = termProgram
        self.itermSessionID = itermSessionID
        self.termSessionID = termSessionID
        self.tmuxPane = tmuxPane
        self.tty = tty
    }
}

/// One normalized event, as sent from `kohai-hook` to the app.
public struct AgentEvent: Codable, Sendable, Equatable {
    public var agent: Agent
    public var kind: EventKind
    public var sessionID: String
    /// Project root (CLAUDE_PROJECT_DIR when available, otherwise cwd). Used for grouping.
    public var projectDir: String
    public var cwd: String
    /// Config dir that identifies the account, e.g. "/Users/me/.claude-work".
    public var configDir: String
    public var terminal: TerminalInfo
    /// Taken by the hook when it starts; used to order events.
    public var timestamp: Date
    /// Human-readable text for the menu, already normalized and truncated.
    public var message: String?
    /// Hash of tool name + tool input, linking a permission request to its tool result.
    public var toolKey: String?

    public init(
        agent: Agent,
        kind: EventKind,
        sessionID: String,
        projectDir: String,
        cwd: String,
        configDir: String,
        terminal: TerminalInfo,
        timestamp: Date,
        message: String? = nil,
        toolKey: String? = nil
    ) {
        self.agent = agent
        self.kind = kind
        self.sessionID = sessionID
        self.projectDir = projectDir
        self.cwd = cwd
        self.configDir = configDir
        self.terminal = terminal
        self.timestamp = timestamp
        self.message = message
        self.toolKey = toolKey
    }
}

/// JSON encoding used on the socket. Dates are seconds since 1970 (sub-millisecond precision).
public enum WireCodec {
    public static func encode(_ event: AgentEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(event)
    }

    public static func decode(_ data: Data) throws -> AgentEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AgentEvent.self, from: data)
    }
}
