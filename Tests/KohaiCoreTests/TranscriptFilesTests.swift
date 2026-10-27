import Foundation
import Testing
@testable import KohaiCore

/// In-memory files and directories. Directories are paths that prefix other paths.
final class MemoryTranscriptFiles: TranscriptFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (data: Data, inode: UInt64, modified: Date)] = [:]
    private var nextInode: UInt64 = 100
    private(set) var reads = 0

    func write(_ path: String, _ text: String, modified: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        write(path, Data(text.utf8), modified: modified)
    }

    func write(_ path: String, _ data: Data, modified: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        lock.lock(); defer { lock.unlock() }
        let inode = files[path]?.inode ?? { nextInode += 1; return nextInode }()
        files[path] = (data, inode, modified)
    }

    func append(_ path: String, _ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard var file = files[path] else { return }
        file.data.append(Data(text.utf8))
        files[path] = file
    }

    /// Same path, new file (as after an editor's atomic save or a rewrite).
    func replace(_ path: String, _ text: String) {
        lock.lock()
        files[path] = nil
        lock.unlock()
        write(path, text)
    }

    func identity(atPath path: String) -> FileIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard let file = files[path] else { return nil }
        return FileIdentity(size: UInt64(file.data.count), inode: file.inode, modified: file.modified)
    }

    func read(atPath path: String, from offset: UInt64, maxLength: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        guard let file = files[path], offset <= UInt64(file.data.count) else { return nil }
        let start = Int(offset)
        return file.data.subdata(in: start..<min(file.data.count, start + maxLength))
    }

    func list(directory path: String) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let names = Set(files.keys.filter { $0.hasPrefix(prefix) }.compactMap {
            $0.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
        })
        return names.isEmpty ? nil : Array(names)
    }
}

private func strings(_ lines: [Data]) -> [String] {
    lines.map { String(decoding: $0, as: UTF8.self) }
}

@Suite("Line tail")
struct LineTailTests {
    let path = "/c/projects/p/s.jsonl"

    @Test func readsOnlyNewCompleteLines() {
        let files = MemoryTranscriptFiles()
        files.write(path, "one\ntwo\nthr")
        var tail = LineTail(path: path)
        #expect(strings(tail.poll(files).lines) == ["one", "two"])
        #expect(tail.poll(files).lines.isEmpty)
        files.append(path, "ee\nfour\n")
        #expect(strings(tail.poll(files).lines) == ["three", "four"])
        #expect(tail.offset == UInt64("one\ntwo\nthree\nfour\n".utf8.count))
    }

    @Test func emptyLinesAreSkipped() {
        let files = MemoryTranscriptFiles()
        files.write(path, "\n\na\n\n")
        var tail = LineTail(path: path)
        #expect(strings(tail.poll(files).lines) == ["a"])
    }

    @Test func missingFile() {
        var tail = LineTail(path: path)
        let read = tail.poll(MemoryTranscriptFiles())
        #expect(read.missing)
        #expect(read.lines.isEmpty)
    }

    @Test func truncationRestartsFromTheTop() {
        let files = MemoryTranscriptFiles()
        files.write(path, "a\nb\nc\n")
        var tail = LineTail(path: path)
        _ = tail.poll(files)
        files.write(path, "x\n") // same inode, shorter
        let read = tail.poll(files)
        #expect(read.restarted)
        #expect(strings(read.lines) == ["x"])
    }

    @Test func replacementRestartsFromTheTop() {
        let files = MemoryTranscriptFiles()
        files.write(path, "a\nb\n")
        var tail = LineTail(path: path)
        _ = tail.poll(files)
        files.replace(path, "a\nb\nc\nd\n") // new inode, longer
        let read = tail.poll(files)
        #expect(read.restarted)
        #expect(strings(read.lines) == ["a", "b", "c", "d"])
    }

    @Test func partialLineIsDroppedOnRestart() {
        let files = MemoryTranscriptFiles()
        files.write(path, "a\npart")
        var tail = LineTail(path: path)
        _ = tail.poll(files)
        files.replace(path, "b\n")
        #expect(strings(tail.poll(files).lines) == ["b"])
    }

    @Test func oversizedLineIsSkippedWhole() {
        let files = MemoryTranscriptFiles()
        let huge = String(repeating: "x", count: LineTail.maxLineBytes + 10)
        files.write(path, "small\n" + huge)
        var tail = LineTail(path: path)
        #expect(strings(tail.poll(files).lines) == ["small"])
        files.append(path, "still the huge line\nafter\n")
        #expect(strings(tail.poll(files).lines) == ["after"])
    }

    @Test func lineSplitAcrossChunksIsJoined() {
        let files = MemoryTranscriptFiles()
        let long = String(repeating: "y", count: LineTail.chunkSize + 100)
        files.write(path, "\(long)\nend\n")
        var tail = LineTail(path: path)
        let lines = strings(tail.poll(files).lines)
        #expect(lines.count == 2)
        #expect(lines.first?.count == long.count)
        #expect(lines.last == "end")
    }

