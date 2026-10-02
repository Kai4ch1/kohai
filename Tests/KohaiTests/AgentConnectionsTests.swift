import Foundation
import KohaiCore
import XCTest

@testable import Kohai

/// The app side of connecting: real file writes, against a throwaway home folder.
@MainActor
final class AgentConnectionsTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("kohai-home-\(UUID().uuidString)")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try Data(#"{"model": "opus"}"#.utf8).write(to: claude.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude-work/projects"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testConnectWritesHooksAndBackupThenDisconnectRemovesThem() throws {
        let settings = SettingsModel(
            store: SettingsStore(url: home.appendingPathComponent("settings.json")),
            defaults: UserDefaults(suiteName: "kohai-test-\(UUID().uuidString)")!)
        let connections = AgentConnections(home: home.path, settings: settings)
        connections.refresh()
        XCTAssertEqual(connections.accounts.map(\.configDir), [".claude", ".claude-work"].map { home.appendingPathComponent($0).path })
        XCTAssertEqual(connections.pendingCount, 2)

        connections.connect(connections.accounts.map(\.id))

        XCTAssertEqual(connections.notice, .connected)
        XCTAssertTrue(connections.states.values.allSatisfy { $0 == .connected }, "\(connections.states)")
        let claudeSettings = home.appendingPathComponent(".claude/settings.json")
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: claudeSettings)) as? [String: Any])
        XCTAssertEqual(written["model"] as? String, "opus")
        XCTAssertNotNil(written["hooks"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeSettings.path + ".kohai-backup"))
        // settings.json did not exist in .claude-work: created, nothing to back up.
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude-work/settings.json").path))

        let first = try XCTUnwrap(connections.accounts.first)
        connections.disconnect(first.id)
        XCTAssertEqual(connections.states[first.id], .notConnected)

        // Done after leaving one unconnected: remembered in the settings file, no longer hinted.
        connections.declinePending()
        XCTAssertEqual(connections.pendingCount, 0)
        XCTAssertEqual(settings.settings.declinedAccounts, [first.id])
    }

    func testLegacyUserDefaultsMoveIntoTheSettingsFileOnce() throws {
        let suite = "kohai-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let extra = AgentAccount(agent: .codex, configDir: "/opt/codex")
        defaults.set(try JSONEncoder().encode([extra]), forKey: SettingsModel.legacyExtraAccountsKey)
        defaults.set(["claude:/old"], forKey: SettingsModel.legacyDeclinedKey)
        let url = home.appendingPathComponent("settings.json")

        let model = SettingsModel(store: SettingsStore(url: url), defaults: defaults)
        XCTAssertEqual(model.settings.extraAccounts, [extra])
        XCTAssertEqual(model.settings.declinedAccounts, ["claude:/old"])
        XCTAssertNil(defaults.object(forKey: SettingsModel.legacyExtraAccountsKey))
        XCTAssertNil(defaults.object(forKey: SettingsModel.legacyDeclinedKey))
        // Persisted: a fresh load sees the same values.
        XCTAssertEqual(SettingsStore(url: url).load().settings.extraAccounts, [extra])
    }

    func testCorruptSettingsAreNotOverwrittenUntilTheUserChangesSomething() throws {
        let url = home.appendingPathComponent("settings.json")
        try Data("{broken".utf8).write(to: url)
        let model = SettingsModel(store: SettingsStore(url: url), defaults: UserDefaults(suiteName: "kohai-test-\(UUID().uuidString)")!)
        XCTAssertNotNil(model.warning)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{broken")
        model.update { $0.accounts.append(AccountLabel(configDir: "/a", name: "A", color: .blue)) }
        XCTAssertEqual(SettingsStore(url: url).load().settings.accounts.count, 1)
        XCTAssertEqual(try String(contentsOfFile: url.path + ".bak", encoding: .utf8), "{broken")
    }
}
