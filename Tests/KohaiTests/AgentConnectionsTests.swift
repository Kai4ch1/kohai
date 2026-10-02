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
        let connections = AgentConnections(home: home.path)
        connections.refresh()
        XCTAssertEqual(connections.accounts.map(\.configDir), [".claude", ".claude-work"].map { home.appendingPathComponent($0).path })
        XCTAssertEqual(connections.pendingCount, 2)

        connections.connect(connections.accounts.map(\.id))

        XCTAssertEqual(connections.notice, .connected)
        XCTAssertTrue(connections.states.values.allSatisfy { $0 == .connected }, "\(connections.states)")
        let settings = home.appendingPathComponent(".claude/settings.json")
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual(written["model"] as? String, "opus")
        XCTAssertNotNil(written["hooks"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path + ".kohai-backup"))
        // settings.json did not exist in .claude-work: created, nothing to back up.
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude-work/settings.json").path))

        let first = try XCTUnwrap(connections.accounts.first)
        connections.disconnect(first.id)
        XCTAssertEqual(connections.states[first.id], .notConnected)
    }
}
