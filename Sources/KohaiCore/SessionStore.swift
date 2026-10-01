import Foundation

public enum SessionStatus: String, Sendable, Codable, CaseIterable {
    case working
    case needsInput
    case done

    public var label: String {
        switch self {
        case .working: "Working"
        case .needsInput: "Needs input"
        case .done: "Done"
        }
    }

    /// Sort order in the menu: blocked sessions first.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .working: 1
        case .done: 2
        }
    }
}

public struct SessionKey: Hashable, Sendable {
    public var agent: Agent
    public var sessionID: String

    public init(agent: Agent, sessionID: String) {
        self.agent = agent
        self.sessionID = sessionID
    }
}

public struct Session: Sendable, Equatable, Identifiable {
    public var key: SessionKey
    public var projectDir: String
    public var cwd: String
    public var configDir: String
    public var terminal: TerminalInfo
    public var status: SessionStatus
    public var statusSince: Date
    public var lastEventAt: Date
    public var message: String?
    /// Tool keys of permission requests not yet followed by a matching tool result.
    public var pendingPermissions: Set<String>

    public var id: SessionKey { key }
    public var agent: Agent { key.agent }

    public var projectName: String {
        let name = URL(fileURLWithPath: projectDir).lastPathComponent
        return name.isEmpty ? projectDir : name
    }

    /// Config dir with the home directory shortened to "~".
    public func accountLabel(home: String) -> String {
        abbreviateHome(configDir, home: home)
    }
}

public struct ProjectGroup: Sendable, Equatable, Identifiable {
    public var projectDir: String
    public var name: String
    public var sessions: [Session]
    public var id: String { projectDir }
}

/// Session state machine. Value type with no side effects; the app owns one instance on the main actor.
///
/// Ordering rule: an event older than the last event applied to its session is dropped, and an
/// event older than a session's removal (SessionEnd or manual clear) cannot bring it back.
public struct SessionStore: Sendable {
    /// How long removals are remembered to reject late events.
    public static let removalMemory: TimeInterval = 600

    public private(set) var sessions: [SessionKey: Session] = [:]
    private var removals: [SessionKey: Date] = [:]

    public init() {}

    /// Applies one event. Returns true when the store changed.
    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        let key = SessionKey(agent: event.agent, sessionID: event.sessionID)
        pruneRemovals(now: event.timestamp)

        if let removedAt = removals[key] {
            guard event.timestamp > removedAt else { return false }
            removals[key] = nil
        }

        if event.kind == .sessionEnd {
            let existing = sessions.removeValue(forKey: key)
            removals[key] = max(event.timestamp, existing?.lastEventAt ?? event.timestamp)
            return existing != nil
        }

        let isNew = sessions[key] == nil
        var session = sessions[key] ?? Session(
            key: key,
            projectDir: event.projectDir,
            cwd: event.cwd,
            configDir: event.configDir,
            terminal: event.terminal,
            status: .done,
            statusSince: event.timestamp,
            lastEventAt: event.timestamp,
            message: nil,
            pendingPermissions: []
        )
        if !isNew, event.timestamp < session.lastEventAt { return false }

        let before = session
        session.projectDir = event.projectDir
        session.cwd = event.cwd
        session.configDir = event.configDir
        session.terminal = event.terminal
        session.lastEventAt = event.timestamp
        if let message = event.message { session.message = message }

        var status = session.status
        switch event.kind {
        case .sessionStart:
            if isNew { status = .done }
        case .promptSubmit:
            session.pendingPermissions.removeAll()
            status = .working
        case .permissionRequest:
            session.pendingPermissions.insert(event.toolKey ?? "")
            status = .needsInput
        case .toolFinished:
            if let toolKey = event.toolKey { session.pendingPermissions.remove(toolKey) }
            if isNew || (status == .needsInput && session.pendingPermissions.isEmpty) {
                status = .working
            }
        case .stop:
            session.pendingPermissions.removeAll()
            status = .done
        case .sessionEnd:
            break // handled above
        }
        if isNew || status != session.status {
            session.status = status
            session.statusSince = event.timestamp
        }

        sessions[key] = session
        return isNew || session != before
    }

    /// Manual clear from the menu. A later event from the same session brings it back.
    public mutating func clear(_ key: SessionKey, at date: Date) {
        guard sessions.removeValue(forKey: key) != nil else { return }
        removals[key] = date
    }

    public var needsInputCount: Int {
        sessions.values.filter { $0.status == .needsInput }.count
    }

    /// Sessions grouped by project dir. Groups sorted by name then path; sessions by status, then
    /// longest in that status first.
    public var groups: [ProjectGroup] {
        let byProject = Dictionary(grouping: sessions.values, by: \.projectDir)
        return byProject.map { dir, sessions in
            ProjectGroup(
                projectDir: dir,
                name: sessions[0].projectName,
                sessions: sessions.sorted { lhs, rhs in
                    if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
                    if lhs.statusSince != rhs.statusSince { return lhs.statusSince < rhs.statusSince }
                    return lhs.key.sessionID < rhs.key.sessionID
                }
            )
        }
        .sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.projectDir < rhs.projectDir
        }
    }

    private mutating func pruneRemovals(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.removalMemory)
        removals = removals.filter { $0.value >= cutoff }
    }
}

/// "45s", "3m 12s", "2h 05m". Negative intervals (clock skew) show as "0s".
public func formatElapsed(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 { return "\(hours)h " + (minutes < 10 ? "0" : "") + "\(minutes)m" }
    if minutes > 0 { return "\(minutes)m \(seconds)s" }
    return "\(seconds)s"
}

public func abbreviateHome(_ path: String, home: String) -> String {
    guard !home.isEmpty, home != "/" else { return path }
    if path == home { return "~" }
    let prefix = home.hasSuffix("/") ? home : home + "/"
    guard path.hasPrefix(prefix) else { return path }
    return "~/" + path.dropFirst(prefix.count)
}
