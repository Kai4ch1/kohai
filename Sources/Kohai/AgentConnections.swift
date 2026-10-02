import AppKit
import KohaiCore
import Observation
import os

private let log = Logger(subsystem: "io.github.kai4ch1.kohai", category: "connections")

enum ConnectNotice: Equatable {
    /// Hooks load at session start, so running sessions need a restart.
    case connected
    /// (file, reason) per account that could not be changed.
    case failed([HookFileFailure])
}

struct HookFileFailure: Equatable {
    let file: String
    let reason: String
}

/// Which agent accounts exist and whether Kohai's hook is in each one. Reads hook files on
/// `refresh()`; writes only from `connect` / `disconnect`, i.e. only after the user clicked.
@MainActor
@Observable
final class AgentConnections {
    private(set) var accounts: [AgentAccount] = []
    private(set) var states: [AgentAccount.ID: HookConnection] = [:]
    /// Restart reminder after connecting, or what went wrong. Cleared on the next action.
    private(set) var notice: ConnectNotice?

    /// The kohai-hook next to the running app binary (build/Kohai.app or wherever it was moved).
    let hookPath: String
    private let home: String
    @ObservationIgnored private var seenConfigDirs: [AgentAccount] = []
    private var declined = Set(UserDefaults.standard.stringArray(forKey: AgentConnections.declinedKey) ?? [])

    private static let extraAccountsKey = "extraAccounts"
    private static let declinedKey = "declinedAccounts"

    init(home: String = NSHomeDirectory()) {
        self.home = home
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        hookPath = executable.deletingLastPathComponent().appendingPathComponent("kohai-hook").path
    }

    var hasConnectedAccount: Bool { states.values.contains(.connected) }

    /// Accounts the hint should mention: not connected (and not passed over by the user), or
    /// connected to an old kohai-hook, which always counts because it silently stopped working.
    var pendingCount: Int {
        states.filter { id, state in
            state == .needsUpdate || (state == .notConnected && !declined.contains(id))
        }.count
    }

    /// The user reviewed the list and left these unticked: stop hinting about them.
    func declinePending() {
        let pending = states.filter { $0.value == .notConnected }.map(\.key)
        declined.formUnion(pending)
        UserDefaults.standard.set(Array(declined), forKey: Self.declinedKey)
    }

    /// Re-reads everything. Cheap: a home listing plus one small file per account.
    /// - Parameter seen: accounts that sessions came from; they show up even when discovery misses them.
    func refresh(seen: [AgentAccount] = []) {
        seenConfigDirs = seen
        let fm = FileManager.default
        var found = AccountDiscovery.discover(home: home) { try? fm.contentsOfDirectory(atPath: $0) }
        for account in extraAccounts + seen where !found.contains(account) {
            found.append(account)
        }
        accounts = found
        states = Dictionary(uniqueKeysWithValues: found.map { account in
            let data = fm.contents(atPath: account.hookFilePath)
            return (account.id, HookConfig.status(of: data, agent: account.agent, hookPath: hookPath))
        })
        log.debug("refresh: \(self.states.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "), privacy: .public)")
    }

    func connect(_ ids: [AgentAccount.ID]) {
        log.info("connect requested: \(ids, privacy: .public); known: \(self.accounts.map(\.id), privacy: .public)")
        notice = nil
        var failures: [HookFileFailure] = []
        for account in accounts where ids.contains(account.id) {
            do {
                try rewrite(account) { try HookConfig.install(into: $0, agent: account.agent, hookPath: hookPath) }
                log.info("connected \(account.hookFilePath, privacy: .public)")
            } catch {
                log.error("connect failed for \(account.hookFilePath, privacy: .public): \(error, privacy: .public)")
                failures.append(failure(account, error))
            }
        }
        refresh(seen: seenConfigDirs)
        notice = failures.isEmpty ? .connected : .failed(failures)
    }

    func disconnect(_ id: AgentAccount.ID) {
        notice = nil
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do {
            try rewrite(account) { try HookConfig.uninstall(from: $0, agent: account.agent) }
            log.info("disconnected \(account.hookFilePath, privacy: .public)")
        } catch {
            log.error("disconnect failed for \(account.hookFilePath, privacy: .public): \(error, privacy: .public)")
            notice = .failed([failure(account, error)])
        }
        refresh(seen: seenConfigDirs)
    }

    /// Folder picker for config dirs discovery cannot see (e.g. outside the home folder).
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: home)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let account = AgentAccount(agent: AccountDiscovery.guessAgent(contents: contents), configDir: url.path)
        var extras = extraAccounts
        if !extras.contains(account) {
            extras.append(account)
            extraAccounts = extras
        }
        refresh(seen: seenConfigDirs)
    }

    // MARK: Files

    /// Backup next to the file, then an atomic write that keeps the file's permissions.
    private func rewrite(_ account: AgentAccount, _ transform: (Data?) throws -> Data) throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: account.hookFilePath)
        let existing = fm.contents(atPath: url.path)
        let updated = try transform(existing)
        guard updated != existing else { return }
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        if let existing {
            try existing.write(to: url.appendingPathExtension("kohai-backup"), options: .atomic)
        }
        try updated.write(to: url, options: .atomic)
        if let permissions = attributes?[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func failure(_ account: AgentAccount, _ error: Error) -> HookFileFailure {
        let reason: String
        switch error {
        case HookConfigError.unreadable(let why): reason = why
        default: reason = error.localizedDescription
        }
        return HookFileFailure(file: abbreviateHome(account.hookFilePath, home: home), reason: reason)
    }

    private var extraAccounts: [AgentAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.extraAccountsKey) else { return [] }
            return (try? JSONDecoder().decode([AgentAccount].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.extraAccountsKey)
        }
    }
}
