import Foundation
import Testing
@testable import KohaiCore

private let hook = "/Applications/Kohai.app/Contents/MacOS/kohai-hook"

private func json(_ string: String) -> Data { Data(string.utf8) }

private func parse(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

@Suite("Account discovery")
struct AccountDiscoveryTests {
    private let tree: [String: [String]] = [
        "/Users/me": [".claude", ".claude-work", ".claude.json", ".claude-empty", ".codex", ".codexbar", "dev", ".claude_old"],
        "/Users/me/.claude": ["settings.json", "projects", "history.jsonl"],
        "/Users/me/.claude-work": [".claude.json", "file-history"],
        "/Users/me/.claude-empty": ["cache"],
        "/Users/me/.codex": ["config.toml", "sessions"],
        "/Users/me/.codexbar": ["config.toml"],
        "/Users/me/.claude_old": ["projects"],
    ]

    @Test func findsConfigDirsWithMarkers() {
        let found = AccountDiscovery.discover(home: "/Users/me") { tree[$0] }
        #expect(found == [
            AgentAccount(agent: .claude, configDir: "/Users/me/.claude"),
            AgentAccount(agent: .claude, configDir: "/Users/me/.claude-work"),
            AgentAccount(agent: .claude, configDir: "/Users/me/.claude_old"),
            AgentAccount(agent: .codex, configDir: "/Users/me/.codex"),
        ])
    }

    @Test func unreadableHomeFindsNothing() {
        #expect(AccountDiscovery.discover(home: "/nope") { _ in nil }.isEmpty)
    }

    @Test func hookFileDependsOnAgent() {
        #expect(AgentAccount(agent: .claude, configDir: "/a").hookFilePath == "/a/settings.json")
        #expect(AgentAccount(agent: .codex, configDir: "/b").hookFilePath == "/b/hooks.json")
    }

    @Test func guessesAgentForPickedFolder() {
        #expect(AccountDiscovery.guessAgent(contents: ["config.toml", "auth.json"]) == .codex)
        #expect(AccountDiscovery.guessAgent(contents: ["settings.json", "config.toml"]) == .claude)
        #expect(AccountDiscovery.guessAgent(contents: []) == .claude)
    }
}

@Suite("Hook config")
struct HookConfigTests {
    @Test(arguments: [Agent.claude, .codex])
    func installIntoMissingFileConnects(agent: Agent) throws {
        let data = try HookConfig.install(into: nil, agent: agent, hookPath: hook)
        #expect(HookConfig.status(of: data, agent: agent, hookPath: hook) == .connected)
        let hooks = parse(data)["hooks"] as? [String: Any] ?? [:]
        #expect(Set(hooks.keys) == Set(HookConfig.events(for: agent)))
    }

    @Test func claudeUsesExecFormAndCodexAShellCommand() throws {
        let claude = HookConfig.commandEntries(in: (parse(try HookConfig.install(into: nil, agent: .claude, hookPath: hook))["hooks"] as? [String: Any])?["Stop"])
        #expect(claude.first?["command"] as? String == hook)
        #expect(claude.first?["args"] as? [String] == ["claude"])

        let spaced = "/Users/me/My Apps/Kohai.app/Contents/MacOS/kohai-hook"
        let codex = HookConfig.commandEntries(in: (parse(try HookConfig.install(into: nil, agent: .codex, hookPath: spaced))["hooks"] as? [String: Any])?["Stop"])
        #expect(codex.first?["command"] as? String == "'\(spaced)' codex")
        #expect(codex.first?["args"] == nil)
    }

    @Test func installKeepsEverythingElse() throws {
        let original = json("""
            {"model": "opus", "permissions": {"allow": ["Bash(ls)"]},
             "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "/usr/local/bin/notify"}]}],
                       "PreCompact": [{"hooks": [{"type": "command", "command": "echo hi"}]}]}}
            """)
        let installed = parse(try HookConfig.install(into: original, agent: .claude, hookPath: hook))
        #expect(installed["model"] as? String == "opus")
        #expect((installed["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])
        let hooks = installed["hooks"] as? [String: Any] ?? [:]
        let stop = HookConfig.commandEntries(in: hooks["Stop"]).compactMap { $0["command"] as? String }
        #expect(stop == ["/usr/local/bin/notify", hook])
        #expect(HookConfig.commandEntries(in: hooks["PreCompact"]).count == 1)
    }

