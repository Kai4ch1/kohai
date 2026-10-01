import Foundation

/// Terminal apps Kohai knows how to bring forward.
public enum TerminalApp: String, Sendable, CaseIterable {
    case iTerm = "com.googlecode.iterm2"
    case terminal = "com.apple.Terminal"
    case ghostty = "com.mitchellh.ghostty"
    case wezTerm = "com.github.wez.wezterm"
    case warp = "dev.warp.Warp-Stable"
    case vsCode = "com.microsoft.VSCode"

    public var bundleID: String { rawValue }

    /// TERM_PROGRAM value -> app. "tmux" is deliberately absent: the outer terminal is unknown.
    public init?(termProgram: String) {
        switch termProgram {
        case "iTerm.app": self = .iTerm
        case "Apple_Terminal": self = .terminal
        case "ghostty": self = .ghostty
        case "WezTerm": self = .wezTerm
        case "WarpTerminal": self = .warp
        case "vscode": self = .vsCode // VS Code and its forks all report "vscode"
        default: return nil
        }
    }
}

/// One way of focusing a session. A plan is tried in order until one target succeeds.
public enum JumpTarget: Sendable, Equatable {
    /// iTerm2 session by `unique id` (the GUID part of ITERM_SESSION_ID).
    case iTermSession(String)
    /// iTerm2 session by tty.
    case iTermTTY(String)
    /// Terminal.app tab by tty.
    case terminalTTY(String)
    /// Bring the app forward without selecting a tab (terminals without AppleScript tab access).
    case activate(TerminalApp)

    public var app: TerminalApp {
        switch self {
        case .iTermSession, .iTermTTY: .iTerm
        case .terminalTTY: .terminal
        case .activate(let app): app
        }
    }

    /// AppleScript that selects the session and returns "ok", or returns "notfound".
    /// nil for `.activate`, which needs no scripting.
    public var appleScript: String? {
        switch self {
        case .iTermSession(let id):
            return Self.iTermScript(match: "unique id of s is \(Self.quoted(id))")
        case .iTermTTY(let tty):
            return Self.iTermScript(match: "tty of s is \(Self.quoted(tty))")
        case .terminalTTY(let tty):
            return """
                tell application id "\(TerminalApp.terminal.bundleID)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is \(Self.quoted(tty)) then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end tell
                return "notfound"
                """
        case .activate:
            return nil
        }
    }

    private static func iTermScript(match condition: String) -> String {
        """
        tell application id "\(TerminalApp.iTerm.bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(condition) then
                            tell w to select
                            tell t to select
                            tell s to select
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
        """
    }

    /// AppleScript string literal.
    static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public enum TerminalJump {
    /// Focus targets for a session, most precise first. Empty when nothing is known.
    ///
    /// Inside tmux the captured tty and ITERM_SESSION_ID belong to the tmux pane or to whatever
    /// terminal started the tmux server, so they are ignored; the caller selects the pane and
    /// passes the tty of the tmux client showing it as `tmuxClientTTY`.
    public static func plan(for info: TerminalInfo, tmuxClientTTY: String? = nil) -> [JumpTarget] {
        if info.tmuxPane != nil {
            guard let tty = tmuxClientTTY, !tty.isEmpty else { return [] }
            return [.iTermTTY(tty), .terminalTTY(tty)]
        }

        let app = info.termProgram.flatMap(TerminalApp.init(termProgram:))
        switch app {
        case .iTerm:
            var targets: [JumpTarget] = []
            if let id = info.itermSessionID { targets.append(.iTermSession(id)) }
            if let tty = info.tty { targets.append(.iTermTTY(tty)) }
            return targets + [.activate(.iTerm)]
        case .terminal:
            return (info.tty.map { [.terminalTTY($0)] } ?? []) + [.activate(.terminal)]
        case .some(let other):
            return [.activate(other)]
        case nil:
            // Unknown terminal: a tty still identifies an iTerm2 or Terminal.app tab.
            guard let tty = info.tty else { return [] }
            return [.iTermTTY(tty), .terminalTTY(tty)]
        }
    }
}
