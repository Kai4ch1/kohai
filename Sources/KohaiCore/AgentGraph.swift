import Foundation

/// One agent: the main session (`agentID == nil`) or one of its subagents.
public struct AgentRef: Hashable, Sendable {
    public var session: SessionKey
    public var agentID: String?

    public init(session: SessionKey, agentID: String? = nil) {
        self.session = session
        self.agentID = agentID
    }

    public var isMain: Bool { agentID == nil }
}

public enum AgentStatus: String, Sendable, CaseIterable {
    case running
    case needsInput
    case done
    case error
    case interrupted

    public var isFinished: Bool { self == .done || self == .error || self == .interrupted }
}

/// One line in an agent's step log: a summary, never full tool input or output.
public struct AgentStep: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case prompt
        case message
        case tool
        case handback
    }

    public var id: String
    public var kind: Kind
    public var at: Date
    /// Tool name for `.tool`; empty otherwise.
    public var name: String
    public var summary: String
    public var finishedAt: Date?
    public var isError: Bool = false
    public var errorLine: String?

    /// A tool call still waiting for its result (running, or waiting for permission).
    public var isPending: Bool { kind == .tool && finishedAt == nil }
}

public struct AgentResult: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// The subagent's own report (SubagentHandback / peer hand-back).
        case handback
        /// A foreground run's returned text, or the last message (SubagentStop).
        case finalMessage
        /// `reports/<agentType>-<task>.md` in the project.
        case report(path: String)
    }

    public var text: String
    public var at: Date
    public var source: Source

    /// Higher wins: a report file beats the hand-back, which beats a last message.
    var rank: Int {
        switch source {
        case .finalMessage: 0
        case .handback: 1
        case .report: 2
        }
    }
}

public struct AgentNode: Identifiable, Sendable, Equatable {
    public var id: AgentRef
    public var parent: AgentRef?
    /// The parent's `Agent` tool call that launched this agent.
    public var toolUseID: String?
    /// Name the master gave the agent (meta.json `name`).
    public var customName: String?
    /// The task description (meta.json, else the parent's `Agent` call).
    public var taskDescription: String?
    public var agentType: String?
    public var background: Bool = false
    public var status: AgentStatus
    /// Timestamp of the event that last set `status`; older evidence can't override it.
    public var statusAt: Date
    public var startedAt: Date
    public var endedAt: Date?
    public var lastActivity: Date
    /// Latest assistant text: the live "what is it doing" view.
    public var latestText: String?
    public var result: AgentResult?
    public var steps: [AgentStep] = []
    /// Oldest steps dropped to keep memory bounded.
    public var droppedSteps = 0
    /// Permission requests (tool keys) from this agent still waiting for an answer.
    public var pendingPermissions: Set<String> = []

    /// Human name: given name, else task description, else agent type, else the id.
    /// Empty for a main session (the app names it after the session).
    public var name: String { customName ?? taskDescription ?? agentType ?? id.agentID ?? "" }
}

/// All agents Kohai knows about, built incrementally from hook events and transcript lines.
/// A value type with no I/O, like `SessionStore`; the app owns one on the main actor.
public struct AgentGraph: Sendable {
    public static let maxSteps = 500

    public private(set) var nodes: [AgentRef: AgentNode] = [:]
    /// Spawn calls seen in a parent before (or without) the child itself.
    private var spawns: [String: (parent: AgentRef, spawn: AgentSpawn, at: Date)] = [:]

    public init() {}

    // MARK: Queries

    public func node(_ ref: AgentRef) -> AgentNode? { nodes[ref] }

    /// Direct children. A subagent whose parent isn't known (yet) hangs under the main session,
    /// so nothing disappears from the map.
    public func children(of ref: AgentRef) -> [AgentNode] {
        nodes.values.filter { node in
            guard !node.id.isMain, node.id.session == ref.session, node.id != ref else { return false }
            if node.parent == ref { return true }
            return ref.isMain && (node.parent == nil || nodes[node.parent!] == nil)
        }
        .sorted(by: Self.launchOrder)
    }