    @Test func bigFileIsReadOverSeveralPolls() {
        let files = MemoryTranscriptFiles()
        let line = String(repeating: "z", count: 1023) + "\n"
        let count = LineTail.maxBytesPerPoll / line.utf8.count + 50
        files.write(path, String(repeating: line, count: count))
        var tail = LineTail(path: path)
        let first = tail.poll(files).lines.count
        let second = tail.poll(files).lines.count
        #expect(first < count)
        #expect(first + second == count)
    }
}

@Suite("Transcript locator")
struct TranscriptLocatorTests {
    @Test func prefersTheReportedPath() {
        let files = MemoryTranscriptFiles()
        files.write("/c/projects/-x/s1.jsonl", "")
        files.write("/elsewhere/s1.jsonl", "")
        #expect(TranscriptLocator.mainTranscript(sessionID: "s1", configDir: "/c", reported: "/elsewhere/s1.jsonl", files: files)
            == "/elsewhere/s1.jsonl")
    }

    @Test func findsBySessionIDWhenTheReportedPathIsGone() {
        let files = MemoryTranscriptFiles()
        files.write("/c/projects/-Users-me-a/other.jsonl", "")
        files.write("/c/projects/-Users-me-b/s1.jsonl", "")
        #expect(TranscriptLocator.mainTranscript(sessionID: "s1", configDir: "/c", reported: "/gone/s1.jsonl", files: files)
            == "/c/projects/-Users-me-b/s1.jsonl")
        #expect(TranscriptLocator.mainTranscript(sessionID: "s9", configDir: "/c", reported: nil, files: files) == nil)
    }

    @Test func subagentsDirectory() {
        #expect(TranscriptLocator.subagentsDirectory(forMainTranscript: "/c/projects/p/s1.jsonl") == "/c/projects/p/s1/subagents")
    }

    @Test func agentFilesFlatAndNested() {
        let files = MemoryTranscriptFiles()
        let dir = "/c/projects/p/s1/subagents"
        files.write("\(dir)/agent-a1.jsonl", "")
        files.write("\(dir)/agent-a1.meta.json", "{}")
        files.write("\(dir)/agent-a1.prefix.json", "{}")
        files.write("\(dir)/team/agent-a2.jsonl", "")
        files.write("\(dir)/notes.txt", "")
        let found = TranscriptLocator.agentFiles(in: dir, files: files)
        #expect(found.map(\.agentID).sorted() == ["a1", "a2"])
        #expect(found.first { $0.agentID == "a1" }?.meta == "\(dir)/agent-a1.meta.json")
        #expect(found.first { $0.agentID == "a2" }?.transcript == "\(dir)/team/agent-a2.jsonl")
        #expect(TranscriptLocator.agentFiles(in: "/nope", files: files).isEmpty)
    }

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func newestReportWrittenDuringTheRun() {
        let files = MemoryTranscriptFiles()
        files.write("/p/reports/qa-old.md", "", modified: start.addingTimeInterval(-600))
        files.write("/p/reports/qa-login.md", "", modified: start.addingTimeInterval(30))
        files.write("/p/reports/qa-signup.md", "", modified: start.addingTimeInterval(60))
        files.write("/p/reports/qa-notes.txt", "", modified: start.addingTimeInterval(90))
        files.write("/p/reports/dev-x.md", "", modified: start.addingTimeInterval(90))
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "qa", since: start, knownTypes: ["qa", "dev"], files: files)
            == "/p/reports/qa-signup.md")
    }

    @Test func reportAfterTheAgentEndedBelongsToSomeoneElse() {
        let files = MemoryTranscriptFiles()
        files.write("/p/reports/qa-a.md", "", modified: start.addingTimeInterval(10))
        files.write("/p/reports/qa-b.md", "", modified: start.addingTimeInterval(500))
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "qa", since: start, until: start.addingTimeInterval(20),
                                         knownTypes: ["qa"], files: files) == "/p/reports/qa-a.md")
    }

    @Test func claimedReportsAreSkipped() {
        let files = MemoryTranscriptFiles()
        files.write("/p/reports/qa-a.md", "", modified: start.addingTimeInterval(10))
        files.write("/p/reports/qa-b.md", "", modified: start.addingTimeInterval(20))
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "qa", since: start, knownTypes: ["qa"],
                                         excluding: ["/p/reports/qa-b.md"], files: files) == "/p/reports/qa-a.md")
    }

    @Test func longerAgentTypeWithTheSamePrefixIsNotConfused() {
        let files = MemoryTranscriptFiles()
        files.write("/p/reports/general-purpose-audit.md", "", modified: start.addingTimeInterval(10))
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "general", since: start,
                                         knownTypes: ["general", "general-purpose"], files: files) == nil)
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "general-purpose", since: start,
                                         knownTypes: ["general", "general-purpose"], files: files) == "/p/reports/general-purpose-audit.md")
    }

    @Test func noReportsFolder() {
        #expect(TranscriptLocator.report(projectDir: "/p", agentType: "qa", since: start, knownTypes: [], files: MemoryTranscriptFiles()) == nil)
    }
}
