import AppKit
import KohaiCore
import SwiftUI

/// The agent map for one project in the main window. Maps the Core graph onto the design's
/// presentation models and follows the sessions' transcripts while it is on screen.
struct AgentMapContainer: View {
    let model: AppModel
    let project: String
    let sessions: [Session]
    var onShowSessions: () -> Void = {}

    @State private var selection: String?

    @Environment(\.kohaiCopyTone) private var tone

    private var graph: AgentGraph { model.agentMap.graph }
    private var keys: [SessionKey] {
        sessions.sorted { $0.statusSince < $1.statusSince }.map(\.key)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            AgentMapScreen(
                project: project,
                map: presentation(now: context.date),
                inspector: inspector(now: context.date),
                selection: $selection,
                onShowSessions: onShowSessions,
                onOpenReport: { path in NSWorkspace.shared.open(URL(fileURLWithPath: path)) })
        }
        // Restarts when the set of sessions changes; cancelled when the map closes.
        .task(id: keys.map(\.sessionID)) {
            await model.agentMap.follow(sessions)
        }
    }

    // MARK: Mapping

    private func presentation(now: Date) -> AgentMapPresentation {
        let layout = AgentTreeLayout(graph: graph, sessions: keys)
        let nodes = layout.positions.compactMap { entry -> AgentNodeModel? in
            let (ref, position) = (entry.key, entry.value)
            guard let node = graph.node(ref) else { return nil }
            return AgentNodeModel(
                id: Self.id(for: ref),
                name: name(of: node),
                subtitle: subtitle(of: node),
                state: state(of: node),
                isMain: ref.isMain,
                elapsed: TimeInStatus.short(Int(elapsed(of: node, now: now))),
                column: position.column,
                level: position.level)
        }
        return AgentMapPresentation(
            nodes: nodes.sorted { ($0.level, $0.column) < ($1.level, $1.column) },
            edges: layout.edges.map { AgentEdgeModel(from: Self.id(for: $0.from), to: Self.id(for: $0.to)) },
            columns: layout.columns,
            levels: layout.levels)
    }

    private func inspector(now: Date) -> AgentInspectorModel? {
        guard let selection, let ref = keys.lazy.compactMap({ Self.ref(forID: selection, in: $0) }).first,
              let node = graph.node(ref)
        else { return nil }
        let time = Date.FormatStyle(date: .omitted, time: .standard)
        return AgentInspectorModel(
            id: selection,
            name: name(of: node),
            subtitle: subtitle(of: node),
            state: state(of: node),
            elapsed: TimeInStatus.short(Int(elapsed(of: node, now: now))),
            steps: node.steps.map { step in
                AgentStepModel(
                    id: step.id,
                    time: step.at.formatted(time),
                    kind: Self.kind(of: step),
                    summary: step.summary,
                    pending: step.isPending,
                    isError: step.isError,
                    errorLine: step.errorLine)
            },
            earlierSteps: node.droppedSteps,
            live: node.latestText,
            result: node.result?.text,
            resultSource: node.result.map { Self.source(of: $0) })
    }

    private static func kind(of step: AgentStep) -> AgentStepModel.Kind {
        switch step.kind {
        case .prompt: .prompt
        case .message: .message
        case .tool: .tool(step.name)
        case .handback: .handback
        }
    }

    private static func source(of result: AgentResult) -> AgentResultSource {
        switch result.source {
        case .handback: .handback
        case .finalMessage: .lastMessage
        case .report(let path): .report(fileName: (path as NSString).lastPathComponent, path: path)
        }
    }

    private func session(_ key: SessionKey) -> Session? {
        sessions.first { $0.key == key }
    }

    private func name(of node: AgentNode) -> String {
        guard node.id.isMain else { return node.name }
        guard let session = session(node.id.session) else { return Copy.mapMain.text(tone) }
        return SessionRowModel.name(for: session)
    }

    private func subtitle(of node: AgentNode) -> String {
        if node.id.isMain {
            let session = session(node.id.session)
            return [Copy.mapMain.text(tone), session.map { model.settings.settings.label(forConfigDir: $0.configDir)?.name ?? $0.accountLabel(home: model.home) }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        var parts = [node.agentType ?? "agent"]
        if node.background { parts.append(Copy.mapBackground.text(tone)) }
        return parts.joined(separator: " · ")
    }

    /// The main session's status is the session's own (hooks); subagents carry theirs.
    private func state(of node: AgentNode) -> AgentState {
        if node.id.isMain, let session = session(node.id.session) {
            switch session.status {
            case .working: return .running
            case .needsInput: return .needsInput
            case .done: return .done
            }
        }
        switch node.status {
        case .running: return .running
        case .needsInput: return .needsInput
        case .done: return .done
        case .error: return .failed
        case .interrupted: return .interrupted
        }
    }

    private func elapsed(of node: AgentNode, now: Date) -> TimeInterval {
        if node.id.isMain, let session = session(node.id.session) {
            return now.timeIntervalSince(session.statusSince)
        }
        return (node.endedAt ?? now).timeIntervalSince(node.startedAt)
    }

    // MARK: Ids

    static func id(for ref: AgentRef) -> String {
        "\(ref.session.agent.rawValue):\(ref.session.sessionID)" + (ref.agentID.map { "/\($0)" } ?? "")
    }

    static func ref(forID id: String, in session: SessionKey) -> AgentRef? {
        let prefix = "\(session.agent.rawValue):\(session.sessionID)"
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        if rest.isEmpty { return AgentRef(session: session) }
        guard rest.hasPrefix("/") else { return nil }
        return AgentRef(session: session, agentID: String(rest.dropFirst()))
    }
}
