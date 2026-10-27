import SwiftUI

// =============================================================================
// Agent map: presentation-only types and views. Like the rest of Views/, no
// KohaiCore here; `AgentMapContainer` maps the Core graph onto these models.
// Layout: the project's sessions as top-down trees (main session → subagents),
// an inspector for the selected agent underneath.
// =============================================================================

enum AgentState: Hashable, Sendable {
    case running
    case needsInput
    case done
    case failed
    case interrupted

    /// The existing seal language; failed/interrupted wear the done seal plus a mark.
    var seal: SessionStatus {
        switch self {
        case .running: .working
        case .needsInput: .needsInput
        case .done, .failed, .interrupted: .done
        }
    }

    func label(_ tone: CopyTone) -> String {
        switch self {
        case .running: Copy.agentRunning.text(tone)
        case .needsInput: Copy.agentNeedsInput.text(tone)
        case .done: Copy.agentDone.text(tone)
        case .failed: Copy.agentError.text(tone)
        case .interrupted: Copy.agentInterrupted.text(tone)
        }
    }

    /// Small mark next to the seal for states the seal alone can't tell apart.
    var markSymbol: String? {
        switch self {
        case .failed: "exclamationmark.triangle.fill"
        case .interrupted: "stop.circle"
        default: nil
        }
    }
}

struct AgentNodeModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Agent type (and "background"); the session name for a main session.
    let subtitle: String
    let state: AgentState
    let isMain: Bool
    let elapsed: String
    /// Grid position from the tree layout: column (may be fractional) and level.
    let column: Double
    let level: Int
}

struct AgentEdgeModel: Hashable, Sendable {
    let from: String
    let to: String
}

struct AgentMapPresentation: Hashable, Sendable {
    let nodes: [AgentNodeModel]
    let edges: [AgentEdgeModel]
    let columns: Double
    let levels: Int

    var hasSubagents: Bool { nodes.contains { !$0.isMain } }
}

struct AgentStepModel: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case prompt
        case message
        case tool(String)
        case handback
    }

    let id: String
    let time: String
    let kind: Kind
    let summary: String
    let pending: Bool
    let isError: Bool
    let errorLine: String?
}

enum AgentResultSource: Hashable, Sendable {
    case handback
    case lastMessage
    case report(fileName: String, path: String)
}

struct AgentInspectorModel: Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let state: AgentState
    let elapsed: String
    let steps: [AgentStepModel]
    let earlierSteps: Int
    let live: String?
    let result: String?
    let resultSource: AgentResultSource?
}

// MARK: Screen

struct AgentMapScreen: View {
    let project: String
    let map: AgentMapPresentation
    let inspector: AgentInspectorModel?
    @Binding var selection: String?
    var onShowSessions: () -> Void = {}
    var onOpenReport: (String) -> Void = { _ in }
    /// false = no ScrollViews (PNG snapshots).
    var scrollable = true
    var inspectorTab: AgentInspector.Tab = .steps

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            KohaiSeparator()
            if map.nodes.isEmpty {
                StateMessage(mascot: .sleeping, title: Copy.mapNoSessions.text(tone), message: "")
                Spacer(minLength: 0)
            } else {
                AgentMapCanvas(map: map, selection: $selection, scrollable: scrollable)
                    .frame(minHeight: 180, maxHeight: .infinity)
                if !map.hasSubagents {
                    Text(Copy.mapEmptyBody.text(tone))
                        .font(KohaiType.hint)
                        .foregroundStyle(palette.text.tertiary.color)
                        .padding(.horizontal, KohaiSpacing.lg)
                        .padding(.bottom, KohaiSpacing.sm)
                }
                KohaiSeparator()
                AgentInspector(model: inspector, onOpenReport: onOpenReport, scrollable: scrollable, initialTab: inspectorTab)
                    // A new agent starts on its steps again.
                    .id(inspector?.id)
                    .frame(height: 280)
            }
        }
        .frame(minWidth: KohaiMetrics.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: KohaiSpacing.md) {
            Text(project)
                .font(KohaiType.headerTitle)
                .foregroundStyle(palette.text.primary.color)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: KohaiSpacing.sm)
            Picker("", selection: Binding(get: { true }, set: { if !$0 { onShowSessions() } })) {
                Text(Copy.mapToggleSessions.text(tone)).tag(false)
                Text(Copy.mapToggleMap.text(tone)).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(KohaiSpacing.lg)
    }
}

// MARK: Graph

struct AgentMapCanvas: View {
    let map: AgentMapPresentation
    @Binding var selection: String?
    var scrollable = true

