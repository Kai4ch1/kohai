import Foundation

/// One agent config dir: the same thing a session's `configDir` is (CLAUDE_CONFIG_DIR / CODEX_HOME).
public struct AgentAccount: Hashable, Sendable, Identifiable, Codable {
    public var agent: Agent
    public var configDir: String

    public init(agent: Agent, configDir: String) {
        self.agent = agent
        self.configDir = configDir
    }

    public var id: String { "\(agent.rawValue):\(configDir)" }

    /// The file Kohai's hook entries live in.
    public var hookFilePath: String {
        let name = switch agent {
        case .claude: "settings.json"
        case .codex: "hooks.json"
        }
        return (configDir as NSString).appendingPathComponent(name)
    }
}

/// Finds agent config dirs in the home folder. The directory listing is injected so this stays pure.
public enum AccountDiscovery {
    /// Files or folders that only a Claude Code config dir has.
    static let claudeMarkers: Set<String> = [".claude.json", "settings.json", "projects", "history.jsonl", "file-history"]
    static let codexMarkers: Set<String> = ["config.toml", "auth.json", "sessions", "hooks.json"]

    /// - Parameter list: names inside a directory, or nil when it is not a readable directory.
    public static func discover(home: String, list: (String) -> [String]?) -> [AgentAccount] {
        guard let names = list(home) else { return [] }
        var found: [AgentAccount] = []
        for name in names.sorted() {
            let agent: Agent
            let markers: Set<String>
            if name == ".claude" || name.hasPrefix(".claude-") || name.hasPrefix(".claude_") {
                agent = .claude
                markers = claudeMarkers
            } else if name == ".codex" || name.hasPrefix(".codex-") || name.hasPrefix(".codex_") {
                agent = .codex
                markers = codexMarkers
            } else {
                continue
            }
            let path = (home as NSString).appendingPathComponent(name)
            guard let contents = list(path), !markers.isDisjoint(with: contents) else { continue }
            found.append(AgentAccount(agent: agent, configDir: path))
        }
        return found
    }

    /// Agent for a folder the user picked by hand: Codex only when it looks like one.
    public static func guessAgent(contents: [String]) -> Agent {
        let names = Set(contents)
        if !codexMarkers.isDisjoint(with: names) && claudeMarkers.isDisjoint(with: names) { return .codex }
        return .claude
    }
}

public enum HookConnection: Equatable, Sendable {
    case notConnected
    case connected
    /// Kohai entries exist but point at another kohai-hook or miss events (app moved or updated).
    case needsUpdate
    /// The hook file exists but is not a JSON object. Kohai never overwrites it.
    case unreadable(String)
}

public enum HookConfigError: Error, Equatable, Sendable {
    case unreadable(String)
}

