import AppKit
import KohaiCore

enum JumpResult: Sendable {
    case jumped
    /// No target matched, or the terminal is not running.
    case notFound
    /// macOS refused Kohai's Apple Events (System Settings > Privacy & Security > Automation).
    case automationDenied
}

/// Runs a `TerminalJump` plan: tmux pane selection, then AppleScript (via osascript, so a slow
/// or prompting terminal never blocks the menu) or plain activation.
enum TerminalJumper {
    static func jump(to info: TerminalInfo) async -> JumpResult {
        await Task.detached(priority: .userInitiated) { run(info) }.value
    }

    private static func run(_ info: TerminalInfo) -> JumpResult {
        var clientTTY: String?
        if let pane = info.tmuxPane, let tmux = tmuxPath() {
            let tty = execute(tmux, ["display-message", "-p", "-t", pane, "#{client_tty}"]).output
            if !tty.isEmpty {
                clientTTY = tty
                _ = execute(tmux, ["switch-client", "-c", tty, "-t", pane])
            }
            _ = execute(tmux, ["select-window", "-t", pane, ";", "select-pane", "-t", pane])
        }

        var denied = false
        for target in TerminalJump.plan(for: info, tmuxClientTTY: clientTTY) {
            guard let app = runningApp(target.app) else { continue }
            guard let script = target.appleScript else {
                app.activate()
                return denied ? .automationDenied : .jumped
            }
            let result = execute("/usr/bin/osascript", ["-e", script])
            if result.output == "ok" { return .jumped }
            // errAEEventNotPermitted: the user said no, or has not been asked yet and declined.
            if result.error.contains("-1743") { denied = true }
        }
        return denied ? .automationDenied : .notFound
    }

    /// Scripting a terminal that isn't running would launch it; activation needs it running anyway.
    private static func runningApp(_ app: TerminalApp) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first
    }

    /// The app is started by launchd, so PATH does not include Homebrew.
    private static func tmuxPath() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func execute(_ path: String, _ arguments: [String]) -> (output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return ("", "\(error)")
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            String(decoding: error, as: UTF8.self)
        )
    }
}
