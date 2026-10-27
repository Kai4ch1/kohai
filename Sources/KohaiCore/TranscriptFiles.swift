import Foundation

/// Size and identity of a file, enough to notice appends, truncation and replacement.
public struct FileIdentity: Sendable, Equatable {
    public var size: UInt64
    public var inode: UInt64
    public var modified: Date

    public init(size: UInt64, inode: UInt64, modified: Date) {
        self.size = size
        self.inode = inode
        self.modified = modified
    }
}

/// Read-only file access for transcripts. Injected so the tailer and locator stay testable.
public protocol TranscriptFiles: Sendable {
    func identity(atPath path: String) -> FileIdentity?
    func read(atPath path: String, from offset: UInt64, maxLength: Int) -> Data?
    /// Entry names in a directory, nil when it is not a readable directory.
    func list(directory path: String) -> [String]?
}

/// The real file system. Opens files read-only and never writes.
public struct LocalTranscriptFiles: TranscriptFiles {
    public init() {}

    public func identity(atPath path: String) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.type] as? FileAttributeType) == .typeRegular
        else { return nil }
        return FileIdentity(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modified: attributes[.modificationDate] as? Date ?? .distantPast)
    }

    public func read(atPath path: String, from offset: UInt64, maxLength: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: maxLength) ?? Data()
        } catch {
            return nil
        }
    }

    public func list(directory path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }
}

/// Follows one append-only JSONL file: each poll returns only the complete lines added since the
/// previous one. A trailing partial line waits for its newline. If the file shrinks or is replaced
/// (different inode), reading restarts from the top and `restarted` tells the caller to drop what
/// it derived from the old content.
public struct LineTail: Sendable {
    /// Lines longer than this are skipped whole (a single tool output can be huge).
    public static let maxLineBytes = 2 << 20
    /// Upper bound per poll, so one giant file can't stall the others.
    public static let maxBytesPerPoll = 8 << 20
    static let chunkSize = 1 << 20

    public let path: String
    public private(set) var offset: UInt64 = 0
    private var inode: UInt64?
    private var pending = Data()
    /// Inside an oversized line: discard bytes up to the next newline.
    private var skipping = false

    public init(path: String) {
        self.path = path
    }

    public struct Read: Sendable, Equatable {
        public var lines: [Data]
        public var restarted: Bool
        /// The file is missing or unreadable right now.
        public var missing: Bool
    }

    public mutating func poll(_ files: TranscriptFiles) -> Read {
        guard let identity = files.identity(atPath: path) else {
            return Read(lines: [], restarted: false, missing: true)
        }
        var restarted = false
        if let known = inode, known != identity.inode || identity.size < offset {
            offset = 0
            pending = Data()
            skipping = false
            restarted = true
        }
        inode = identity.inode

        var lines: [Data] = []
        var budget = Self.maxBytesPerPoll
        while offset < identity.size, budget > 0 {
            let length = Int(min(UInt64(Self.chunkSize), identity.size - offset, UInt64(budget)))
            guard let chunk = files.read(atPath: path, from: offset, maxLength: length), !chunk.isEmpty else { break }
            offset += UInt64(chunk.count)
            budget -= chunk.count
            lines += consume(chunk)
        }
        return Read(lines: lines, restarted: restarted, missing: false)
    }

    /// Splits new bytes into complete lines; keeps the unfinished tail.
    mutating func consume(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let piece = chunk[start..<newline]
            if skipping {
                skipping = false
            } else if pending.count + piece.count <= Self.maxLineBytes {
                var line = pending
                line.append(piece)
                if !line.isEmpty { lines.append(line) }
            }
            pending = Data()
            start = chunk.index(after: newline)
        }
        if !skipping {
            pending.append(chunk[start...])
            if pending.count > Self.maxLineBytes {
                pending = Data()
                skipping = true
            }
        }
        return lines
    }
}

/// Where Claude Code keeps a session's transcripts.
public enum TranscriptLocator {
    /// The session's main transcript. Prefers the path the hooks reported; otherwise looks for
    /// `<configDir>/projects/*/<sessionID>.jsonl` (the project folder's name encoding is not
    /// guessed, it is found).
    public static func mainTranscript(
        sessionID: String, configDir: String, reported: String?, files: TranscriptFiles
    ) -> String? {
        if let reported, files.identity(atPath: reported) != nil { return reported }
        let projects = (configDir as NSString).appendingPathComponent("projects")
        for folder in (files.list(directory: projects) ?? []).sorted() {
            let candidate = "\(projects)/\(folder)/\(sessionID).jsonl"
            if files.identity(atPath: candidate) != nil { return candidate }
        }
        return nil
    }

    /// `<…>/<sessionID>.jsonl` → `<…>/<sessionID>/subagents`.
    public static func subagentsDirectory(forMainTranscript path: String) -> String {
        let base = path.hasSuffix(".jsonl") ? String(path.dropLast(".jsonl".count)) : path
        return base + "/subagents"
    }

    public struct AgentFile: Sendable, Equatable {
        public var agentID: String
        public var transcript: String
        public var meta: String
    }

    /// `agent-<id>.jsonl` files, also in nested folders (up to `depth` levels).
    public static func agentFiles(in directory: String, files: TranscriptFiles, depth: Int = 3) -> [AgentFile] {
        guard depth > 0, let names = files.list(directory: directory) else { return [] }
        var found: [AgentFile] = []
        for name in names.sorted() {
            let path = "\(directory)/\(name)"
            if name.hasPrefix("agent-"), name.hasSuffix(".jsonl") {
                let id = String(name.dropFirst("agent-".count).dropLast(".jsonl".count))
                guard !id.isEmpty else { continue }
                found.append(AgentFile(agentID: id, transcript: path, meta: "\(directory)/agent-\(id).meta.json"))
            } else if !name.contains("."), files.list(directory: path) != nil {
                found += agentFiles(in: path, files: files, depth: depth - 1)
            }
        }
        return found
    }

    /// How long after an agent finished its report may still be written.
    public static let reportGrace: TimeInterval = 60

    /// The newest `reports/<agentType>-<task>.md` written while the agent ran (from `start` to
    /// `end` + grace). Skipped: files in `excluding` (claimed by another agent), and files that
    /// belong to a longer agent type starting with this one ("general-purpose-…" for "general").
    public static func report(
        projectDir: String, agentType: String, since start: Date, until end: Date? = nil,
        knownTypes: Set<String>, excluding: Set<String> = [], files: TranscriptFiles
    ) -> String? {
        let directory = (projectDir as NSString).appendingPathComponent("reports")
        let prefix = agentType + "-"
        let longer = knownTypes.filter { $0 != agentType && $0.hasPrefix(prefix) }
        // Small slack for clock granularity between the hook timestamp and the file's mtime.
        let earliest = start.addingTimeInterval(-2)
        var best: (path: String, modified: Date)?
        for name in files.list(directory: directory) ?? [] where name.hasPrefix(prefix) && name.hasSuffix(".md") {
            if longer.contains(where: { name.hasPrefix($0 + "-") }) { continue }
            let path = "\(directory)/\(name)"
            guard !excluding.contains(path),
                  let identity = files.identity(atPath: path), identity.modified >= earliest
            else { continue }
            if let end, identity.modified > end.addingTimeInterval(reportGrace) { continue }
            if best == nil || identity.modified > best!.modified { best = (path, identity.modified) }
        }
        return best?.path
    }
}