    static let nodeSize = CGSize(width: 180, height: 58)
    static let columnSpacing: CGFloat = 204
    static let levelSpacing: CGFloat = 92
    static let margin: CGFloat = KohaiSpacing.lg

    @Environment(\.kohaiPalette) private var palette

    var body: some View {
        OptionalScroll(axes: [.horizontal, .vertical], enabled: scrollable) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in map.edges {
                        guard let from = center(of: edge.from), let to = center(of: edge.to) else { continue }
                        var path = Path()
                        let start = CGPoint(x: from.x, y: from.y + Self.nodeSize.height / 2)
                        let end = CGPoint(x: to.x, y: to.y - Self.nodeSize.height / 2)
                        let midY = (start.y + end.y) / 2
                        path.move(to: start)
                        path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
                        context.stroke(path, with: .color(palette.surface.separator.color), lineWidth: 1.5)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)

                ForEach(map.nodes) { node in
                    AgentNodeCard(node: node, isSelected: node.id == selection) { selection = node.id }
                        .frame(width: Self.nodeSize.width, height: Self.nodeSize.height)
                        .position(center(of: node.id) ?? .zero)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        }
    }

    private var canvasSize: CGSize {
        CGSize(
            width: max(1, map.columns) * Self.columnSpacing + Self.margin * 2,
            height: CGFloat(max(1, map.levels)) * Self.levelSpacing + Self.margin * 2)
    }

    private func center(of id: String) -> CGPoint? {
        guard let node = map.nodes.first(where: { $0.id == id }) else { return nil }
        return CGPoint(
            x: Self.margin + CGFloat(node.column) * Self.columnSpacing + Self.columnSpacing / 2,
            y: Self.margin + CGFloat(node.level) * Self.levelSpacing + Self.nodeSize.height / 2)
    }
}

struct AgentNodeCard: View {
    let node: AgentNodeModel
    var isSelected = false
    var onSelect: () -> Void = {}

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: KohaiSpacing.sm) {
                VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                    Text(node.name)
                        .font(node.isMain ? KohaiType.rowTitle.weight(.semibold) : KohaiType.rowTitle)
                        .foregroundStyle(palette.text.primary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(node.subtitle)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.secondary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: KohaiSpacing.xs)
                VStack(alignment: .trailing, spacing: KohaiSpacing.xxs) {
                    HStack(spacing: KohaiSpacing.xxs) {
                        if let mark = node.state.markSymbol {
                            Image(systemName: mark)
                                .font(KohaiType.secondary)
                                .foregroundStyle(palette.text.secondary.color)
                        }
                        StatusSeal(status: node.state.seal)
                    }
                    Text(node.elapsed)
                        .font(KohaiType.mono)
                        .foregroundStyle(palette.text.tertiary.color)
                }
            }
            .padding(.horizontal, KohaiSpacing.sm)
            .padding(.vertical, KohaiSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? palette.surface.rowHighlight.color : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        node.state == .needsInput ? palette.seal.needsInput.color : palette.surface.separator.color,
                        lineWidth: node.state == .needsInput || isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(node.subtitle), \(node.state.label(tone)), \(node.elapsed)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .help(node.name)
    }
}

// MARK: Inspector

struct AgentInspector: View {
    let model: AgentInspectorModel?
    var onOpenReport: (String) -> Void = { _ in }
    var scrollable = true

    enum Tab: Hashable, Sendable { case steps, live, result }
    @State private var tab: Tab

