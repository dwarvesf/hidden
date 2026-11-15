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

### macOS 27, direct download build

The direct (non-App Store) build hides icons natively on macOS 27, and the
**arrow itself is the boundary**: there is no `|` separator. ⌘-drag icons to
the arrow's left to hide them when collapsed, to its right to keep them
visible. The always-hidden separator still appears (while expanded) when that
section is enabled.

- Needs **Accessibility** permission (System Settings › Privacy & Security ›
  Accessibility) to see where your icons are. Without it the bar stays
  expanded.
- Hiding is per app: an app with several icons hides or shows them together.
  If any of its icons is right of the arrow, all of them stay visible; to hide
  the app, ⌘-drag every one of its icons left of the arrow.
- An app that starts while the bar is collapsed (a login item that starts
  after Hidden Bar, an app you relaunch) shows in the section it was in last
  time, or stays visible if Hidden Bar has never seen it. The next collapse
  places it by where macOS put its icon, so a brand-new icon that macOS puts
  on the far left is hidden from then on; ⌘-drag it right of the arrow once.
- **Pinned sections (beta, on by default):** Hidden Bar keeps a section per app
  and no longer reads it from where macOS put the icon after the app started.
  An app seen for the first time starts visible. A ⌘-drag still moves an app
  between sections, except in the moment right after it relaunched.
  Settings › Menu Bar Apps lists every app with a Visible / Hidden /
  Always hidden choice, which applies at once, and "Reset all to visible". An
  app set to always hidden stays hidden when the bar expands; Option-click the
  arrow to show it until the next collapse. Turn the beta off in Settings › Advanced to
  get the position-based behavior above; it takes effect at the next collapse.
- An icon whose app has no bundle identifier (a script run by an interpreter,
  some helpers) cannot be kept visible on macOS 27. Preferences offers to show
  all icons while one of them sits right of the arrow.
- macOS's own items (clock, Wi-Fi, Sound, Control Center) always stay visible.
- Run Hidden Bar from `/Applications`; macOS only recognizes that copy as
  Hidden Bar, and a copy elsewhere hides its own arrow.
- Native hiding blocks Notification Center, so clicking the clock while the bar is collapsed expands it, opens Notification Center, and collapses it again when the panel closes, unless you expand or collapse it yourself meanwhile.
- Native hiding also hides the menu-bar capsule that names the app using the microphone or camera (the orange or green indicator); the dot in the screen corner still shows. So while any app uses the microphone or a camera, Hidden Bar stops hiding and shows the whole bar, and hides again when that stops. The arrow keeps its collapsed look meanwhile. Screen recording is not covered: macOS offers no public way to detect it.

## Settings window

Tabs in a centered control at the top (Cmd+1 to Cmd+5). A status card at the top of General says whether Hidden Bar is working, and if not, what to do (grant Accessibility, move to Applications, or that the App Store build cannot hide on macOS 27). The "Your menu bar" preview draws the edge the running engine uses: the arrow on the macOS 27 direct build, the "|" separator otherwise.

| Pane | Setting | Stored as |
|---|---|---|
| General | Open Hidden Bar at login: login item via System Settings (macOS 13+ `SMAppService`) | `isAutoStart` |
| General | Hide icons again: Never, or after 5 s to 1 min | `isAutoHide`, `numberOfSecondForAutoHide` |
| General | Always-hidden section: a second zone revealed by Option-clicking the arrow | `alwaysHiddenSectionEnabled` |
| General | Keyboard shortcut: system-wide expand/collapse (F-keys display as F18, not Fn18) | `globalKey` |
| General | Show icons when the pointer rests on the menu bar | `hoverToExpand` |
| General (macOS 27, direct) | Show all icons when the microphone or camera turns on | `showWholeBarWhenCaptureStarts` |
| Appearance | Arrow style tiles | `arrowStyle` |
| Appearance | Fade the arrow when icons are hidden | `stealthExpandIconEnabled` |
| Advanced | Show this window when Hidden Bar opens | `isShowPreferences` |
| Advanced | Make room for icons while they are shown: the app turns "regular" while expanded, so the frontmost app's menus give way | `useFullStatusBarOnExpandEnabled` |
| Advanced (notch Macs) | Reach icons behind the camera notch | `notchOverflowEnabled` |
| Advanced (macOS 27, direct) | Show all icons while macOS hides one right of the arrow | `pauseHidingForUnkeepableItems` |
| About (direct) | Check for updates automatically, Check for Updates… | Sparkle's `SUEnableAutomaticChecks` |

A Menu Bar Apps tab joins the others on the macOS 27 direct build once the pinned sections beta registers it (`MenuBarAppsPane`).

Debug builds can draw every pane and status state, light and dark, to PNGs without showing a window: run the built binary with `-settingsSnapshotDir <dir>`; it quits when done and writes no preference.

> **Always-hidden section:** every collapse hides the always-hidden section
> again, so it stays hidden when the bar expands. Option-click the arrow to show
> it (and ⌘-drag icons out of it) until the next collapse. To get lost icons
> back on macOS 26 and earlier, right-click the arrow and choose **Show
> Everything**. An icon macOS persisted off-screen still has to be ⌘-dragged
> back (macOS keeps its position per app).

## Behaviors you get for free

- **It won't collapse mid-use**: while your pointer is anywhere in the menu bar,
  the auto-collapse countdown defers and restarts; it resumes when you leave.
- **Self-repair**: if the arrow or separator was ⌘-dragged off the bar (which
  used to make the app unreachable forever), they come back on next launch.
- **Display changes**: plugging in or removing monitors re-sizes the hidden zone
  for the widest attached screen automatically.

## Hover to expand

Settings > General > "Show icons when the pointer rests on the menu bar"
expands the collapsed bar after the pointer rests in the menu bar for about half a
second. Off by default; it takes effect at once, no relaunch.

## Hidden settings (Terminal)

All via `defaults`; quit and relaunch the app after changing them.

```sh
# auto-collapse delay in seconds (the UI offers a fixed list; any value works)
defaults write com.dwarvesv.minimalbar numberOfSecondForAutoHide -float 5

# force the app language regardless of system order (issue #287)
defaults write com.dwarvesv.minimalbar AppleLanguages '(en)'
```

To undo any of them: `defaults delete com.dwarvesv.minimalbar <key>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons I want visible got hidden after an update | ⌘-drag them to the right of the separator |
| Login item missing after denying it once | System Settings > General > Login Items: re-enable Hidden Bar, then toggle the pref off/on |
| A ghost "LauncherApplication" login item from old versions | Launch the current version once; it deauthorizes the legacy item automatically |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| Nothing hides on a macOS 27 beta | Known (issue #360); the menu bar re-architecture broke the hiding mechanism, fix under investigation |
| A new or just-updated app's icon shows up already hidden | Expected, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator once |
| Date disappears from the clock when collapsed (macOS 26 and earlier) | The collapsed bar takes the space macOS measures; set System Settings > Control Center > Clock > Show date to Always. macOS 27 with the direct build is not affected |

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