    public func subagents(of session: SessionKey) -> [AgentNode] {
        nodes.values.filter { $0.id.session == session && !$0.id.isMain }.sorted(by: Self.launchOrder)
    }

    public struct Summary: Sendable, Equatable {
        public var total = 0
        public var running = 0
        public var needsInput = 0
    }

    /// Subagent counts for a session row ("3 agents · 1 waiting").
    public func summary(of session: SessionKey) -> Summary {
        var summary = Summary()
        for node in subagents(of: session) {
            summary.total += 1
            if node.status == .running { summary.running += 1 }
            if node.status == .needsInput { summary.needsInput += 1 }
        }
        return summary
    }

    static func launchOrder(_ a: AgentNode, _ b: AgentNode) -> Bool {
        if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
        return (a.id.agentID ?? "") < (b.id.agentID ?? "")
    }

    // MARK: Hooks

    /// Applies a hook event. Subagent start/stop and permission requests from inside a subagent
    /// arrive here instantly; transcripts fill in the rest.
    public mutating func apply(hook event: AgentEvent) {
        let session = SessionKey(agent: event.agent, sessionID: event.sessionID)
        if event.kind == .sessionEnd {
            removeSession(session)
            return
        }
        guard let agentID = event.agentID else {
            ensureMain(session, at: event.timestamp)
            return
        }
        let ref = AgentRef(session: session, agentID: agentID)
        ensureChild(ref, at: event.timestamp)
        update(ref) { node in
            node.agentType = event.agentType ?? node.agentType
            node.lastActivity = max(node.lastActivity, event.timestamp)
        }
        switch event.kind {
        case .subagentStart:
            // Also fires when a finished subagent is continued.
            setStatus(ref, .running, at: event.timestamp, reopen: true)
        case .subagentStop:
            setStatus(ref, .done, at: event.timestamp)
            if let message = event.message {
                offerResult(ref, AgentResult(text: message, at: event.timestamp, source: .finalMessage))
            }
        case .permissionRequest:
            update(ref) { $0.pendingPermissions.insert(event.toolKey ?? "") }
            setStatus(ref, .needsInput, at: event.timestamp)
        case .toolFinished:
            var cleared = false
            update(ref) { node in
                if let key = event.toolKey { node.pendingPermissions.remove(key) }
                cleared = node.status == .needsInput && node.pendingPermissions.isEmpty
            }
            if cleared { setStatus(ref, .running, at: event.timestamp) }
        case .sessionStart, .promptSubmit, .stop, .sessionEnd:
            break
        }
    }

    // MARK: Transcripts

    /// Applies lines parsed from `ref`'s own transcript (main file or `agent-<id>.jsonl`).
    public mutating func apply(_ entries: [TranscriptEntry], from ref: AgentRef) {
        for entry in entries { apply(entry, from: ref) }
    }

    public mutating func apply(meta: AgentMeta, for ref: AgentRef, at: Date) {
        ensureChild(ref, at: at)
        update(ref) { node in
            node.agentType = meta.agentType ?? node.agentType
            node.customName = meta.name ?? node.customName
            node.taskDescription = meta.description ?? node.taskDescription
            node.toolUseID = meta.toolUseID ?? node.toolUseID
            node.background = node.background || meta.background
            if let parentID = meta.parentAgentID {
                node.parent = AgentRef(session: ref.session, agentID: parentID)
            }
        }
        if let toolUseID = meta.toolUseID, let pending = spawns[toolUseID] {
            link(ref, toolUseID: toolUseID, parent: pending.parent, spawn: pending.spawn, at: pending.at)
        }
    }

