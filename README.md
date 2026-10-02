# Kohai

macOS menu bar app that lists running Claude Code (and Codex) sessions and shows which ones need your input.
Local only: no network, no telemetry, no persistence.

**Status: Milestone 1. Written without a Swift compiler (cloud session). It has not been built or tested yet.
Expect a first round of compile fixes on the Mac.**

## How it works

```
claude / codex ──hook──▶ kohai-hook <agent> ──Unix socket──▶ Kohai.app (MenuBarExtra)
   stdin JSON             + terminal info                      SessionStore state machine
                          150 ms watchdog, exit 0, silent      ~/Library/Application Support/Kohai/agent.sock
```

| Hook event | Session effect |
|---|---|
| SessionStart | create as **done**; if it exists, update details only |
| UserPromptSubmit | → **working**, clear pending permissions |
| PermissionRequest | add pending permission → **needs input** |
| PostToolUse / PostToolUseFailure | remove the matching pending permission; none left → **working** |
| Stop | → **done** |
| SessionEnd / Clear button | remove |
| anything else (Notification, SubagentStop, …) | ignored |

`PermissionRequest` is used instead of `Notification`: it fires ~0.1 s after the dialog appears, `Notification(permission_prompt)` ~6 s later.
Events are ordered by the hook's timestamp; late or duplicate events are dropped.

## Layout

- `Sources/KohaiCore` – event model, payload parser, state machine, terminal probe, Unix socket client/listener
- `Sources/kohai-hook` – the hook CLI
- `Sources/Kohai` – the menu bar app (built only on macOS). `KohaiApp.swift` / `SessionMenuView.swift` own the store
  and map Core sessions to the design system's presentation models; `Design/` (tokens, copy), `Views/` and
  `Previews/` are the design system and never import Core
- `Tests/KohaiCoreTests` – unit tests; `Fixtures/claude` are payloads captured from Claude Code 2.1.286, `Fixtures/codex` are built from Codex's hook schemas
- `Tests/KohaiHookTests` – runs the built `kohai-hook` binary (exit code, silence, 200 ms budget)
- `Tests/KohaiTests` – token contrast checks; `SnapshotTests` renders every preview state to `design-snapshots/*.png`
  (set `KOHAI_SNAPSHOT_DIR` to write them elsewhere)
- `Support/Info.plist`, `scripts/build-app.sh` – app bundle (LSUIElement, ad-hoc signed)

## Build and test

Requires Xcode 27 / Swift 6.4 (deployment target macOS 26). Tests use Swift Testing, so Command Line Tools are enough for `swift test`.

```sh
swift test                  # all unit + hook process tests
scripts/build-app.sh        # → build/Kohai.app (contains kohai-hook)
open build/Kohai.app
```

Quit from the menu (⌘Q in the popover). SIGTERM/SIGINT/SIGHUP also quit cleanly. The socket file is removed on quit.

## Connecting agents

On first launch Kohai lists the agent config folders it finds in your home folder (`~/.claude`,
`~/.claude-*`, `~/.codex`, `~/.codex-*`) and asks which ones to connect. Nothing is written until you click
**Connect**. For each selected folder it adds one `kohai-hook` entry per event to `settings.json` (Claude Code)
or `hooks.json` (Codex), keeps everything else, and saves the previous file as `<file>.kohai-backup`.
**Agents…** in the dropdown footer reopens the list: connect more, **Disconnect** (removes only Kohai's
entries), or **Add a folder…** for a config dir elsewhere. If the app moves, accounts show *Needs update*.
Running sessions must be restarted to pick up new hooks.

## Manual acceptance test (never touches ~/.claude)

```sh
export KOHAI_CFG="$(mktemp -d /tmp/kohai-claude.XXXXXX)"
HOOK="$PWD/build/Kohai.app/Contents/MacOS/kohai-hook"
python3 - "$KOHAI_CFG/settings.json" "$HOOK" <<'EOF'
import json, sys
path, hook = sys.argv[1], sys.argv[2]
entry = lambda: [{"hooks": [{"type": "command", "command": hook, "args": ["claude"], "timeout": 1}]}]
events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd"]
json.dump({"hooks": {e: entry() for e in events}}, open(path, "w"), indent=2)
EOF
cat "$KOHAI_CFG/settings.json"
```

Then, with `build/Kohai.app` running:

1. In two iTerm2 tabs, in two different project folders: `CLAUDE_CONFIG_DIR="$KOHAI_CFG" claude`.
   A fresh config dir needs its own login, and hooks only run after you accept the folder trust dialog.
   → both sessions appear in the menu, grouped by project, account shown as `/tmp/kohai-claude.…`.
2. Ask one session: `run: touch kohai-test.txt`. When the permission dialog appears, the menu bar shows `1`
   and that row says **Needs input** (target: < 2 s).
3. Approve. The row returns to **Working** when the command finishes, then **Done** after Claude stops.
4. `/exit` in a tab → the row disappears.
5. Quit Kohai → `ls ~/Library/Application\ Support/Kohai/` shows no `agent.sock`.

`args` (exec form, no shell) was verified on Claude Code 2.1.286. On older versions use `"command": "'/path/to/kohai-hook' claude"`.

Codex (not part of the M1 acceptance): same entries in `$CODEX_HOME/hooks.json` with `"command": "/path/to/kohai-hook codex"`;
Codex asks you to trust the hooks once.

## Known limitations (M1)

- Esc at a permission prompt fires no hook: the row stays **Needs input** until the next prompt, Stop, or Clear.
- After approving, the row returns to **Working** only when the tool finishes (no "approved" event exists).
- AskUserQuestion, plan approval and MCP input dialogs: not verified to fire `PermissionRequest`.
- Codex questions (`request_user_input`) have no hook.
- Sessions already running when Kohai starts appear on their next event; state is memory-only.
- A killed terminal may not send SessionEnd; use Clear.
- tmux: the captured TTY is the pane's, not the terminal tab's (matters for tab focusing later).
- After a crash or SIGKILL the socket file stays; the next launch removes it.
- If you hide Kohai via System Settings › Menu Bar, there is no other way to reach it.
