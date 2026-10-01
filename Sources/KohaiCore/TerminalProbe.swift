import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// One row of the process table, as far as the TTY walk needs it.
public struct ProcessEntry: Sendable, Equatable {
    public var parentPID: Int32
    /// Controlling terminal path such as "/dev/ttys003", or nil when the process has none.
    public var tty: String?

    public init(parentPID: Int32, tty: String?) {
        self.parentPID = parentPID
        self.tty = tty
    }
}

public enum TerminalProbe {
    /// Terminal info from the hook's inherited environment plus an already-resolved TTY.
    public static func info(environment env: [String: String], tty: String?) -> TerminalInfo {
        func value(_ name: String) -> String? {
            guard let v = env[name], !v.isEmpty else { return nil }
            return v
        }
        var itermID = value("ITERM_SESSION_ID")
        if let raw = itermID, let colon = raw.firstIndex(of: ":") {
            let guid = String(raw[raw.index(after: colon)...])
            itermID = guid.isEmpty ? nil : guid
        }
        return TerminalInfo(
            termProgram: value("TERM_PROGRAM"),
            itermSessionID: itermID,
            termSessionID: value("TERM_SESSION_ID"),
            tmuxPane: value("TMUX") != nil ? value("TMUX_PANE") : nil,
            tty: tty
        )
    }

    /// Walks up from `pid` until a process with a controlling terminal is found.
    /// Hooks run detached from the terminal (Claude Code and Codex both start them in a new
    /// session), so the TTY has to come from the agent process or one of its ancestors.
    /// Stops at pid 1, on a cycle, on a lookup failure, or after `maxDepth` steps.
    public static func findTTY(
        startingAt pid: Int32,
        maxDepth: Int = 16,
        lookup: (Int32) -> ProcessEntry?
    ) -> String? {
        var current = pid
        var visited = Set<Int32>()
        for _ in 0..<maxDepth {
            guard current > 1, visited.insert(current).inserted, let entry = lookup(current) else { return nil }
            if let tty = entry.tty { return tty }
            current = entry.parentPID
        }
        return nil
    }

    /// TTY of the nearest ancestor of this process that has one. nil on platforms other than macOS.
    public static func controllingTTY() -> String? {
        #if canImport(Darwin)
        return findTTY(startingAt: getpid(), lookup: darwinLookup)
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    /// Process info via sysctl(KERN_PROC_PID): parent pid and controlling tty device.
    public static func darwinLookup(_ pid: Int32) -> ProcessEntry? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        // A pid that does not exist returns success with size 0.
        guard rc == 0, size > 0 else { return nil }

        let device = info.kp_eproc.e_tdev
        var tty: String?
        let noDevice: dev_t = -1 // NODEV
        if device != noDevice {
            var name = [CChar](repeating: 0, count: 128)
            if let result = devname_r(device, S_IFCHR, &name, Int32(name.count)) {
                let deviceName = String(cString: result)
                if !deviceName.isEmpty, deviceName != "??" { tty = "/dev/" + deviceName }
            }
        }
        return ProcessEntry(parentPID: info.kp_eproc.e_ppid, tty: tty)
    }
    #endif
}
