# Copy table

Generated from `Design/Copy.swift` (single source of truth). Every string has a **polite** variant (the kohai,
a junior colleague, speaking to the senpai) and a **serious** variant (plain, neutral). Placeholders like `{n}`
are identical in both variants. Tone is chosen by the `kohaiCopyTone` environment value.

| Key | Polite (default) | Serious mode |
|---|---|---|
| `header.summary.one` | 1 needs you, senpai | 1 needs input |
| `header.summary.many` | {n} need you, senpai | {n} need input |
| `header.summary.none` | All quiet | No sessions need input |
| `header.sessionCount` | {n} at their desks | {n} sessions |
| `header.appName` | Kohai | Kohai |
| `status.needsInput` | Needs your approval | Needs input |
| `status.done` | Finished | Done |
| `status.working` | Working on it | Working |
| `row.jumpHint` | Takes you to their desk | Jumps to the session |
| `row.inStatusFor` | for {time} | for {time} |
| `row.unknownAgent` | Unknown colleague | Unknown agent |
| `row.noAccount` | no account | no account |
| `row.clear` | Forget this one | Clear from list |
| `app.quit` | Quit Kohai | Quit Kohai |
| `notification.title` | Senpai, {project} needs your approval. | {project}: input needed |
| `notification.body` | {agent} is waiting for you in {session}. | {agent} session {session} is waiting for input. |
| `notification.mockLabel` | What you'll see even if my icon is hidden | Notification shown even if the icon is hidden |
| `empty.title` | Nobody needs you, senpai. | No sessions need input. |
| `empty.body` | I'll wake you when someone does. | You'll be notified when one does. |
| `hooks.title` | Senpai, I can't hear the others yet. | Hooks are not installed. |
| `hooks.body` | Install the Kohai hooks so Claude Code and Codex can report to you. | Install the Kohai hooks so Claude Code and Codex sessions appear here. |
| `hooks.action` | Install hooks | Install hooks |
| `socket.title` | Senpai, I lost the line to the others. | Can't connect to the Kohai socket. |
| `socket.body` | I can't reach my local socket. Please try again. | The local socket is unreachable. Try again or restart Kohai. |
| `socket.action` | Try again | Retry |
| `automation.title` | Senpai, I'm not allowed to visit their desks. | Automation permission denied. |
| `automation.body` | Allow Kohai under Automation so I can take you to a session. | Allow Kohai under Automation to jump to a session's terminal. |
| `automation.action` | Open System Settings | Open System Settings |
| `hint.firstRun` | Keep my icon visible: Settings > Menu Bar. | Keep the icon visible: Settings > Menu Bar. |
| `hint.overflow` | Icon hidden? I'll still notify you. | Icon hidden. You'll still be notified. |
| `hint.dismiss` | Got it | Dismiss |
| `menubar.a11y.none` | Kohai, nobody needs you | Kohai, no sessions need input |
| `menubar.a11y.some` | Kohai, {n} need you | Kohai, {n} sessions need input |
| `socket.pathLabel` | Socket | Socket |
| `connect.title` | May I listen to your agents? | Connect your agents |
| `connect.body` | I'll add one small hook to each folder you pick. Nothing else changes, and a backup is kept. | Kohai adds a hook entry to each selected config. Nothing else changes; a backup is kept. |
| `connect.action` | Connect {n} | Connect {n} |
| `connect.done` | Done | Done |
| `connect.addFolder` | Add a folder… | Add folder… |
| `connect.noneFound` | I couldn't find Claude Code or Codex here. Point me to a config folder? | No Claude Code or Codex config folders found. |
| `connect.restart` | Connected. Please restart running sessions so they report to me. | Connected. Restart running sessions to see them here. |
| `connect.failed` | I couldn't change {file}: {reason} | Could not update {file}: {reason} |
| `account.connected` | Connected | Connected |
| `account.notConnected` | Not connected | Not connected |
| `account.needsUpdate` | Needs updating | Needs update |
| `account.unreadable` | I can't read its settings ({reason}), so I won't touch it | Settings unreadable ({reason}); left unchanged |
| `account.disconnect` | Disconnect | Disconnect |
| `hint.accountsPending` | {n} not connected yet. | {n} not connected. |
| `hint.connect` | Connect | Connect |
| `footer.agents` | Agents… | Agents… |
| `window.title` | Kohai | Kohai |
| `sidebar.all` | Everyone | All sessions |
| `sidebar.unsorted` | Unsorted | Unsorted |
| `sidebar.spaces` | Spaces | Spaces |
| `sidebar.newSpace` | New space… | New space… |
| `space.edit` | Edit… | Edit… |
| `space.mute` | Mute notifications | Mute notifications |
| `space.unmute` | Unmute notifications | Unmute notifications |
| `space.moveUp` | Move up | Move up |
| `space.moveDown` | Move down | Move down |
| `space.mutedLabel` | muted | muted |
| `sessions.emptyTitle` | Nobody is here, senpai. | No sessions here. |
| `sessions.emptyBody` | Sessions show up as soon as an agent starts. | Sessions appear when an agent starts. |
| `detail.empty` | Pick someone and I'll tell you about them. | Select a session. |
| `detail.jump` | Take me to their desk | Jump to terminal |
| `detail.clear` | Forget this one | Clear from list |
| `detail.project` | Project | Project |
| `detail.folder` | Folder | Folder |
| `detail.remote` | Git remote | Git remote |
| `detail.noRemote` | none | none |
| `detail.account` | Account | Account |
| `detail.space` | Space | Space |
| `detail.terminal` | Terminal | Terminal |
| `detail.lastMessage` | Last words | Last message |
| `detail.selectHint` | Shows the details | Shows details |
| `terminal.claudeApp` | Claude app | Claude app |
| `terminal.unknown` | unknown | unknown |
| `warning.unreadable` | I couldn't read my notes, so I started fresh. Your old file is safe at {path}. | Settings could not be read; defaults are in use. The old file was kept at {path}. |
| `warning.newer` | My notes were written by a newer Kohai, so I started fresh. They are safe at {path}. | Settings were written by a newer Kohai; defaults are in use. The file was kept at {path}. |
| `warning.saveFailed` | I couldn't save my notes: {reason} | Settings could not be saved: {reason} |
| `warning.showFile` | Show in Finder | Show in Finder |
| `editor.newTitle` | A new space | New space |
| `editor.editTitle` | Edit space | Edit space |
| `editor.name` | Name | Name |
| `editor.namePlaceholder` | Work | Work |
| `editor.color` | Color | Color |
| `editor.symbol` | Symbol | Symbol |
| `editor.rules` | Who belongs here | Rules |
| `editor.rulesHelp` | A session joins the first space whose rule fits. Accounts beat git remotes, which beat folders. | A session joins the first matching space. Account rules beat git remote rules, which beat folder rules. |
| `editor.noRules` | No rules yet, so nobody joins on their own. | No rules: sessions never join this space. |
| `rule.account` | Account | Account |
| `rule.remote` | Git remote | Git remote |
| `rule.folder` | Folder | Folder |
| `rule.remotePlaceholder` | github.com/acme/* | github.com/acme/* |
| `rule.chooseFolder` | Choose… | Choose… |
| `rule.add` | Add rule | Add rule |
| `rule.remove` | Remove rule | Remove rule |
| `editor.save` | Save | Save |
| `editor.cancel` | Cancel | Cancel |
| `editor.delete` | Delete space | Delete space |
| `editor.deleteHelp` | Its sessions go back to the next matching space or Unsorted. | Its sessions move to the next matching space or Unsorted. |
| `settings.general` | General | General |
| `settings.accounts` | Accounts | Accounts |
| `notify.toggle` | Tap my shoulder when someone needs me | Notify when a session needs input |
| `notify.help` | Once per request. Never for the session you're looking at, never for muted spaces. | One notification per request. None for the focused session or muted spaces. |
| `notify.mutedSpaces` | Muted spaces | Muted spaces |
| `notify.noSpaces` | No spaces yet. | No spaces yet. |
| `notify.deniedTitle` | macOS won't let me tap your shoulder. | Notifications are turned off for Kohai. |
| `notify.deniedBody` | Allow Kohai under Notifications in System Settings. | Allow Kohai in System Settings > Notifications. |
| `notify.deniedAction` | Open System Settings | Open System Settings |
| `notification.claudeApp` | Claude app | Claude app |
| `accounts.help` | Give each config folder a name and color so you can tell them apart. | Name and color each agent config folder. |
| `accounts.namePlaceholder` | Name | Name |
| `accounts.unnamed` | unnamed | unnamed |
