import Foundation
import Testing
@testable import KohaiCore

@Suite("Terminal jump plan")
struct TerminalJumpTests {
    @Test func iTermPrefersSessionIDThenTTYThenActivate() {
        let info = TerminalInfo(termProgram: "iTerm.app", itermSessionID: "GUID", tty: "/dev/ttys004")
        #expect(TerminalJump.plan(for: info) == [
            .iTermSession("GUID"), .iTermTTY("/dev/ttys004"), .activate(.iTerm),
        ])
    }

    @Test func iTermWithoutIDsStillActivates() {
        #expect(TerminalJump.plan(for: TerminalInfo(termProgram: "iTerm.app")) == [.activate(.iTerm)])
    }

    @Test func terminalAppUsesTTY() {
        let info = TerminalInfo(termProgram: "Apple_Terminal", termSessionID: "X", tty: "/dev/ttys002")
        #expect(TerminalJump.plan(for: info) == [.terminalTTY("/dev/ttys002"), .activate(.terminal)])
    }

    @Test(arguments: [
        ("ghostty", TerminalApp.ghostty), ("WezTerm", .wezTerm), ("WarpTerminal", .warp), ("vscode", .vsCode),
    ])
    func otherTerminalsAreOnlyActivated(program: String, app: TerminalApp) {
        let info = TerminalInfo(termProgram: program, tty: "/dev/ttys009")
        #expect(TerminalJump.plan(for: info) == [.activate(app)])
    }

    @Test func unknownTerminalFallsBackToTTYMatch() {
        let info = TerminalInfo(termProgram: "SomethingNew", tty: "/dev/ttys001")
        #expect(TerminalJump.plan(for: info) == [.iTermTTY("/dev/ttys001"), .terminalTTY("/dev/ttys001")])
        #expect(TerminalJump.plan(for: TerminalInfo()) == [])
    }

    @Test func tmuxIgnoresInnerIDsAndUsesClientTTY() {
        // ITERM_SESSION_ID and the pane tty are stale inside tmux.
        let info = TerminalInfo(termProgram: "tmux", itermSessionID: "STALE", tmuxPane: "%3", tty: "/dev/ttys010")
        #expect(TerminalJump.plan(for: info, tmuxClientTTY: "/dev/ttys001") == [
            .iTermTTY("/dev/ttys001"), .terminalTTY("/dev/ttys001"),
        ])
        #expect(TerminalJump.plan(for: info, tmuxClientTTY: nil) == [])
        #expect(TerminalJump.plan(for: info, tmuxClientTTY: "") == [])
    }

    @Test func scriptsQuoteValues() {
        #expect(JumpTarget.quoted(#"a"b\c"#) == #""a\"b\\c""#)
        let script = JumpTarget.iTermSession(#"x" & do shell script "y"#).appleScript ?? ""
        #expect(script.contains(#"unique id of s is "x\" & do shell script \"y""#))
        #expect(JumpTarget.terminalTTY("/dev/ttys002").appleScript?.contains(#"tty of t is "/dev/ttys002""#) == true)
        #expect(JumpTarget.activate(.ghostty).appleScript == nil)
    }

    @Test func targetsKnowTheirApp() {
        #expect(JumpTarget.iTermTTY("t").app == .iTerm)
        #expect(JumpTarget.terminalTTY("t").app == .terminal)
        #expect(JumpTarget.activate(.warp).app == .warp)
    }
}
