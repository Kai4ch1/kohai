import Foundation

/// Positions for the agent map: one tree per session, top-down. Leaves take consecutive columns,
/// a parent sits centred over its children, and trees are placed side by side with one empty
/// column between them. Units are abstract (columns, levels); the view scales them.
public struct AgentTreeLayout: Sendable, Equatable {
    public struct Position: Sendable, Equatable {
        public var column: Double
        public var level: Int
    }

    public private(set) var positions: [AgentRef: Position] = [:]
    /// Parent → child pairs in drawing order.
    public private(set) var edges: [(from: AgentRef, to: AgentRef)] = []
    public private(set) var columns: Double = 0
    public private(set) var levels = 0

    public static func == (a: AgentTreeLayout, b: AgentTreeLayout) -> Bool {
        a.positions == b.positions && a.columns == b.columns && a.levels == b.levels
            && a.edges.map(\.from) == b.edges.map(\.from) && a.edges.map(\.to) == b.edges.map(\.to)
    }

    public init(graph: AgentGraph, sessions: [SessionKey]) {
        var next = 0.0
        for (index, session) in sessions.enumerated() {
            let root = AgentRef(session: session)
            guard graph.node(root) != nil else { continue }
            if index > 0, !positions.isEmpty { next += 1 }
            var visited = Set<AgentRef>()
            place(root, level: 0, graph: graph, next: &next, visited: &visited)
            // Agents unreachable from the root (a parent cycle from bad metadata) still show,
            // hung under the main session.
            for node in graph.subagents(of: session) where !visited.contains(node.id) {
                edges.append((root, node.id))
                place(node.id, level: 1, graph: graph, next: &next, visited: &visited)
            }
        }
        columns = next
    }

    @discardableResult
    private mutating func place(_ ref: AgentRef, level: Int, graph: AgentGraph, next: inout Double, visited: inout Set<AgentRef>) -> Double {
        visited.insert(ref)
        levels = max(levels, level + 1)
        // A malformed parent chain (cycle) must not loop forever.
        let children = graph.children(of: ref).map(\.id).filter { !visited.contains($0) }
        let column: Double
        if children.isEmpty {
            column = next
            next += 1
        } else {
            let placed = children.map { child -> Double in
                edges.append((ref, child))
                return place(child, level: level + 1, graph: graph, next: &next, visited: &visited)
            }
            column = (placed.first! + placed.last!) / 2
        }
        positions[ref] = Position(column: column, level: level)
        return column
    }
}
