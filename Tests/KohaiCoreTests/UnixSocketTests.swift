import Foundation
import Testing
@testable import KohaiCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Thread-safe collector for messages delivered on the listener's background queue.
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func add(_ data: Data) {
        lock.lock(); items.append(data); lock.unlock()
    }

    var messages: [Data] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    /// Waits up to `timeout` for at least `count` messages.
    func wait(for count: Int, timeout: TimeInterval = 2) -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)
        while messages.count < count, Date() < deadline { usleep(10_000) }
        return messages
    }
}

/// Short unique path: sun_path is limited to 104 bytes on macOS.
func temporarySocketPath() -> String {
    "/tmp/kohai-test-\(UUID().uuidString.prefix(8)).sock"
}

func fileExists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
}

@Suite("Unix socket", .serialized)
struct UnixSocketTests {
    @Test func roundTrip() throws {
        let path = temporarySocketPath()
        let inbox = Inbox()
        let listener = SocketListener(path: path) { inbox.add($0) }
        try listener.start()
        defer { listener.stop() }

        #expect(SocketClient.send(Data("hello".utf8), to: path, timeout: 0.5))
        #expect(SocketClient.send(Data("world".utf8), to: path, timeout: 0.5))
        let received = Set(inbox.wait(for: 2).map { String(decoding: $0, as: UTF8.self) })
        #expect(received == ["hello", "world"])
    }

    @Test func socketFileIsUserOnly() throws {
        let path = temporarySocketPath()
        let listener = SocketListener(path: path) { _ in }
        try listener.start()
        defer { listener.stop() }
        var info = stat()
        #expect(lstat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test func stopRemovesSocketFile() throws {
        let path = temporarySocketPath()
        let listener = SocketListener(path: path) { _ in }
        try listener.start()
        #expect(fileExists(path))
        listener.stop()
        #expect(!fileExists(path))
        #expect(!SocketClient.send(Data("late".utf8), to: path, timeout: 0.2))
        listener.stop() // second stop is harmless
    }

    @Test func staleSocketFileIsReplaced() throws {
        let path = temporarySocketPath()
        // Simulate a crashed run: a socket file with nobody listening.
        try makeStaleSocketFile(at: path)
        #expect(fileExists(path))

        let inbox = Inbox()
        let second = SocketListener(path: path) { inbox.add($0) }
        try second.start()
        defer { second.stop() }
        #expect(SocketClient.send(Data("ok".utf8), to: path, timeout: 0.5))
        #expect(inbox.wait(for: 1).count == 1)
    }

    @Test func liveSocketIsNotStolen() throws {
        let path = temporarySocketPath()
        let first = SocketListener(path: path) { _ in }
        try first.start()
        defer { first.stop() }
        let second = SocketListener(path: path) { _ in }
        #expect(throws: SocketError.alreadyRunning) { try second.start() }
        #expect(SocketClient.isListening(at: path))
    }

    @Test func regularFileAtPathIsNotDeleted() throws {
        let path = temporarySocketPath()
        #expect(FileManager.default.createFile(atPath: path, contents: Data("keep".utf8)))
        defer { unlink(path) }
        let listener = SocketListener(path: path) { _ in }
        #expect(throws: SocketError.notASocket) { try listener.start() }
        #expect(FileManager.default.contents(atPath: path) == Data("keep".utf8))
    }

    @Test func stopDoesNotRemoveAnotherInstancesSocket() throws {
        let path = temporarySocketPath()
        let first = SocketListener(path: path) { _ in }
        try first.start()
        // Someone replaced the file (e.g. a second instance after a forced unlink).
        unlink(path)
        let second = SocketListener(path: path) { _ in }
        try second.start()
        defer { second.stop() }
        first.stop()
        #expect(fileExists(path))
        #expect(SocketClient.isListening(at: path))
    }

    @Test func oversizedAndGarbageMessagesDoNotStopTheListener() throws {
        let path = temporarySocketPath()
        let inbox = Inbox()
        let listener = SocketListener(path: path) { inbox.add($0) }
        try listener.start()
        defer { listener.stop() }

        SocketClient.send(Data(repeating: 0x41, count: SocketListener.maxMessageBytes + 10), to: path, timeout: 2)
        SocketClient.send(Data([0x00, 0xFF, 0x10]), to: path, timeout: 0.5)
        #expect(SocketClient.send(Data("after".utf8), to: path, timeout: 0.5))
        let received = inbox.wait(for: 2).map { String(decoding: $0, as: UTF8.self) }
        #expect(received.contains("after"))
        #expect(!received.contains { $0.count > SocketListener.maxMessageBytes })
    }

    @Test func clientFailsQuietlyWhenNothingListens() {
        let start = Date()
        #expect(!SocketClient.send(Data("x".utf8), to: temporarySocketPath(), timeout: 0.1))
        #expect(!SocketClient.send(Data("x".utf8), to: String(repeating: "a", count: 300), timeout: 0.1))
        #expect(Date().timeIntervalSince(start) < 0.2)
    }

    @Test func defaultSocketPath() {
        #expect(KohaiPaths.socketPath(environment: ["HOME": "/Users/me"]) == "/Users/me/Library/Application Support/Kohai/agent.sock")
        #expect(KohaiPaths.socketPath(environment: ["HOME": "/Users/me", "KOHAI_SOCKET": "/tmp/k.sock"]) == "/tmp/k.sock")
    }
}

/// Binds a socket at `path` and closes it without unlinking, leaving a stale socket file.
func makeStaleSocketFile(at path: String) throws {
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
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    #expect(rc == 0)
    close(fd)
}
