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
