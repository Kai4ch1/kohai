import SwiftUI

// =============================================================================
// Copy table. Every user-facing string, in two tones:
//   .polite  : the kohai (junior colleague) speaking to the senpai (the user)
//   .serious : plain, neutral wording for people who don't want the persona
//
// Placeholders look like {project}. `Design/CopyTable.md` is generated from
// this file (same keys, same strings), so edit here and regenerate.
// =============================================================================

enum CopyTone: String, CaseIterable, Sendable {
    case polite
    case serious
}

struct CopyEntry: Sendable {
    let key: String
    let polite: String
    let serious: String

    func text(_ tone: CopyTone, _ args: [String: String] = [:]) -> String {
        var s = (tone == .polite) ? polite : serious
        for (name, value) in args {
            s = s.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return s
    }
}

private struct KohaiCopyToneKey: EnvironmentKey {
    static let defaultValue: CopyTone = .polite
}

extension EnvironmentValues {
    var kohaiCopyTone: CopyTone {
        get { self[KohaiCopyToneKey.self] }
        set { self[KohaiCopyToneKey.self] = newValue }
    }
}

enum Copy {

    // MARK: Header
    static let summaryOne = CopyEntry(
        key: "header.summary.one",
        polite: "1 needs you, senpai",
        serious: "1 needs input")
    static let summaryMany = CopyEntry(
        key: "header.summary.many",
        polite: "{n} need you, senpai",
        serious: "{n} need input")
    static let summaryNone = CopyEntry(
        key: "header.summary.none",
        polite: "All quiet",
        serious: "No sessions need input")
    static let sessionCount = CopyEntry(
        key: "header.sessionCount",
        polite: "{n} at their desks",
        serious: "{n} sessions")
    static let appName = CopyEntry(
        key: "header.appName",
        polite: "Kohai",
        serious: "Kohai")

    // MARK: Status (also the VoiceOver labels of the seals)
    static let statusNeedsInput = CopyEntry(
        key: "status.needsInput",
        polite: "Needs your approval",
        serious: "Needs input")
    static let statusDone = CopyEntry(
        key: "status.done",
        polite: "Finished",
        serious: "Done")
    static let statusWorking = CopyEntry(
        key: "status.working",
        polite: "Working on it",
        serious: "Working")

    // MARK: Rows
    static let jumpHint = CopyEntry(
        key: "row.jumpHint",
        polite: "Takes you to their desk",
        serious: "Jumps to the session")
    static let inStatusFor = CopyEntry(
        key: "row.inStatusFor",
        polite: "for {time}",
        serious: "for {time}")
    static let unknownAgent = CopyEntry(
        key: "row.unknownAgent",
        polite: "Unknown colleague",
        serious: "Unknown agent")
    static let noAccount = CopyEntry(
        key: "row.noAccount",
        polite: "no account",
        serious: "no account")

    // MARK: Notification (needs_input must always also surface here)
    static let notificationTitle = CopyEntry(
        key: "notification.title",
        polite: "Senpai, {project} needs your approval.",
        serious: "{project}: input needed")
    static let notificationBody = CopyEntry(
        key: "notification.body",
        polite: "{agent} is waiting for you in {session}.",
        serious: "{agent} session {session} is waiting for input.")
    static let notificationMockLabel = CopyEntry(
        key: "notification.mockLabel",
        polite: "What you'll see even if my icon is hidden",
        serious: "Notification shown even if the icon is hidden")

    // MARK: Empty
    static let emptyTitle = CopyEntry(
        key: "empty.title",
        polite: "Nobody needs you, senpai.",
        serious: "No sessions need input.")
    static let emptyBody = CopyEntry(
        key: "empty.body",
        polite: "I'll wake you when someone does.",
        serious: "You'll be notified when one does.")

    // MARK: Hooks not installed
    static let hooksTitle = CopyEntry(
        key: "hooks.title",
        polite: "Senpai, I can't hear the others yet.",
        serious: "Hooks are not installed.")
    static let hooksBody = CopyEntry(
        key: "hooks.body",
        polite: "Install the Kohai hooks so Claude Code and Codex can report to you.",
        serious: "Install the Kohai hooks so Claude Code and Codex sessions appear here.")
    static let hooksAction = CopyEntry(
        key: "hooks.action",
        polite: "Install hooks",
        serious: "Install hooks")

    // MARK: Socket / app error
    static let socketTitle = CopyEntry(
        key: "socket.title",
        polite: "Senpai, I lost the line to the others.",
        serious: "Can't connect to the Kohai socket.")
    static let socketBody = CopyEntry(
        key: "socket.body",
        polite: "I can't reach my local socket. Please try again.",
        serious: "The local socket is unreachable. Try again or restart Kohai.")
    static let socketAction = CopyEntry(
        key: "socket.action",
        polite: "Try again",
        serious: "Retry")

    // MARK: Automation permission denied
    static let automationTitle = CopyEntry(
        key: "automation.title",
        polite: "Senpai, I'm not allowed to visit their desks.",
        serious: "Automation permission denied.")
    static let automationBody = CopyEntry(
        key: "automation.body",
        polite: "Allow Kohai under Automation so I can take you to a session.",
        serious: "Allow Kohai under Automation to jump to a session's terminal.")
    static let automationAction = CopyEntry(
        key: "automation.action",
        polite: "Open System Settings",
        serious: "Open System Settings")

    // MARK: Hints (one line each)
    static let firstRunHint = CopyEntry(
        key: "hint.firstRun",
        polite: "Keep my icon visible: Settings > Menu Bar.",
        serious: "Keep the icon visible: Settings > Menu Bar.")
    static let overflowHint = CopyEntry(
        key: "hint.overflow",
        polite: "Icon hidden? I'll still notify you.",
        serious: "Icon hidden. You'll still be notified.")
    static let hintDismiss = CopyEntry(
        key: "hint.dismiss",
        polite: "Got it",
        serious: "Dismiss")

    // MARK: Menu bar icon (VoiceOver)
    static let clearSession = CopyEntry(
        key: "row.clear",
        polite: "Forget this one",
        serious: "Clear from list")
    static let quit = CopyEntry(
        key: "app.quit",
        polite: "Quit Kohai",
        serious: "Quit Kohai")
    static let menuBarNone = CopyEntry(
        key: "menubar.a11y.none",
        polite: "Kohai, nobody needs you",
        serious: "Kohai, no sessions need input")
    static let menuBarSome = CopyEntry(
        key: "menubar.a11y.some",
        polite: "Kohai, {n} need you",
        serious: "Kohai, {n} sessions need input")

    // MARK: Developer-facing placeholders (previews only)
    static let socketPathLabel = CopyEntry(
        key: "socket.pathLabel",
        polite: "Socket",
        serious: "Socket")

    /// Every entry, in table order. The test target asserts keys are unique and
    /// that both tones are non-empty.
    static let all: [CopyEntry] = [
        summaryOne, summaryMany, summaryNone, sessionCount, appName,
        statusNeedsInput, statusDone, statusWorking,
        jumpHint, inStatusFor, unknownAgent, noAccount,
        notificationTitle, notificationBody, notificationMockLabel,
        emptyTitle, emptyBody,
        hooksTitle, hooksBody, hooksAction,
        socketTitle, socketBody, socketAction, socketPathLabel,
        automationTitle, automationBody, automationAction,
        firstRunHint, overflowHint, hintDismiss,
        clearSession, quit,
        menuBarNone, menuBarSome,
    ]
}
