import Foundation
import Testing
@testable import KohaiCore

@Suite("Terminal probe")
struct TerminalProbeTests {
    @Test func iTermEnvironment() {
        let info = TerminalProbe.info(
            environment: [
                "TERM_PROGRAM": "iTerm.app",
                "ITERM_SESSION_ID": "w0t1p0:8E2A0C4B-1111-2222-3333-444455556666",
                "TERM_SESSION_ID": "w0t1p0:8E2A0C4B-1111-2222-3333-444455556666",
            ],
            tty: "/dev/ttys004"
        )
        #expect(info.termProgram == "iTerm.app")
        #expect(info.itermSessionID == "8E2A0C4B-1111-2222-3333-444455556666")
        #expect(info.tty == "/dev/ttys004")
        #expect(info.tmuxPane == nil)
    }

    @Test func terminalAppAndEmptyValues() {
        let info = TerminalProbe.info(
            environment: ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "ABC", "ITERM_SESSION_ID": "", "TMUX_PANE": "%3"],
            tty: nil
        )
        #expect(info == TerminalInfo(termProgram: "Apple_Terminal", termSessionID: "ABC"))
    }

    @Test func tmuxPaneOnlyInsideTmux() {
        let info = TerminalProbe.info(environment: ["TMUX": "/tmp/tmux-501/default,123,0", "TMUX_PANE": "%3"], tty: nil)
        #expect(info.tmuxPane == "%3")
    }

    @Test func itermIDWithoutPrefixIsKept() {
        #expect(TerminalProbe.info(environment: ["ITERM_SESSION_ID": "GUID"], tty: nil).itermSessionID == "GUID")
        #expect(TerminalProbe.info(environment: ["ITERM_SESSION_ID": "w0t0p0:"], tty: nil).itermSessionID == nil)
    }

    // hook (no tty) -> sh (no tty) -> claude (ttys004) -> zsh (ttys004) -> login -> launchd
    let table: [Int32: ProcessEntry] = [
        500: ProcessEntry(parentPID: 400, tty: nil),
        400: ProcessEntry(parentPID: 300, tty: nil),
        300: ProcessEntry(parentPID: 200, tty: "/dev/ttys004"),
        200: ProcessEntry(parentPID: 100, tty: "/dev/ttys004"),
        100: ProcessEntry(parentPID: 1, tty: nil),
    ]

    @Test func walksUpToNearestTTY() {
        let table = self.table
        let tty = TerminalProbe.findTTY(startingAt: 500) { table[$0] }
        #expect(tty == "/dev/ttys004")
    }

    @Test func stopsAtLaunchdAndUnknownPids() {
        let table = self.table
        let fromLogin = TerminalProbe.findTTY(startingAt: 100) { table[$0] }
        let unknown = TerminalProbe.findTTY(startingAt: 999) { table[$0] }
        let launchd = TerminalProbe.findTTY(startingAt: 1) { _ in ProcessEntry(parentPID: 0, tty: "/dev/console") }
        #expect(fromLogin == nil)
        #expect(unknown == nil)
        #expect(launchd == nil)
    }

    @Test func stopsOnCycles() {
        let cycle: [Int32: ProcessEntry] = [10: ProcessEntry(parentPID: 11, tty: nil), 11: ProcessEntry(parentPID: 10, tty: nil)]
        var lookups = 0
        let result = TerminalProbe.findTTY(startingAt: 10) { pid in
            lookups += 1
            return cycle[pid]
        }
        #expect(result == nil)
        #expect(lookups == 2)
    }

    @Test func respectsDepthLimit() {
        var lookups = 0
        let result = TerminalProbe.findTTY(startingAt: 1000, maxDepth: 5) { pid in
            lookups += 1
            return ProcessEntry(parentPID: pid - 1, tty: nil)
        }
        #expect(result == nil)
        #expect(lookups == 5)
    }

    #if os(macOS)
    /// The sysctl lookup must agree with `ps` for this test process's own ancestry.
    @Test func darwinLookupMatchesPs() throws {
        let pid = getpid()
        let entry = try #require(TerminalProbe.darwinLookup(pid))
        #expect(entry.parentPID == getppid())

        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "tty=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try ps.run()
        ps.waitUntilExit()
        let psTTY = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if psTTY.isEmpty || psTTY == "??" {
            #expect(entry.tty == nil)
        } else {
            #expect(entry.tty == "/dev/" + psTTY)
        }
    }

    @Test func darwinLookupOfMissingPidIsNil() {
        #expect(TerminalProbe.darwinLookup(Int32.max) == nil)
    }
    #endif
}
