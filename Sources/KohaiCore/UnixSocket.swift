import Foundation
#if canImport(Darwin)
import Darwin
private let streamType = SOCK_STREAM
#elseif canImport(Glibc)
import Glibc
private let streamType = Int32(SOCK_STREAM.rawValue)
#endif

public enum KohaiPaths {
    /// `KOHAI_SOCKET` overrides the path (used by tests); otherwise
    /// `~/Library/Application Support/Kohai/agent.sock`.
    public static func socketPath(environment: [String: String]) -> String {
        if let override = environment["KOHAI_SOCKET"], !override.isEmpty { return override }
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return home + "/Library/Application Support/Kohai/agent.sock"
    }
}

public enum SocketError: Error, Equatable {
    case pathTooLong
    case alreadyRunning
    case notASocket
    case system(String, Int32)
}

// MARK: - Shared helpers

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard !bytes.isEmpty, bytes.count < capacity else { throw SocketError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    #if canImport(Darwin)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif
    return address
}

private func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

private func setTimeout(_ fd: Int32, option: Int32, seconds: TimeInterval) {
    var tv = timeval()
    tv.tv_sec = .init(Int(seconds))
    tv.tv_usec = .init(Int((seconds - Double(Int(seconds))) * 1_000_000))
    _ = setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
}

/// Writes to a closed peer must return EPIPE instead of killing the process.
private func disableSigPipe(_ fd: Int32) {
    #if canImport(Darwin)
    var on: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    #endif
}

private func connectSocket(path: String, timeout: TimeInterval) -> Int32? {
    guard var address = try? makeAddress(path) else { return nil }
    let fd = socket(AF_UNIX, streamType, 0)
    guard fd >= 0 else { return nil }
    disableSigPipe(fd)
    setTimeout(fd, option: SO_SNDTIMEO, seconds: timeout)
    setTimeout(fd, option: SO_RCVTIMEO, seconds: timeout)
    let rc = withSockaddr(&address) { connect(fd, $0, $1) }
    guard rc == 0 else {
        close(fd)
        return nil
    }
    return fd
}

// MARK: - Client

public enum SocketClient {
    /// Sends one message and closes. Returns false on any failure; never throws, never raises SIGPIPE.
    @discardableResult
    public static func send(_ data: Data, to path: String, timeout: TimeInterval) -> Bool {
        guard let fd = connectSocket(path: path, timeout: timeout) else { return false }
        defer { close(fd) }
        let ok = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let n = write(fd, base + sent, raw.count - sent)
                if n > 0 {
                    sent += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        _ = shutdown(fd, Int32(SHUT_WR))
        return ok
    }

    /// True when something accepts connections on `path`.
    public static func isListening(at path: String) -> Bool {
        guard let fd = connectSocket(path: path, timeout: 0.2) else { return false }
        close(fd)
        return true
    }
}

// MARK: - Listener

/// Accepts one message per connection (read until EOF) and hands the bytes to `onMessage`
/// on a background queue. Owns the socket file: removes a stale one on start, and on stop
/// removes the file only if it is still the one this listener created.
public final class SocketListener: @unchecked Sendable {
    public static let maxMessageBytes = 1 << 20
    public static let readTimeout: TimeInterval = 1

    public let path: String
    private let onMessage: @Sendable (Data) -> Void
    private let lock = NSLock()
    private var running = false
    private var stopRequested = false
    private var boundFile: (device: UInt64, inode: UInt64)?
    private let loopFinished = DispatchSemaphore(value: 0)

    public init(path: String, onMessage: @escaping @Sendable (Data) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }

        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try removeStaleSocket()

        var address = try makeAddress(path)
        let fd = socket(AF_UNIX, streamType, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        let bound = withSockaddr(&address) { bind(fd, $0, $1) }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw code == EADDRINUSE ? SocketError.alreadyRunning : SocketError.system("bind", code)
        }
        _ = chmod(path, 0o600)
        guard listen(fd, 64) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw SocketError.system("listen", code)
        }
        boundFile = fileIdentity(path)
        running = true
        stopRequested = false

        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "Kohai socket listener"
        thread.start()
    }

    /// Stops accepting, waits briefly for the accept loop to exit and removes the socket file.
    public func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        stopRequested = true
        lock.unlock()

        _ = loopFinished.wait(timeout: .now() + 2)

        lock.lock()
        if let ours = boundFile, let current = fileIdentity(path), ours == current {
            unlink(path)
        }
        boundFile = nil
        running = false
        lock.unlock()
    }

    private var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    private func acceptLoop(_ listenFD: Int32) {
        defer {
            close(listenFD)
            loopFinished.signal()
        }
        while !shouldStop {
            var poller = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 100)
            guard ready > 0 else { continue }
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { continue }
            let handler = onMessage
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = Self.readMessage(client), !data.isEmpty { handler(data) }
            }
        }
    }

    /// Reads until EOF. nil when the peer sends too much, stalls past the timeout or errors.
    private static func readMessage(_ fd: Int32) -> Data? {
        defer { close(fd) }
        disableSigPipe(fd)
        setTimeout(fd, option: SO_RCVTIMEO, seconds: readTimeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
                if data.count > maxMessageBytes { return nil }
            } else if n == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
    }

    /// A leftover socket file from a crashed run is removed; a live one means another instance.
    private func removeStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw SocketError.notASocket }
        if SocketClient.isListening(at: path) { throw SocketError.alreadyRunning }
        unlink(path)
    }

    private func fileIdentity(_ path: String) -> (device: UInt64, inode: UInt64)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (UInt64(truncatingIfNeeded: info.st_dev), UInt64(truncatingIfNeeded: info.st_ino))
    }
}
