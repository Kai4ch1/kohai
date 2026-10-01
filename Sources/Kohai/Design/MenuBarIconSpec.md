# Menu bar icon spec

Status: spec + placeholder silhouette. Final mascot art replaces `MascotHeadIcon` later; this spec stays.

## Asset

- One **template image** (`NSImage.isTemplate = true`): black + clear only. The system recolors it for light/dark
  bars, the selected (pressed) state and the transparent bar. Never ship a colored or pre-tinted icon.
- Canvas **18 x 18 pt** (`KohaiMetrics.menuBarIconCanvas`) inside the 24 pt menu bar (Apple HIG: "The menu bar's
  height is 24 pt"). Deliver @1x, @2x, @3x. `MenuBarIconImage.make(filled:)` builds both variants from the same
  vector so they cannot drift.
- Source silhouette: the mascot **head** (round head, eyes as cut-outs). No body, no accessories, no text.

## States

| State | Image | Count text | Color |
|---|---|---|---|
| idle / working / nobody needs you | **outline** head, eyes as dots | none | none (template) |
| needs_input (1 or more) | **filled** head, eyes cut out | `1`...`9`, `9+` beyond | none (template) |

- needs_input is communicated by **shape** (outline -> filled) and a **number**, never by color. Vermilion is not
  used in the menu bar.
- Count: `KohaiType.menuBarCount` (12 pt semibold, monospaced digits), 4 pt right of the icon, same template color.
- VoiceOver: "Kohai, nobody needs you" / "Kohai, {n} need you" (`menubar.a11y.*` in the copy table).

## Legibility (full Liquid Glass transparency range, macOS 27, and the fully transparent macOS 26 bar)

- Outline stroke is at least **1.5 pt** at 18 pt (8.5% of the canvas) so it survives a transparent bar.
- The two states differ by **coverage** (solid vs ring), which stays distinguishable at any foreground/background
  luminance, including the mid-grey worst case in `11-menu-bar-icon.png`.
- No halo, drop effects, tinted outlines or fills: they fight the system's own bar treatment.
- Manual checks (cannot be automated here): both states at min and max Liquid Glass transparency on macOS 27, with
  Reduce Transparency, on a light wallpaper and a dark wallpaper, and once on macOS 26.

## The icon can be hidden (macOS 27 overflow)

HIG: "Avoid relying on the presence of menu bar extras. The system hides and shows menu bar extras regularly" and
"Let people ... decide whether to put your menu bar extra in the menu bar." So the icon is never the only channel:

1. **Notification on every needs_input** (title/body in the copy table, `notification.*`). Preview:
   `10-icon-hidden-overflow.png`. Wiring `UNUserNotificationCenter` is business logic and is NOT part of this task.
2. **First run, one line** in the dropdown: "Keep my icon visible: Settings > Menu Bar." (`hint.firstRun`),
   dismissible.
3. When the dropdown is opened from the overflow menu, the same row slot carries `hint.overflow`.
4. HIG also suggests a Dock menu as an always-available fallback. Out of scope here; recommended as a follow-up.