    /// The transcript was replaced or truncated: its steps will be read again from the top.
    public mutating func resetSteps(of ref: AgentRef) {
        update(ref) { node in
            node.steps = []
            node.droppedSteps = 0
        }
    }

    public mutating func attachReport(path: String, text: String, at: Date, to ref: AgentRef) {
        offerResult(ref, AgentResult(text: text, at: at, source: .report(path: path)))
    }

    public mutating func removeSession(_ session: SessionKey) {
        nodes = nodes.filter { $0.key.session != session }
        spawns = spawns.filter { $0.value.parent.session != session }
    }

    /// The main session exists (named by the app); creates its node if needed.
    public mutating func ensureMain(_ session: SessionKey, at: Date) {
        let ref = AgentRef(session: session)
        guard nodes[ref] == nil else { return }
        nodes[ref] = AgentNode(
            id: ref, parent: nil, toolUseID: nil, agentType: nil,
            status: .running, statusAt: at, startedAt: at, lastActivity: at)
    }

    // MARK: Entry handling

    private mutating func apply(_ entry: TranscriptEntry, from ref: AgentRef) {
        if ref.isMain { ensureMain(ref.session, at: entry.at) } else { ensureChild(ref, at: entry.at) }
        update(ref) { $0.lastActivity = max($0.lastActivity, entry.at) }

        switch entry {
        case .prompt(let at, let text, let continuation):
            addStep(ref, AgentStep(id: "prompt-\(at.timeIntervalSince1970)", kind: .prompt, at: at, name: "", summary: Self.summary(text)))
            if continuation, !ref.isMain { setStatus(ref, .running, at: at, reopen: true) }

        case .text(let at, let messageID, let text):
            // Stable id, so re-reading a file never duplicates a step.
            let id = "text-" + HookPayloadParser.makeToolKey(toolName: messageID ?? "\(at.timeIntervalSince1970)", toolInput: text)
            addStep(ref, AgentStep(id: id, kind: .message, at: at, name: "", summary: Self.summary(text)))
            update(ref) { $0.latestText = text }

        case .toolCall(let at, let id, let name, let summary, let spawn):
            if name == TranscriptParser.handbackTool { break }
            addStep(ref, AgentStep(id: id, kind: .tool, at: at, name: name, summary: summary))
            if let spawn {
                spawns[id] = (ref, spawn, at)
                if let child = nodes.values.first(where: { $0.toolUseID == id && $0.id.session == ref.session }) {
                    link(child.id, toolUseID: id, parent: ref, spawn: spawn, at: at)
                }
            }

        case .toolResult(let at, let toolUseID, let isError, let errorLine, let spawnedAgentID, let agentResult):
            update(ref) { node in
                guard let index = node.steps.lastIndex(where: { $0.id == toolUseID }) else { return }
                node.steps[index].finishedAt = at
                node.steps[index].isError = isError
                node.steps[index].errorLine = errorLine
            }
            if let childID = spawnedAgentID {
                let child = AgentRef(session: ref.session, agentID: childID)
                ensureChild(child, at: at)
                if let pending = spawns[toolUseID] {
                    link(child, toolUseID: toolUseID, parent: ref, spawn: pending.spawn, at: pending.at)
                } else {
                    update(child) { node in
                        node.parent = ref
                        node.toolUseID = toolUseID
                    }
                }
                if let text = agentResult {
                    offerResult(child, AgentResult(text: text, at: at, source: .finalMessage))
                    setStatus(child, .done, at: at)
                } else if isError {
                    setStatus(child, .error, at: at)
                }
            }

        case .handback(let at, let agentID, let text):
            let child = AgentRef(session: ref.session, agentID: agentID)
            ensureChild(child, at: at)
            // The parent's copy arrives from the parent's file; link if the spawn wasn't seen.
            if child != ref, nodes[child]?.toolUseID == nil { update(child) { $0.parent = ref } }
            // The child's file and the parent's copy carry the same report: one step for both.
            let summary = Self.summary(text)
            let stepID = "handback-" + HookPayloadParser.makeToolKey(toolName: agentID, toolInput: summary)
            addStep(child, AgentStep(id: stepID, kind: .handback, at: at, name: "", summary: summary))
            offerResult(child, AgentResult(text: text, at: at, source: .handback))
            setStatus(child, .done, at: at)

        case .agentFinished(let at, let agentID, let status):
            let child = AgentRef(session: ref.session, agentID: agentID)
            // Background shell tasks use the same notification; only known agents count.
            guard nodes[child] != nil else { return }
            switch status {
            case .completed: setStatus(child, .done, at: at)
            case .failed: setStatus(child, .error, at: at)
            case .killed: setStatus(child, .interrupted, at: at)
            case .blocked: setStatus(child, .needsInput, at: at)
            }

        case .interrupted(let at):
            if nodes[ref]?.status == .running || nodes[ref]?.status == .needsInput {
                setStatus(ref, .interrupted, at: at)
            }
        }
    }

