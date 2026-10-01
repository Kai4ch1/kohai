import Foundation

// =============================================================================
// PRESENTATION-ONLY types for the dropdown. These are NOT the Core session
// models (none exist yet in this repo). When Core lands, map Core -> these in
// the app target; do not make views depend on Core directly.
// No networking, no state machine, no persistence here: just what a row shows.
// =============================================================================

enum AgentKind: Hashable, Sendable {
    case claudeCode
    case codex
    /// Any agent type the app doesn't recognise. Carries the raw type string.
    case unknown(String)

    var symbolName: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    func displayName(_ tone: CopyTone) -> String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .unknown: return Copy.unknownAgent.text(tone)
        }
    }
}

enum SessionStatus: Hashable, Sendable {
    case needsInput
    case working
    case done

    /// Display order inside a group: needs_input pinned first.
    var sortRank: Int {
        switch self {
        case .needsInput: return 0
        case .working: return 1
        case .done: return 2
        }
    }

    func label(_ tone: CopyTone) -> String {
        switch self {
        case .needsInput: return Copy.statusNeedsInput.text(tone)
        case .working: return Copy.statusWorking.text(tone)
        case .done: return Copy.statusDone.text(tone)
        }
    }
}

struct SessionRowModel: Identifiable, Hashable, Sendable {
    /// Session id (shown in mono where an ID is displayed).
    let id: String
    let agent: AgentKind
    let project: String
    let sessionName: String
    let account: String?
    let status: SessionStatus
    let secondsInStatus: Int
    let lastMessage: String
}

struct ProjectGroup: Identifiable, Hashable, Sendable {
    let project: String
    let sessions: [SessionRowModel]

    var id: String { project }
    var needsInputCount: Int { sessions.filter { $0.status == .needsInput }.count }
}

/// Display ordering only: groups by project, needs_input pinned to the top
/// (groups containing needs_input first, and within a group needs_input rows
/// first, longest-waiting first).
enum SessionGrouping {
    static func groups(_ sessions: [SessionRowModel]) -> [ProjectGroup] {
        let byProject = Dictionary(grouping: sessions, by: { $0.project })
        var result: [ProjectGroup] = []
        for (project, items) in byProject {
            result.append(ProjectGroup(project: project, sessions: items.sorted(by: rowOrder)))
        }
        result.sort { a, b in
            let aNeeds = a.needsInputCount > 0
            let bNeeds = b.needsInputCount > 0
            if aNeeds != bNeeds { return aNeeds }
            return a.project.localizedCaseInsensitiveCompare(b.project) == .orderedAscending
        }
        return result
    }

    static func rowOrder(_ a: SessionRowModel, _ b: SessionRowModel) -> Bool {
        if a.status.sortRank != b.status.sortRank { return a.status.sortRank < b.status.sortRank }
        if a.secondsInStatus != b.secondsInStatus { return a.secondsInStatus > b.secondsInStatus }
        return a.id < b.id
    }
}

enum TimeInStatus {
    /// Compact mono text: 3:12, 1h 04m, 2d 3h.
    static func short(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 3_600 { return String(format: "%d:%02d", s / 60, s % 60) }
        if s < 86_400 { return String(format: "%dh %02dm", s / 3_600, (s % 3_600) / 60) }
        return String(format: "%dd %dh", s / 86_400, (s % 86_400) / 3_600)
    }

    /// Spoken form for VoiceOver ("3 minutes, 12 seconds").
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
    }
}
