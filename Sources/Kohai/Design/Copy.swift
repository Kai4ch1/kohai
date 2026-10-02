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
    // MARK: Connect agents
    static let connectTitle = CopyEntry(
        key: "connect.title",
        polite: "May I listen to your agents?",
        serious: "Connect your agents")
    static let connectBody = CopyEntry(
        key: "connect.body",
        polite: "I'll add one small hook to each folder you pick. Nothing else changes, and a backup is kept.",
        serious: "Kohai adds a hook entry to each selected config. Nothing else changes; a backup is kept.")
    static let connectAction = CopyEntry(
        key: "connect.action",
        polite: "Connect {n}",
        serious: "Connect {n}")
    static let connectDone = CopyEntry(
        key: "connect.done",
        polite: "Done",
        serious: "Done")
    static let connectAddFolder = CopyEntry(
        key: "connect.addFolder",
        polite: "Add a folder…",
        serious: "Add folder…")
    static let connectNoneFound = CopyEntry(
        key: "connect.noneFound",
        polite: "I couldn't find Claude Code or Codex here. Point me to a config folder?",
        serious: "No Claude Code or Codex config folders found.")
    static let connectRestart = CopyEntry(
        key: "connect.restart",
        polite: "Connected. Please restart running sessions so they report to me.",
        serious: "Connected. Restart running sessions to see them here.")
    static let connectFailed = CopyEntry(
        key: "connect.failed",
        polite: "I couldn't change {file}: {reason}",
        serious: "Could not update {file}: {reason}")
    static let accountConnected = CopyEntry(
        key: "account.connected",
        polite: "Connected",
        serious: "Connected")
    static let accountNotConnected = CopyEntry(
        key: "account.notConnected",
        polite: "Not connected",
        serious: "Not connected")
    static let accountNeedsUpdate = CopyEntry(
        key: "account.needsUpdate",
        polite: "Needs updating",
        serious: "Needs update")
    static let accountUnreadable = CopyEntry(
        key: "account.unreadable",
        polite: "I can't read its settings ({reason}), so I won't touch it",
        serious: "Settings unreadable ({reason}); left unchanged")
    static let accountDisconnect = CopyEntry(
        key: "account.disconnect",
        polite: "Disconnect",
        serious: "Disconnect")
    static let hintAccountsPending = CopyEntry(
        key: "hint.accountsPending",
        polite: "{n} not connected yet.",
        serious: "{n} not connected.")
    static let hintConnect = CopyEntry(
        key: "hint.connect",
        polite: "Connect",
        serious: "Connect")
    static let footerAgents = CopyEntry(
        key: "footer.agents",
        polite: "Agents…",
        serious: "Agents…")

    // MARK: Main window, space editor, Settings (Milestone 2)
    static let windowTitle = CopyEntry(
        key: "window.title",
        polite: "Kohai",
        serious: "Kohai")
    static let sidebarAll = CopyEntry(
        key: "sidebar.all",
        polite: "Everyone",
        serious: "All sessions")
    static let sidebarUnsorted = CopyEntry(
        key: "sidebar.unsorted",
        polite: "Unsorted",
        serious: "Unsorted")
    static let sidebarSpaces = CopyEntry(
        key: "sidebar.spaces",
        polite: "Spaces",
        serious: "Spaces")
    static let sidebarNewSpace = CopyEntry(
        key: "sidebar.newSpace",
        polite: "New space…",
        serious: "New space…")
    static let spaceEdit = CopyEntry(
        key: "space.edit",
        polite: "Edit…",
        serious: "Edit…")
    static let spaceMute = CopyEntry(
        key: "space.mute",
        polite: "Mute notifications",
        serious: "Mute notifications")
    static let spaceUnmute = CopyEntry(
        key: "space.unmute",
        polite: "Unmute notifications",
        serious: "Unmute notifications")
    static let spaceMoveUp = CopyEntry(
        key: "space.moveUp",
        polite: "Move up",
        serious: "Move up")
    static let spaceMoveDown = CopyEntry(
        key: "space.moveDown",
        polite: "Move down",
        serious: "Move down")
    static let spaceMutedLabel = CopyEntry(
        key: "space.mutedLabel",
        polite: "muted",
        serious: "muted")
    static let sessionsEmptyTitle = CopyEntry(
        key: "sessions.emptyTitle",
        polite: "Nobody is here, senpai.",
        serious: "No sessions here.")
    static let sessionsEmptyBody = CopyEntry(
        key: "sessions.emptyBody",
        polite: "Sessions show up as soon as an agent starts.",
        serious: "Sessions appear when an agent starts.")
    static let detailEmpty = CopyEntry(
        key: "detail.empty",
        polite: "Pick someone and I'll tell you about them.",
        serious: "Select a session.")
    static let detailJump = CopyEntry(
        key: "detail.jump",
        polite: "Take me to their desk",
        serious: "Jump to terminal")
    static let detailClear = CopyEntry(
        key: "detail.clear",
        polite: "Forget this one",
        serious: "Clear from list")
    static let detailProject = CopyEntry(
        key: "detail.project",
        polite: "Project",
        serious: "Project")
    static let detailFolder = CopyEntry(
        key: "detail.folder",
        polite: "Folder",
        serious: "Folder")
    static let detailRemote = CopyEntry(
        key: "detail.remote",
        polite: "Git remote",
        serious: "Git remote")
    static let detailNoRemote = CopyEntry(
        key: "detail.noRemote",
        polite: "none",
        serious: "none")
    static let detailAccount = CopyEntry(
        key: "detail.account",
        polite: "Account",
        serious: "Account")
    static let detailSpace = CopyEntry(
        key: "detail.space",
        polite: "Space",
        serious: "Space")
    static let detailTerminal = CopyEntry(
        key: "detail.terminal",
        polite: "Terminal",
        serious: "Terminal")
    static let detailLastMessage = CopyEntry(
        key: "detail.lastMessage",
        polite: "Last words",
        serious: "Last message")
    static let detailSelectHint = CopyEntry(
        key: "detail.selectHint",
        polite: "Shows the details",
        serious: "Shows details")
    static let terminalClaudeApp = CopyEntry(
        key: "terminal.claudeApp",
        polite: "Claude app",
        serious: "Claude app")
    static let terminalUnknown = CopyEntry(
        key: "terminal.unknown",
        polite: "unknown",
        serious: "unknown")
    static let warningUnreadable = CopyEntry(
        key: "warning.unreadable",
        polite: "I couldn't read my notes, so I started fresh. Your old file is safe at {path}.",
        serious: "Settings could not be read; defaults are in use. The old file was kept at {path}.")
    static let warningNewer = CopyEntry(
        key: "warning.newer",
        polite: "My notes were written by a newer Kohai, so I started fresh. They are safe at {path}.",
        serious: "Settings were written by a newer Kohai; defaults are in use. The file was kept at {path}.")
    static let warningSaveFailed = CopyEntry(
        key: "warning.saveFailed",
        polite: "I couldn't save my notes: {reason}",
        serious: "Settings could not be saved: {reason}")
    static let warningShowFile = CopyEntry(
        key: "warning.showFile",
        polite: "Show in Finder",
        serious: "Show in Finder")
    static let editorNewTitle = CopyEntry(
        key: "editor.newTitle",
        polite: "A new space",
        serious: "New space")
    static let editorEditTitle = CopyEntry(
        key: "editor.editTitle",
        polite: "Edit space",
        serious: "Edit space")
    static let editorName = CopyEntry(
        key: "editor.name",
        polite: "Name",
        serious: "Name")
    static let editorNamePlaceholder = CopyEntry(
        key: "editor.namePlaceholder",
        polite: "Work",
        serious: "Work")
    static let editorColor = CopyEntry(
        key: "editor.color",
        polite: "Color",
        serious: "Color")
    static let editorSymbol = CopyEntry(
        key: "editor.symbol",
        polite: "Symbol",
        serious: "Symbol")
    static let editorRules = CopyEntry(
        key: "editor.rules",
        polite: "Who belongs here",
        serious: "Rules")
    static let editorRulesHelp = CopyEntry(
        key: "editor.rulesHelp",
        polite: "A session joins the first space whose rule fits. Accounts beat git remotes, which beat folders.",
        serious: "A session joins the first matching space. Account rules beat git remote rules, which beat folder rules.")
    static let editorNoRules = CopyEntry(
        key: "editor.noRules",
        polite: "No rules yet, so nobody joins on their own.",
        serious: "No rules: sessions never join this space.")
    static let ruleAccount = CopyEntry(
        key: "rule.account",
        polite: "Account",
        serious: "Account")
    static let ruleRemote = CopyEntry(
        key: "rule.remote",
        polite: "Git remote",
        serious: "Git remote")
    static let ruleFolder = CopyEntry(
        key: "rule.folder",
        polite: "Folder",
        serious: "Folder")
    static let ruleRemotePlaceholder = CopyEntry(
        key: "rule.remotePlaceholder",
        polite: "github.com/acme/*",
        serious: "github.com/acme/*")
    static let ruleChooseFolder = CopyEntry(
        key: "rule.chooseFolder",
        polite: "Choose…",
        serious: "Choose…")
    static let ruleAdd = CopyEntry(
        key: "rule.add",
        polite: "Add rule",
        serious: "Add rule")
    static let ruleRemove = CopyEntry(
        key: "rule.remove",
        polite: "Remove rule",
        serious: "Remove rule")
    static let editorSave = CopyEntry(
        key: "editor.save",
        polite: "Save",
        serious: "Save")
    static let editorCancel = CopyEntry(
        key: "editor.cancel",
        polite: "Cancel",
        serious: "Cancel")
    static let editorDelete = CopyEntry(
        key: "editor.delete",
        polite: "Delete space",
        serious: "Delete space")
    static let editorDeleteHelp = CopyEntry(
        key: "editor.deleteHelp",
        polite: "Its sessions go back to the next matching space or Unsorted.",
        serious: "Its sessions move to the next matching space or Unsorted.")
    static let settingsGeneral = CopyEntry(
        key: "settings.general",
        polite: "General",
        serious: "General")
    static let settingsAccounts = CopyEntry(
        key: "settings.accounts",
        polite: "Accounts",
        serious: "Accounts")
    static let notifyToggle = CopyEntry(
        key: "notify.toggle",
        polite: "Tap my shoulder when someone needs me",
        serious: "Notify when a session needs input")
    static let notifyHelp = CopyEntry(
        key: "notify.help",
        polite: "Once per request. Never for the session you're looking at, never for muted spaces.",
        serious: "One notification per request. None for the focused session or muted spaces.")
    static let notifyMutedSpaces = CopyEntry(
        key: "notify.mutedSpaces",
        polite: "Muted spaces",
        serious: "Muted spaces")
    static let notifyNoSpaces = CopyEntry(
        key: "notify.noSpaces",
        polite: "No spaces yet.",
        serious: "No spaces yet.")
    static let notifyDeniedTitle = CopyEntry(
        key: "notify.deniedTitle",
        polite: "macOS won't let me tap your shoulder.",
        serious: "Notifications are turned off for Kohai.")
    static let notifyDeniedBody = CopyEntry(
        key: "notify.deniedBody",
        polite: "Allow Kohai under Notifications in System Settings.",
        serious: "Allow Kohai in System Settings > Notifications.")
    static let notifyDeniedAction = CopyEntry(
        key: "notify.deniedAction",
        polite: "Open System Settings",
        serious: "Open System Settings")
    static let notificationClaudeApp = CopyEntry(
        key: "notification.claudeApp",
        polite: "Claude app",
        serious: "Claude app")
    static let accountsHelp = CopyEntry(
        key: "accounts.help",
        polite: "Give each config folder a name and color so you can tell them apart.",
        serious: "Name and color each agent config folder.")
    static let accountsNamePlaceholder = CopyEntry(
        key: "accounts.namePlaceholder",
        polite: "Name",
        serious: "Name")
    static let accountsUnnamed = CopyEntry(
        key: "accounts.unnamed",
        polite: "unnamed",
        serious: "unnamed")

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
        connectTitle, connectBody, connectAction, connectDone, connectAddFolder, connectNoneFound,
        connectRestart, connectFailed,
        accountConnected, accountNotConnected, accountNeedsUpdate, accountUnreadable, accountDisconnect,
        hintAccountsPending, hintConnect, footerAgents,
        windowTitle, sidebarAll, sidebarUnsorted, sidebarSpaces, sidebarNewSpace, spaceEdit, spaceMute, spaceUnmute, spaceMoveUp, spaceMoveDown, spaceMutedLabel, sessionsEmptyTitle, sessionsEmptyBody, detailEmpty, detailJump, detailClear, detailProject, detailFolder, detailRemote, detailNoRemote, detailAccount, detailSpace, detailTerminal, detailLastMessage, detailSelectHint, terminalClaudeApp, terminalUnknown, warningUnreadable, warningNewer, warningSaveFailed, warningShowFile, editorNewTitle, editorEditTitle, editorName, editorNamePlaceholder, editorColor, editorSymbol, editorRules, editorRulesHelp, editorNoRules, ruleAccount, ruleRemote, ruleFolder, ruleRemotePlaceholder, ruleChooseFolder, ruleAdd, ruleRemove, editorSave, editorCancel, editorDelete, editorDeleteHelp, settingsGeneral, settingsAccounts, notifyToggle, notifyHelp, notifyMutedSpaces, notifyNoSpaces, notifyDeniedTitle, notifyDeniedBody, notifyDeniedAction, notificationClaudeApp, accountsHelp, accountsNamePlaceholder, accountsUnnamed,
        menuBarNone, menuBarSome,
    ]
}