    // MARK: Mutation helpers

    private mutating func ensureChild(_ ref: AgentRef, at: Date) {
        guard nodes[ref] == nil else { return }
        ensureMain(ref.session, at: at)
        nodes[ref] = AgentNode(
            id: ref, parent: AgentRef(session: ref.session), toolUseID: nil, agentType: nil, status: .running, statusAt: at, startedAt: at, lastActivity: at)
    }

    private mutating func link(_ child: AgentRef, toolUseID: String, parent: AgentRef, spawn: AgentSpawn, at: Date) {
        update(child) { node in
            // meta.json's parentAgentId (nested agents) wins over the spawning file.
            if node.parent == nil || node.parent == AgentRef(session: child.session) { node.parent = parent }
            node.toolUseID = toolUseID
            // meta.json's description, when already read, stays.
            node.taskDescription = node.taskDescription ?? spawn.description
            node.agentType = node.agentType ?? spawn.agentType
            node.background = node.background || spawn.background
            node.startedAt = min(node.startedAt, at)
        }
    }

    /// Status changes follow time: evidence older than the current status is ignored, and a
    /// finished agent only reopens through `reopen` (a new prompt).
    private mutating func setStatus(_ ref: AgentRef, _ status: AgentStatus, at: Date, reopen: Bool = false) {
        update(ref) { node in
            guard at >= node.statusAt else { return }
            if node.status.isFinished, !status.isFinished, !reopen { return }
            node.status = status
            node.statusAt = at
            if status.isFinished {
                node.endedAt = at
                node.pendingPermissions = []
            } else {
                node.endedAt = nil
            }
        }
    }

    private mutating func offerResult(_ ref: AgentRef, _ result: AgentResult) {
        update(ref) { node in
            if let current = node.result, current.rank > result.rank { return }
            if let current = node.result, current.rank == result.rank, current.at > result.at { return }
            node.result = result
        }
    }

    private mutating func addStep(_ ref: AgentRef, _ step: AgentStep) {
        update(ref) { node in
            if node.steps.contains(where: { $0.id == step.id }) { return }
            // Steps come from several files (the parent's copy of a hand-back), so keep time order.
            let index = node.steps.lastIndex(where: { $0.at <= step.at }).map { $0 + 1 } ?? 0
            node.steps.insert(step, at: index)
            let overflow = node.steps.count - Self.maxSteps
            if overflow > 0 {
                node.steps.removeFirst(overflow)
                node.droppedSteps += overflow
            }
        }
    }

    private mutating func update(_ ref: AgentRef, _ change: (inout AgentNode) -> Void) {
        guard var node = nodes[ref] else { return }
        change(&node)
        nodes[ref] = node
    }

    static func summary(_ text: String) -> String {
        String((HookPayloadParser.normalizeMessage(text) ?? "").prefix(TranscriptParser.maxSummaryLength))
    }
}