    @Test func installTwiceDoesNotDuplicate() throws {
        let once = try HookConfig.install(into: nil, agent: .claude, hookPath: hook)
        let twice = try HookConfig.install(into: once, agent: .claude, hookPath: hook)
        #expect(once == twice)
    }

    @Test func movedAppNeedsUpdateAndReinstallReplacesOldPath() throws {
        let old = try HookConfig.install(into: nil, agent: .claude, hookPath: "/old/place/kohai-hook")
        #expect(HookConfig.status(of: old, agent: .claude, hookPath: hook) == .needsUpdate)
        let fixed = try HookConfig.install(into: old, agent: .claude, hookPath: hook)
        #expect(HookConfig.status(of: fixed, agent: .claude, hookPath: hook) == .connected)
        let all = (parse(fixed)["hooks"] as? [String: Any] ?? [:]).values.flatMap(HookConfig.commandEntries(in:))
        #expect(!all.contains { ($0["command"] as? String) == "/old/place/kohai-hook" })
    }

    @Test func missingEventOrStrayEntryNeedsUpdate() throws {
        var root = parse(try HookConfig.install(into: nil, agent: .claude, hookPath: hook))
        var hooks = root["hooks"] as! [String: Any]
        hooks.removeValue(forKey: "SessionEnd")
        root["hooks"] = hooks
        let missing = try JSONSerialization.data(withJSONObject: root)
        #expect(HookConfig.status(of: missing, agent: .claude, hookPath: hook) == .needsUpdate)

        let stray = json(#"{"hooks": {"Notification": [{"hooks": [{"type": "command", "command": "/x/kohai-hook"}]}]}}"#)
        #expect(HookConfig.status(of: stray, agent: .claude, hookPath: hook) == .needsUpdate)
    }

    @Test func uninstallRemovesOnlyKohai() throws {
        let original = json(#"{"theme": "dark", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/notify"}]}]}}"#)
        let installed = try HookConfig.install(into: original, agent: .claude, hookPath: hook)
        let removed = try HookConfig.uninstall(from: installed, agent: .claude)
        #expect(HookConfig.status(of: removed, agent: .claude, hookPath: hook) == .notConnected)
        let root = parse(removed)
        #expect(root["theme"] as? String == "dark")
        #expect(Set((root["hooks"] as? [String: Any] ?? [:]).keys) == ["Stop"])

        let onlyKohai = try HookConfig.uninstall(from: try HookConfig.install(into: nil, agent: .codex, hookPath: hook), agent: .codex)
        #expect(parse(onlyKohai).isEmpty)
    }

    @Test func emptyOrMissingFileIsNotConnected() {
        #expect(HookConfig.status(of: nil, agent: .claude, hookPath: hook) == .notConnected)
        #expect(HookConfig.status(of: json("  \n"), agent: .claude, hookPath: hook) == .notConnected)
        #expect(HookConfig.status(of: json("{}"), agent: .codex, hookPath: hook) == .notConnected)
    }

    @Test func brokenFilesAreNeverRewritten() {
        for bad in ["{not json", "[1, 2]", #"{"hooks": []}"#] {
            #expect(HookConfig.status(of: json(bad), agent: .claude, hookPath: hook) != .notConnected)
            #expect(throws: HookConfigError.self) { try HookConfig.install(into: json(bad), agent: .claude, hookPath: hook) }
            #expect(throws: HookConfigError.self) { try HookConfig.uninstall(from: json(bad), agent: .claude) }
        }
    }

    @Test func recognisesKohaiCommands() {
        #expect(HookConfig.programPath(of: "'/a b/kohai-hook' codex") == "/a b/kohai-hook")
        #expect(HookConfig.programPath(of: #""/a b/kohai-hook" codex"#) == "/a b/kohai-hook")
        #expect(HookConfig.programPath(of: "'/it'\\''s/kohai-hook' codex") == "/it's/kohai-hook")
        #expect(HookConfig.programPath(of: "/x/kohai-hook codex") == "/x/kohai-hook")
        #expect(HookConfig.isKohaiEntry(["command": "/x/kohai-hook"]))
        #expect(!HookConfig.isKohaiEntry(["command": "/x/kohai-hooks"]))
        #expect(!HookConfig.isKohaiEntry(["command": "echo kohai-hook"]))
        #expect(!HookConfig.isKohaiEntry(["type": "command"]))
        #expect(HookConfig.shellQuoted("/it's") == "'/it'\\''s'")
    }
}
