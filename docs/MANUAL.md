# Manual

Everything Hidden Bar can do, including the parts with no UI.

## Basics

- **Left-click the arrow** (`<` / `>`): expand or collapse the hidden section.
- **Right-click the arrow** or **left-click the separator** (`|`): context menu
  (Preferences, Toggle Auto Collapse, Quit).
- **⌘-drag** icons in the menu bar to move them across the separator: icons to
  the separator's left are hidden when collapsed.
- **Option-click the arrow**: show/hide the separators and the always-hidden
  area without expanding.

## Preferences window

| Setting | What it does |
|---|---|
| Start Hidden Bar when I log in | Login item via System Settings (macOS 13+ `SMAppService`); revocable in System Settings > General > Login Items |
| Show preferences on launch | Open this window at app start |
| Auto collapse | Re-hide automatically after the chosen delay |
| Global shortcut | System-wide expand/collapse hotkey (F-keys display as F18, not Fn18) |
| Enable always hidden section | A second zone whose icons stay hidden even when expanded; revealed by option-clicking the arrow |
| Use full menu bar on expanding | App becomes briefly "regular" while expanded (helps on tight menubars) |

> **Always-hidden section, current behavior:** items in the always-hidden zone
> are reliably pushed off-screen only when "hide separators" is also on
> (option-click the arrow). With the separators visible, always-hidden items can
> still appear after expanding. This coupling is a known limitation being
> reworked alongside the menu-bar redesign; for now, option-click to hide the
> separators if always-hidden items keep showing. Avoid placing critical icons in
> the always-hidden zone until the rework lands, since a stuck off-screen item has
> to be recovered by ⌘-dragging it back (macOS persists its position per app).

## Behaviors you get for free

- **It won't collapse mid-use**: while your pointer is anywhere in the menu bar,
  the auto-collapse countdown defers and restarts; it resumes when you leave.
- **Self-repair**: if the arrow or separator was ⌘-dragged off the bar (which
  used to make the app unreachable forever), they come back on next launch.
- **Display changes**: plugging in or removing monitors re-sizes the hidden zone
  for the widest attached screen automatically.

## Hidden settings (Terminal)

All via `defaults`; quit and relaunch the app after changing them.

```sh
# expand by hovering the menu bar for ~0.5s (off by default)
defaults write com.dwarvesv.minimalbar hoverToExpand -bool true

# auto-collapse delay in seconds (the UI offers a fixed list; any value works)
defaults write com.dwarvesv.minimalbar numberOfSecondForAutoHide -float 5

# force the app language regardless of system order (issue #287)
defaults write com.dwarvesv.minimalbar AppleLanguages '(en)'

# macOS 27 with displays of different widths: hide on the narrowest display and
# accept that wider ones show their icons shifted sideways (off by default, see
# "Several displays on macOS 27" below)
defaults write com.dwarvesv.minimalbar hideWithMixedDisplays -bool true
```

To undo any of them: `defaults delete com.dwarvesv.minimalbar <key>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons I want visible got hidden after an update | ⌘-drag them to the right of the separator |
| Login item missing after denying it once | System Settings > General > Login Items: re-enable Hidden Bar, then toggle the pref off/on |
| A ghost "LauncherApplication" login item from old versions | Launch the current version once; it deauthorizes the legacy item automatically |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| Nothing hides while a second, wider display is attached (macOS 27) | Expected, see "Several displays on macOS 27" below |
| A new or just-updated app's icon shows up already hidden | Expected, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator once |

### Several displays on macOS 27

macOS 27 refuses any separator wider than half the display it is drawn on, and a
wide display needs a *longer* separator than a narrow one to push icons away —
so on a large external monitor no separator is ever long enough to hide anything.
Because one separator length is shared by every menu bar, a mixed-width setup can
have one or the other, never both:

- **Default:** nothing is hidden while displays of different widths are attached,
  and every menu bar is left exactly as it was.
- **`hideWithMixedDisplays`:** hides on the narrowest display, at the cost of
  wider displays showing their icons shifted sideways with a gap while collapsed.

Either way, hiding returns to normal as soon as only one display (or displays of
equal width) is connected — no relaunch needed.

### Why new icons start hidden

Hidden Bar hides icons by widening its separator so everything to the *left* of
it slides off-screen. macOS always inserts a brand-new menu-bar icon at the
far-left slot, which is inside that hidden zone, so a freshly launched or updated
app can appear "swallowed". This is macOS positioning behavior, not Hidden Bar
moving your icon: there is no way for one app to reposition another app's menu-bar
icon. The one-time fix is to ⌘-drag the icon to the right of the separator;
macOS remembers that placement per app. A built-in way to keep chosen icons
pinned is being explored as part of the larger menu-bar redesign.

## Requirements

macOS 13 Ventura or later. Pre-Ventura (10.13 - 12.x): use
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10), the last release
on the old autostart mechanism.