    init(model: AgentInspectorModel?, onOpenReport: @escaping (String) -> Void = { _ in },
         scrollable: Bool = true, initialTab: Tab = .steps) {
        self.model = model
        self.onOpenReport = onOpenReport
        self.scrollable = scrollable
        _tab = State(initialValue: initialTab)
    }

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        if let model {
            VStack(alignment: .leading, spacing: KohaiSpacing.sm) {
                HStack(spacing: KohaiSpacing.sm) {
                    VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                        Text(model.name)
                            .font(KohaiType.rowTitle)
                            .foregroundStyle(palette.text.primary.color)
                            .lineLimit(1)
                        Text("\(model.subtitle) · \(model.state.label(tone)) · \(model.elapsed)")
                            .font(KohaiType.secondary)
                            .foregroundStyle(palette.text.secondary.color)
                            .lineLimit(1)
                    }
                    Spacer(minLength: KohaiSpacing.sm)
                    Picker("", selection: $tab) {
                        Text(Copy.inspectorSteps.text(tone)).tag(Tab.steps)
                        Text(Copy.inspectorLive.text(tone)).tag(Tab.live)
                        Text(Copy.inspectorResult.text(tone)).tag(Tab.result)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                switch tab {
                case .steps: steps(model)
                case .live: textPane(model.live, empty: Copy.inspectorNoLive.text(tone))
                case .result: result(model)
                }
            }
            .padding(KohaiSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            StateMessage(mascot: .sleeping, title: Copy.mapSelectHint.text(tone), message: "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func steps(_ model: AgentInspectorModel) -> some View {
        if model.steps.isEmpty {
            placeholder(Copy.inspectorNoSteps.text(tone))
        } else {
            if scrollable {
                ScrollViewReader { proxy in
                    ScrollView { stepList(model) }
                        // Live: keep the newest step in view.
                        .onChange(of: model.steps.last?.id) { _, last in
                            if let last { proxy.scrollTo(last, anchor: .bottom) }
                        }
                        .onAppear { if let last = model.steps.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
                }
            } else {
                stepList(model)
                Spacer(minLength: 0)
            }
        }
    }

    private func stepList(_ model: AgentInspectorModel) -> some View {
        LazyVStack(alignment: .leading, spacing: KohaiSpacing.xs) {
            if model.earlierSteps > 0 {
                Text(Copy.inspectorEarlier.text(tone, ["n": "\(model.earlierSteps)"]))
                    .font(KohaiType.hint)
                    .foregroundStyle(palette.text.tertiary.color)
            }
            ForEach(model.steps) { step in
                AgentStepRow(step: step).id(step.id)
            }
        }
    }

    @ViewBuilder
    private func result(_ model: AgentInspectorModel) -> some View {
        if let text = model.result {
            VStack(alignment: .leading, spacing: KohaiSpacing.xs) {
                if let source = model.resultSource {
                    HStack(spacing: KohaiSpacing.sm) {
                        Text(sourceLabel(source))
                            .font(KohaiType.hint)
                            .foregroundStyle(palette.text.tertiary.color)
                        if case .report(_, let path) = source {
                            LinkButton(title: Copy.resultOpenReport.text(tone)) { onOpenReport(path) }
                        }
                    }
                }
                textPane(text, empty: "")
            }
        } else {
            placeholder(Copy.inspectorNoResult.text(tone))
        }
    }

    private func sourceLabel(_ source: AgentResultSource) -> String {
        switch source {
        case .handback: Copy.resultFromHandback.text(tone)
        case .lastMessage: Copy.resultFromMessage.text(tone)
        case .report(let fileName, _): Copy.resultFromReport.text(tone, ["file": fileName])
        }
    }

    @ViewBuilder
    private func textPane(_ text: String?, empty: String) -> some View {
        if let text, !text.isEmpty {
            OptionalScroll(axes: .vertical, enabled: scrollable) {
                Text(text)
                    .font(KohaiType.body)
                    .foregroundStyle(palette.text.primary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            placeholder(empty)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(KohaiType.hint)
            .foregroundStyle(palette.text.tertiary.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AgentStepRow: View {
    let step: AgentStepModel

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KohaiSpacing.sm) {
            Text(step.time)
                .font(KohaiType.mono)
                .foregroundStyle(palette.text.tertiary.color)
            Image(systemName: symbol)
                .font(KohaiType.secondary)
                .foregroundStyle(step.isError ? palette.seal.needsInput.color : palette.text.secondary.color)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KohaiSpacing.xxs) {
                HStack(spacing: KohaiSpacing.xs) {
                    Text(title)
                        .font(KohaiType.secondary.weight(.semibold))
                        .foregroundStyle(palette.text.primary.color)
                    if step.pending {
                        Text(Copy.stepWaiting.text(tone))
                            .font(KohaiType.hint)
                            .foregroundStyle(palette.text.tertiary.color)
                    }
                }
                if !step.summary.isEmpty {
                    Text(step.summary)
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.secondary.color)
                        .lineLimit(2)
                }
                if let error = step.errorLine {
                    Text(error)
                        .font(KohaiType.monoPath)
                        .foregroundStyle(palette.text.secondary.color)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch step.kind {
        case .prompt: Copy.stepPrompt.text(tone)
        case .message: Copy.stepMessage.text(tone)
        case .tool(let name): name
        case .handback: Copy.stepHandback.text(tone)
        }
    }

    private var symbol: String {
        if step.isError { return "exclamationmark.triangle.fill" }
        switch step.kind {
        case .prompt: return "text.bubble"
        case .message: return "bubble.left"
        case .tool: return step.pending ? "hourglass" : "wrench.and.screwdriver"
        case .handback: return "arrowshape.turn.up.left"
        }
    }
}

/// A ScrollView, or just the content when rendering to PNG.
struct OptionalScroll<Content: View>: View {
    let axes: Axis.Set
    let enabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if enabled {
            ScrollView(axes) { content }
        } else {
            content
        }
    }
}
