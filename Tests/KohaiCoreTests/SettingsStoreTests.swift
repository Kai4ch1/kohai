import Foundation
import Testing
@testable import KohaiCore

@Suite("Settings store")
struct SettingsStoreTests {
    private let dir: URL
    private let store: SettingsStore

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kohai-settings-\(UUID().uuidString)")
        store = SettingsStore(url: dir.appendingPathComponent("Kohai/settings.json"))
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: store.url)
    }

    private var sample: KohaiSettings {
        let work = UUID()
        return KohaiSettings(
            accounts: [
                AccountLabel(configDir: "/Users/me/.claude", name: "Personal", color: .blue),
                AccountLabel(configDir: "/Users/me/.claude-work", name: "Work", color: .orange),
            ],
            spaces: [Space(id: work, name: "Work", color: .orange, symbol: "briefcase", rules: [
                SpaceRule(.account, "/Users/me/.claude-work"), SpaceRule(.gitRemote, "github.com/acme/*"),
            ])],
            notifications: NotificationSettings(enabled: true, mutedSpaces: [work]),
            extraAccounts: [AgentAccount(agent: .codex, configDir: "/opt/codex")],
            declinedAccounts: ["claude:/Users/me/.claude-old"])
    }

    @Test func missingFileGivesDefaultsWithoutWarning() {
        let (settings, warning) = store.load()
        #expect(settings == KohaiSettings())
        #expect(warning == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func roundTrip() throws {
        let saved = sample
        try store.save(saved)
        let (loaded, warning) = store.load()
        #expect(loaded == saved)
        #expect(warning == nil)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(text.contains("\"version\" : 1"))
    }

    @Test(arguments: ["{not json", "[1,2,3]", "", #"{"version": 1, "spaces": [{"name": 3}]}"#])
    func corruptFileIsBackedUpAndDefaultsLoad(text: String) throws {
        try write(text)
        let (settings, warning) = store.load()
        #expect(settings == KohaiSettings())
        guard case .unreadable(let backup)? = warning else {
            Issue.record("expected an unreadable warning, got \(String(describing: warning))")
            return
        }
        #expect(backup == store.url.path + ".bak")
        #expect(try String(contentsOfFile: backup, encoding: .utf8) == text)
        // The broken original stays until the user changes something.
        #expect(try String(contentsOf: store.url, encoding: .utf8) == text)
    }

    @Test func repeatedCorruptionNeverOverwritesAnOlderBackup() throws {
        try write("first broken")
        _ = store.load()
        try write("second broken")
        guard case .unreadable(let second)? = store.load().warning else {
            Issue.record("expected a warning")
            return
        }
        #expect(second == store.url.path + ".bak.2")
        #expect(try String(contentsOfFile: store.url.path + ".bak", encoding: .utf8) == "first broken")
    }

    @Test func versionZeroFileMigrates() throws {
        // Hand-written, no version field.
        try write(#"{"accounts": [{"configDir": "/a", "name": "A", "color": "green"}]}"#)
        let (settings, warning) = store.load()
        #expect(warning == nil)
        #expect(settings.version == KohaiSettings.currentVersion)
        #expect(settings.accounts == [AccountLabel(configDir: "/a", name: "A", color: .green)])
    }

    @Test func newerVersionIsKeptNotOverwritten() throws {
        try write(#"{"version": 99, "accounts": []}"#)
        let (settings, warning) = store.load()
        #expect(settings == KohaiSettings())
        #expect(warning == .newerVersion(99, backup: store.url.path + ".bak"))
    }

    @Test func unknownKeysAndMissingSectionsAreTolerated() throws {
        try write(#"{"version": 1, "futureThing": true, "spaces": []}"#)
        let (settings, warning) = store.load()
        #expect(warning == nil)
        #expect(settings == KohaiSettings())
    }

    @Test func concurrentSavesLeaveOneCompleteFile() async throws {
        let store = store
        let variants = (0..<40).map { i in
            KohaiSettings(accounts: [AccountLabel(configDir: "/dir/\(i)", name: "Account \(i)", color: .teal)])
        }
        await withTaskGroup(of: Void.self) { group in
            for settings in variants {
                group.addTask { try? store.save(settings) }
            }
        }
        let (loaded, warning) = store.load()
        #expect(warning == nil)
        #expect(variants.contains(loaded))
    }
}
