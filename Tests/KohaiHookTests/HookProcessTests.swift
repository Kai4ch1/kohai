import Foundation
import KohaiCore
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs the real `kohai-hook` binary and checks the contract with the agent:
/// exit 0, no output, done within 200 ms, whatever the socket or input looks like.
@Suite("kohai-hook process", .serialized)
struct HookProcessTests {
    static let budget: TimeInterval = 0.2

    static let payload = Data("""
    {"session_id":"s-123","transcript_path":"/Users/tester/.claude-b/projects/-p/s-123.jsonl",\
    "cwd":"/Users/tester/dev/proj","hook_event_name":"PermissionRequest","tool_name":"Bash",\
    "tool_input":{"command":"rm -rf build"}}
    """.utf8)

    @Test func socketMissing() throws {
        let run = try HookRunner.run(input: Self.payload, socket: "/tmp/kohai-missing-\(UUID().uuidString.prefix(8)).sock")
        run.expectContract()
    }

    @Test func staleSocketFileWithoutListener() throws {
        let path = "/tmp/kohai-stale-\(UUID().uuidString.prefix(8)).sock"
        try HookRunner.bindAndAbandon(path)
        defer { unlink(path) }
        let run = try HookRunner.run(input: Self.payload, socket: path)
        run.expectContract()
    }

    @Test func listenerThatNeverAccepts() throws {
        let path = "/tmp/kohai-stuck-\(UUID().uuidString.prefix(8)).sock"
        let fd = try HookRunner.bindAndListen(path, backlog: 1)
        defer { close(fd); unlink(path) }
        // Fill the backlog so further connects stall.
        for _ in 0..<4 { _ = try? HookRunner.run(input: Self.payload, socket: path) }
        let run = try HookRunner.run(input: Self.payload, socket: path)
        run.expectContract()
    }

    @Test func stdinNeverClosed() throws {
        let run = try HookRunner.run(input: Data("{\"hook_event_name\":".utf8), socket: "/tmp/kohai-none.sock", closeStdin: false)
        run.expectContract()
    }

    @Test(arguments: ["", "not json", "{\"hook_event_name\":\"Stop\"}", "{\"hook_event_name\":\"Unknown\",\"session_id\":\"s\",\"cwd\":\"/x\"}"])
    func badInputSendsNothing(input: String) throws {
        let path = "/tmp/kohai-bad-\(UUID().uuidString.prefix(8)).sock"
        let inbox = MessageBox()
        let listener = SocketListener(path: path) { inbox.add($0) }
        try listener.start()
        defer { listener.stop() }
        let run = try HookRunner.run(input: Data(input.utf8), socket: path)
        run.expectContract()
        usleep(100_000)
        #expect(inbox.count == 0)
    }

    @Test func missingOrUnknownAgentArgument() throws {
        for arguments in [[String](), ["vim"]] {
            let run = try HookRunner.run(input: Self.payload, socket: "/tmp/kohai-none.sock", arguments: arguments)
            run.expectContract()
        }
    }

    @Test func deliversNormalizedEvent() throws {
        let path = "/tmp/kohai-ok-\(UUID().uuidString.prefix(8)).sock"
        let inbox = MessageBox()
        let listener = SocketListener(path: path) { inbox.add($0) }
        try listener.start()
        defer { listener.stop() }

        let run = try HookRunner.run(input: Self.payload, socket: path, extraEnvironment: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t2p0:AAAA-BBBB",
            "CLAUDE_PROJECT_DIR": "/Users/tester/dev/proj",
        ])
        run.expectContract()

        let data = try #require(inbox.wait(timeout: 1))
        let event = try WireCodec.decode(data)
        #expect(event.agent == .claude)
        #expect(event.kind == .permissionRequest)
        #expect(event.sessionID == "s-123")
        #expect(event.configDir == "/Users/tester/.claude-b")
        #expect(event.terminal.termProgram == "iTerm.app")
        #expect(event.terminal.itermSessionID == "AAAA-BBBB")
        #expect(event.message == "Permission: Bash — rm -rf build")
        #expect(abs(event.timestamp.timeIntervalSinceNow) < 5)
    }
}

// MARK: - Helpers

final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func add(_ data: Data) { lock.lock(); items.append(data); lock.unlock() }

    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }

    func wait(timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let first = items.first
            lock.unlock()
            if let first { return first }
            usleep(5_000)
        }
        return nil
    }
}

struct HookRun {
    var exitCode: Int32
    var elapsed: TimeInterval
    var stdout: Data
    var stderr: Data

    func expectContract(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(exitCode == 0, sourceLocation: sourceLocation)
        #expect(elapsed < HookProcessTests.budget, "took \(Int(elapsed * 1000)) ms", sourceLocation: sourceLocation)
        #expect(stdout.isEmpty, sourceLocation: sourceLocation)
        #expect(stderr.isEmpty, sourceLocation: sourceLocation)
    }
}

enum HookRunner {
    /// The built hook binary. `KOHAI_HOOK_BINARY` overrides; otherwise it sits next to the test bundle.
    static let binary: URL = {
        if let path = ProcessInfo.processInfo.environment["KOHAI_HOOK_BINARY"] {
            return URL(fileURLWithPath: path)
        }
        var candidates: [URL] = []
        #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("kohai-hook"))
        }
        #endif
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("kohai-hook"))
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(packageRoot.appendingPathComponent(".build/debug/kohai-hook"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates.last!
    }()

    /// One untimed run so the first measured run doesn't pay for the cold launch of a freshly
    /// built binary (code-signature check, dyld cache).
    static let warmUp: Void = {
        // The hook may exit before reading stdin; writing to its pipe must not kill the test runner.
        signal(SIGPIPE, SIG_IGN)
        _ = try? launch(input: Data(), socket: "/tmp/kohai-warmup.sock", arguments: ["claude"], extraEnvironment: [:], closeStdin: true)
    }()

    static func run(
        input: Data,
        socket: String,
        arguments: [String] = ["claude"],
        extraEnvironment: [String: String] = [:],
        closeStdin: Bool = true
    ) throws -> HookRun {
        _ = warmUp
        return try launch(input: input, socket: socket, arguments: arguments, extraEnvironment: extraEnvironment, closeStdin: closeStdin)
    }

    private static func launch(
        input: Data,
        socket: String,
        arguments: [String],
        extraEnvironment: [String: String],
        closeStdin: Bool
    ) throws -> HookRun {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ["HOME": "/Users/tester", "KOHAI_SOCKET": socket, "PATH": "/usr/bin:/bin"]
        environment.merge(extraEnvironment) { _, new in new }
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let start = Date()
        try process.run()
        try? stdin.fileHandleForWriting.write(contentsOf: input) // EPIPE is fine: the hook may not read
        if closeStdin { try? stdin.fileHandleForWriting.close() }
        process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        if !closeStdin { try? stdin.fileHandleForWriting.close() }

        return HookRun(
            exitCode: process.terminationStatus,
            elapsed: elapsed,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    static func bindAndListen(_ path: String, backlog: Int32) throws -> Int32 {
        let fd = try bind(path)
        #expect(listen(fd, backlog) == 0)
        return fd
    }

    static func bindAndAbandon(_ path: String) throws {
        close(try bind(path))
    }

    private static func bind(_ path: String) throws -> Int32 {
        #if canImport(Darwin)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        #expect(fd >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                #if canImport(Darwin)
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Glibc.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }
        #expect(rc == 0)
        return fd
    }
}