/// Adds and removes Kohai's entries in an agent's hook file without touching anything else.
///
/// Both agents use the same shape: `{"hooks": {"<Event>": [{"matcher"?, "hooks": [{"type": "command", ...}]}]}}`.
/// Claude Code gets the exec form (`command` + `args`, no shell); Codex gets a shell command string.
public enum HookConfig {
    public static func events(for agent: Agent) -> [String] {
        switch agent {
        case .claude:
            ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd"]
        case .codex:
            // Codex has no PostToolUseFailure.
            ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    static func entry(agent: Agent, hookPath: String) -> [String: Any] {
        switch agent {
        case .claude:
            ["type": "command", "command": hookPath, "args": ["claude"], "timeout": 1]
        case .codex:
            ["type": "command", "command": "\(shellQuoted(hookPath)) codex"]
        }
    }

    public static func status(of file: Data?, agent: Agent, hookPath: String) -> HookConnection {
        let root: [String: Any]
        do {
            root = try object(from: file)
        } catch HookConfigError.unreadable(let reason) {
            return .unreadable(reason)
        } catch {
            return .unreadable("\(error)")
        }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let wanted = NSDictionary(dictionary: entry(agent: agent, hookPath: hookPath))
        let required = Set(events(for: agent))
        var anyKohai = false
        var exact = true
        // Exactly one current entry per required event, and no Kohai entries anywhere else
        // (a duplicate or an old path means the file needs rewriting).
        for event in Set(hooks.keys).union(required) {
            let kohai = commandEntries(in: hooks[event]).filter(isKohaiEntry)
            anyKohai = anyKohai || !kohai.isEmpty
            if required.contains(event) {
                if kohai.count != 1 || !wanted.isEqual(to: kohai[0]) { exact = false }
            } else if !kohai.isEmpty {
                exact = false
            }
        }
        if exact { return .connected }
        return anyKohai ? .needsUpdate : .notConnected
    }

    /// Replaces any Kohai entries with fresh ones for every event. A missing file counts as `{}`.
    public static func install(into file: Data?, agent: Agent, hookPath: String) throws -> Data {
        var root = try object(from: file)
        var hooks = removingKohai(from: root["hooks"] as? [String: Any] ?? [:])
        for event in events(for: agent) {
            var groups = hooks[event] as? [Any] ?? []
            groups.append(["hooks": [entry(agent: agent, hookPath: hookPath)]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try encode(root)
    }

    /// Removes every Kohai entry, and any group or event left empty by that.
    public static func uninstall(from file: Data?, agent: Agent) throws -> Data {
        var root = try object(from: file)
        let hooks = removingKohai(from: root["hooks"] as? [String: Any] ?? [:])
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return try encode(root)
    }

    // MARK: Helpers

    static func object(from file: Data?) throws -> [String: Any] {
        guard let file, !file.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: file)
        } catch {
            throw HookConfigError.unreadable("not valid JSON")
        }
        guard let object = parsed as? [String: Any] else { throw HookConfigError.unreadable("not a JSON object") }
        if let hooks = object["hooks"], !(hooks is [String: Any]) {
            throw HookConfigError.unreadable("\"hooks\" is not an object")
        }
        return object
    }

    static func encode(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// The `{"type": "command", ...}` dictionaries under one event.
    static func commandEntries(in event: Any?) -> [[String: Any]] {
        guard let groups = event as? [Any] else { return [] }
        return groups.flatMap { group -> [[String: Any]] in
            guard let group = group as? [String: Any], let entries = group["hooks"] as? [Any] else { return [] }
            return entries.compactMap { $0 as? [String: Any] }
        }
    }

    /// A command whose program is a file named `kohai-hook`, wherever it lives.
    static func isKohaiEntry(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return (programPath(of: command) as NSString).lastPathComponent == "kohai-hook"
    }

    /// First word of a shell command, honoring the single or double quotes Kohai writes.
    static func programPath(of command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if let quote = trimmed.first, quote == "'" || quote == "\"" {
            let rest = trimmed.dropFirst()
            if quote == "'" {
                // 'a'\''b' style: join quoted runs separated by \'
                var result = ""
                var remaining = Substring(rest)
                while let end = remaining.firstIndex(of: "'") {
                    result += remaining[..<end]
                    remaining = remaining[remaining.index(after: end)...]
                    guard remaining.hasPrefix("\\''") else { return result }
                    result += "'"
                    remaining = remaining.dropFirst(3)
                }
                return result + remaining
            }
            return String(rest.prefix { $0 != "\"" })
        }
        return String(trimmed.prefix { $0 != " " })
    }

    static func removingKohai(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [Any] else {
                result[event] = value // not ours to judge
                continue
            }
            let kept: [Any] = groups.compactMap { group in
                guard var group = group as? [String: Any], let entries = group["hooks"] as? [Any] else { return group }
                let remaining = entries.filter { !(($0 as? [String: Any]).map(isKohaiEntry) ?? false) }
                if remaining.isEmpty { return nil }
                group["hooks"] = remaining
                return group
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
