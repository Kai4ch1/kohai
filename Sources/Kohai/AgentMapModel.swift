import Foundation
import KohaiCore
import Observation

/// Reads transcripts off the main thread. Owns the per-file tail state; only reads, never writes.
actor TranscriptReader {
    struct Target: Sendable {
        var session: SessionKey
        var configDir: String
        var reportedTranscript: String?
    }

    struct Batch: Sendable {
        var ref: AgentRef
        var entries: [TranscriptEntry] = []
        var restarted = false
        var meta: AgentMeta?
        var metaAt = Date()
    }

    struct ReportQuery: Sendable {
        var ref: AgentRef
        var projectDir: String
        var agentType: String
        var since: Date
        var until: Date?
    }

    struct Report: Sendable {
        var ref: AgentRef
        var path: String
        var text: String
        var modified: Date
    }

    /// Report files are shown in full but bounded.
    static let maxReportBytes = 256 * 1024

    private let files: TranscriptFiles
    private var tails: [String: LineTail] = [:]
    private var mainPaths: [SessionKey: String] = [:]
    private var metaSeen: [String: Date] = [:]
    private var reportsSeen: [String: Date] = [:]

    init(files: TranscriptFiles = LocalTranscriptFiles()) {
        self.files = files
    }

    func poll(_ targets: [Target]) -> [Batch] {
        var batches: [Batch] = []
        var live = Set<String>()
        for target in targets {
            guard let main = mainPath(for: target) else { continue }
            live.insert(main)
            batches.append(read(main, as: AgentRef(session: target.session)))

            let directory = TranscriptLocator.subagentsDirectory(forMainTranscript: main)
            for file in TranscriptLocator.agentFiles(in: directory, files: files) {
                let ref = AgentRef(session: target.session, agentID: file.agentID)
                live.insert(file.transcript)
                var batch = read(file.transcript, as: ref)
                if let identity = files.identity(atPath: file.meta), metaSeen[file.meta] != identity.modified,
                   let data = files.read(atPath: file.meta, from: 0, maxLength: 64 * 1024),
                   let meta = AgentMeta.parse(data) {
                    metaSeen[file.meta] = identity.modified
                    batch.meta = meta
                    batch.metaAt = identity.modified
                }
                batches.append(batch)
            }
        }
        // Stop following files of sessions that are no longer shown.
        tails = tails.filter { live.contains($0.key) }
        return batches.filter { !$0.entries.isEmpty || $0.restarted || $0.meta != nil }
    }

    /// Newest matching report per query, read only when the file changed since last time.
    func reports(_ queries: [ReportQuery], knownTypes: Set<String>, claimed: Set<String>) -> [Report] {
        var found: [Report] = []
        var taken = claimed
        for query in queries {
            guard let path = TranscriptLocator.report(
                projectDir: query.projectDir, agentType: query.agentType, since: query.since, until: query.until,
                knownTypes: knownTypes, excluding: taken, files: files),
                let identity = files.identity(atPath: path)
            else { continue }
            taken.insert(path)
            guard reportsSeen[path] != identity.modified,
                  let data = files.read(atPath: path, from: 0, maxLength: Self.maxReportBytes)
            else { continue }
            reportsSeen[path] = identity.modified
            found.append(Report(ref: query.ref, path: path, text: String(decoding: data, as: UTF8.self), modified: identity.modified))
        }
        return found
    }

    private func mainPath(for target: Target) -> String? {
        if let known = mainPaths[target.session], files.identity(atPath: known) != nil { return known }
        let path = TranscriptLocator.mainTranscript(
            sessionID: target.session.sessionID, configDir: target.configDir,
            reported: target.reportedTranscript, files: files)
        mainPaths[target.session] = path
        return path
    }

    private func read(_ path: String, as ref: AgentRef) -> Batch {
        var tail = tails[path] ?? LineTail(path: path)
        let read = tail.poll(files)
        tails[path] = tail
        var batch = Batch(ref: ref, restarted: read.restarted)
        for line in read.lines { batch.entries += TranscriptParser.entries(fromLine: line) }
        return batch
    }
}

/// The agent map's state. Hook events are applied always (cheap: they keep the per-session agent
/// counts current); transcripts are read only while a map is on screen.
@MainActor
@Observable
final class AgentMapModel {
    private(set) var graph = AgentGraph()
    @ObservationIgnored private let reader = TranscriptReader()

    static let pollInterval: Duration = .milliseconds(500)

    func apply(hook event: AgentEvent) {
        graph.apply(hook: event)
    }

    func remove(_ session: SessionKey) {
        graph.removeSession(session)
    }

    /// Follows these sessions' transcripts until the calling task is cancelled (the map closes or
    /// shows another project). Meant for `.task(id:)`.
    func follow(_ sessions: [Session]) async {
        let targets = sessions.map {
            TranscriptReader.Target(session: $0.key, configDir: $0.configDir, reportedTranscript: $0.transcriptPath)
        }
        let projects = Dictionary(sessions.map { ($0.key, $0.projectDir) }, uniquingKeysWith: { a, _ in a })
        for session in sessions { graph.ensureMain(session.key, at: session.statusSince) }

        while !Task.isCancelled {
            for batch in await reader.poll(targets) {
                if batch.restarted { graph.resetSteps(of: batch.ref) }
                if let meta = batch.meta { graph.apply(meta: meta, for: batch.ref, at: batch.metaAt) }
                graph.apply(batch.entries, from: batch.ref)
            }
            await attachReports(projects: projects)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// `reports/<agentType>-<task>.md` written by a subagent becomes its result.
    private func attachReports(projects: [SessionKey: String]) async {
        let children = graph.nodes.values.filter { !$0.id.isMain && projects[$0.id.session] != nil }
        var claimed = Set<String>()
        var queries: [TranscriptReader.ReportQuery] = []
        for node in children {
            if case .report(let path) = node.result?.source { claimed.insert(path) }
            guard let type = node.agentType, let projectDir = projects[node.id.session] else { continue }
            queries.append(.init(ref: node.id, projectDir: projectDir, agentType: type, since: node.startedAt, until: node.endedAt))
        }
        guard !queries.isEmpty else { return }
        let knownTypes = Set(children.compactMap(\.agentType))
        // Agents that already own a report keep it; the rest can't take it.
        let own = Dictionary(children.compactMap { node -> (AgentRef, String)? in
            if case .report(let path) = node.result?.source { return (node.id, path) }
            return nil
        }, uniquingKeysWith: { a, _ in a })
        for query in queries {
            let others = claimed.subtracting(own[query.ref].map { [$0] } ?? [])
            for report in await reader.reports([query], knownTypes: knownTypes, claimed: others) {
                graph.attachReport(path: report.path, text: report.text, at: report.modified, to: report.ref)
                claimed.insert(report.path)
            }
        }
    }
}
