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
- **Right-click the arrow to show always-hidden icons** (Settings › Advanced ›
  "Right-click on the arrow": Show always-hidden icons): right-click then does
  what Option-click does, as it did before 1.11, so no keyboard is needed.
  The menu moves to **Option-right-click**. The default stays Show menu.
- **Shift-click the arrow**: expand and use the full menu bar for this
  expansion only, like "Use the full menu bar on expanding" but without
  changing the setting. It reverts when the bar collapses.

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
  Settings › Icons lists every app with a Visible / Hidden /
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
| General (macOS 27, direct) | Find a hidden icon: shortcut that opens a search under the arrow; unset means off | `findHiddenIconShortcut` |
| General | Also show hidden icons when you: Rest the pointer on the menu bar | `hoverToExpand` |
| General | Also show hidden icons when you: Scroll down on the menu bar (scroll up hides again) | `revealOnScrollEnabled` |
| General (direct build) | Also show hidden icons when you: Click empty space in the menu bar | `revealOnEmptyClickEnabled` |
| General | Also show hidden icons when you: Shake the pointer at the top of the screen | `revealOnShakeEnabled` |
| General (macOS 27, direct) | Show all icons when the microphone or camera turns on | `showWholeBarWhenCaptureStarts` |
| General (macOS 27, direct) | Presentation mode: Turn on automatically, when a display is mirrored | `presentationAutoMirrorEnabled` |
| General (macOS 27, direct) | Presentation mode: Sensitive apps, an Edit picker; they stay hidden while presenting even when you click the arrow | `presentationSensitiveApps` |
| General (macOS 27, direct) | Presentation mode: Keyboard shortcut that starts and stops it; unset means no shortcut | `presentationShortcut` |
| Icons (macOS 27, direct) | When an app adds a new icon: Ask Me, Show It (default) or Hide It | `newAppDefaultSection` |
| Appearance | Arrow style tiles | `arrowStyle` |
| Appearance | Fade the arrow when icons are hidden | `stealthExpandIconEnabled` |
| Advanced | Show this window when Hidden Bar opens | `isShowPreferences` |
| Advanced | Make room for icons while they are shown: the app turns "regular" while expanded, so the frontmost app's menus give way | `useFullStatusBarOnExpandEnabled` |
| Advanced | Right-click on the arrow: Show menu (default) or Show always-hidden icons, which moves the menu to Option-right-click | `rightClickAction` (`showMenu`, `showAlwaysHidden`) |
| Advanced (notch Macs) | Reach icons behind the camera notch | `notchOverflowEnabled` |
| Advanced (macOS 27, direct) | Pause hiding while macOS shows Now Playing, Focus and similar items: macOS 27 hides these items whenever an app hides icons, so while one shows, Hidden Bar hides nothing | `pauseHidingForUnkeepableItems` |
| About (direct) | Check for updates automatically, Check for Updates… | Sparkle's `SUEnableAutomaticChecks` |

The General pane scrolls when it is taller than the window (the window stops at 720 pt).

An Icons tab joins the others on the macOS 27 direct build once the pinned sections beta registers it (`MenuBarAppsPane`).

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

## Reveal without aiming

Settings > General > "Also show hidden icons when you" groups every way to show the hidden icons that does not need the arrow. All are off by default, take effect at once, and use only global mouse and scroll monitors, so none asks for a new permission.

- **Rest the pointer on the menu bar** (`hoverToExpand`): expands the collapsed bar after the pointer rests in the menu bar for about half a second.
- **Scroll down on the menu bar** (`revealOnScrollEnabled`): a two-finger or wheel scroll down on the menu bar of any screen shows the icons; scrolling up hides them. A scroll over another app's icon is left to that app.
- **Click empty space in the menu bar** (`revealOnEmptyClickEnabled`, direct build only): a click on bare menu bar shows the icons. A click on an icon or a menu title keeps its normal meaning. It reads what is under the pointer through Accessibility, which the sandboxed App Store build cannot use, so that row is not there; without the Accessibility permission the click does nothing.
- **Shake the pointer at the top of the screen** (`revealOnShakeEnabled`): three quick side-to-side reversals within 0.6 seconds, each at least 12 points wide, inside the menu bar. Window drags do not count; there is no menu bar to shake in a full-screen app until it slides down.

Clicking anywhere off the menu bar hides the icons that a gesture revealed (the same auto-collapse path waits while Settings or a popup is open); they also hide after the "Hide icons again" delay. A gesture does nothing while the bar is already expanded or Hidden Bar's own menu is open. Thresholds live in `RevealTuning` (`RevealGestures.swift`). Debug builds count each gesture (`revealTriggerCounts` in the `dump-state` output) and accept `reveal-sim scroll|scroll-up|click|shake`.

## Find a hidden icon

Direct build on macOS 27 only. Record a shortcut in Settings > General > "Find a hidden icon" (under Keyboard shortcut). It is unset by default, so the feature is off; once a shortcut is set, the arrow's right-click menu also offers "Find a Hidden Icon...".

- The shortcut opens a small panel under the arrow, on the display with the pointer. It lists the hidden and always-hidden apps that are running.
- Type part of a name or bundle id. Matches at the start of the name come first; letters in order and the bundle id also match. The arrow keys move the selection.
- **Return** opens that app's own menu without expanding the bar, then hides it again when the menu closes. An app that opens a panel instead of a menu hides again when it loses focus, after 15 seconds at most. **Command-Return** moves the app to the visible section, **Option-Return** to always hidden. **Escape** or a click elsewhere closes the panel.
- It uses the Accessibility permission hiding already needs and never reads the screen. Focus, Siri and Now Playing cannot be opened from here: macOS keeps them out of Accessibility while icons are hidden.
- Debug builds accept `palette-open [query]`, `palette-query <text>`, `palette-select <bundle id>`, `palette-activate open|keep|hide` and `palette-close`.

## New menu bar apps

Direct build on macOS 27 only, and only with Pinned sections on. Settings > Icons > "When an app adds a new icon" decides what happens the first time Hidden Bar sees an app:

- **Show It** (default): the app stays visible, which is how 1.12 behaves. Nothing is asked.
- **Hide It**: the app is placed in the hidden section at once. Nothing is asked.
- **Ask Me**: the app stays visible, the arrow gets a dot, and clicking the arrow asks once ("New in your menu bar": Show, Hide, or Always hide under the ellipsis). The answer is remembered, also after a restart. Closing the popover without an answer keeps the dot and the question. Waiting apps sit first in Settings > Icons with a NEW tag. A question nobody answers lapses after 24 hours and the Settings default applies; for Ask Me that leaves the app shown. An app is asked at most once.

Apps Hidden Bar already knew when you upgraded are never announced. With Pinned sections off nothing is placed or asked, and the popup is disabled. Debug builds accept `arrivals-inject <bundle id>`, `arrivals-answer <bundle id>=show|hide|always-hide` and `arrivals-prompt`.

## Presentation mode

Direct build on macOS 27 only. While it is on, every third-party app icon is hidden (macOS's own items stay), and the apps in Settings > General > Presentation mode > "Sensitive apps" stay hidden even when you click the arrow. Presentation mode is a hide, not a quit: Hidden Bar never closes an app for you.

- **Start and stop:** the shortcut in Settings > General > Presentation mode > "Keyboard shortcut" (unset by default), the arrow's right-click menu ("Start Presentation Mode" and "Stop Presentation Mode"), or the "Presenting" capsule that shows while it is on. Its panel gives counts of what is hidden and why, plus "Stop Presenting", and names no app because the screen may be shared. After you click the arrow, a note says how many apps stay hidden, also without names. A manual start stays on until you stop it and does not survive a quit or relaunch.
- **First-start tip:** the first time presentation mode starts and hides your icons, a small note opens under the "Presenting" capsule. It says in three short lines that every app icon is hidden (macOS's own items stay), that clicking "Presenting" shows how many apps are hidden and lets you stop, and what a camera or microphone does (it pauses hiding once, or does not, depending on the switch below). It names no app, closes with "Got it", and shows once, never again, including after a relaunch. It does not open over the capsule's own panel, and it closes when you stop. The same facts, in full, are under "How it works" in Settings > General > Presentation mode.
- **Turn on automatically:** off by default. When on, mirroring a display starts the mode and ends it when mirroring stops. If you stop it while mirroring continues it stays off until mirroring starts again.
- **Camera or microphone:** presentation mode follows the 1.12 switch "Show all icons when the microphone or camera turns on". With it on, a microphone or camera that turns on while presenting pauses hiding once, so macOS can show the capsule that names the app using it. The capsule reads Paused and offers "Hide again"; nothing is hidden while paused, sensitive apps included. "Hide again" or any collapse resumes, and hiding resumes by itself 2.5 seconds after the microphone and camera are off. With the switch off it never pauses. A microphone or camera already on when presenting starts does not pause it. The screen-sharing indicator cannot be paused for: share one window, not the whole screen.
- **Other features while presenting:** reveal gestures do nothing, the new-app question waits (the dot stays on the arrow), and the find-a-hidden-icon search leaves your sensitive apps out of its list.
- A clock click does nothing while presenting. If macOS refuses the request, every icon shows and the capsule says "Couldn't hide".
- Debug builds accept `present on|off`.

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
| The old "LauncherApplication" login item from a version before 1.11 (System Settings > General > Login Items & Extensions lists it inside "Hidden Bar" under Allow in the Background; a "Hidden Bar" row there is normal while launch at login is on) | With "Open Hidden Bar at login" on, launch the current version once; it removes the old item. Otherwise turn "Open Hidden Bar at login" off and on in Settings |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| A second arrow « appears when I expand (macOS 27 direct build) | The icons Hidden Bar reveals do not all fit in the menu bar (on a notched MacBook, right of the notch), so macOS puts some into its own « button. macOS offers no setting to turn this off. Click « to see them, and move icons you rarely use to the always-hidden section (Settings > Icons) to make room. Hidden Bar says this once, the first time an expand overflows |
| Nothing hides on a macOS 27 beta | Known (issue #360); the menu bar re-architecture broke the hiding mechanism, fix under investigation |
| A new or just-updated app's icon shows up already hidden | macOS 26 and earlier, or the App Store build: expected, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator once. macOS 27 direct build: new and relaunched apps start visible (Pinned sections, beta) |
| An app jumps into the hidden section by itself (BitBar, SwiftBar) | macOS 27 direct build: in Settings > Icons, tick "Ignore drags" on that app; it then keeps the section you picked |
| Date disappears from the clock when collapsed (macOS 26 and earlier) | The collapsed bar takes the space macOS measures; set System Settings > Control Center > Clock > Show date to Always. macOS 27 with the direct build is not affected |

### Why new icons start hidden

On macOS 26 and earlier, and in the App Store build, Hidden Bar hides icons by
widening its separator so everything to the *left* of it slides off-screen. macOS
always inserts a brand-new menu-bar icon at the far-left slot, which is inside that
hidden zone, so a freshly launched or updated app can appear "swallowed". This is
macOS positioning behavior, not Hidden Bar moving your icon: there is no way for
one app to reposition another app's menu-bar icon. The one-time fix is to ⌘-drag
the icon to the right of the separator; macOS remembers that placement per app.

On macOS 27 with the direct build, Hidden Bar keeps a section per app instead
(Pinned sections, beta, on by default; Settings > Icons). A new or
relaunched app starts visible and stays in the section you pick, also after it
restarts. A ⌘-drag across the arrow still moves it. An app that recreates its
icon without relaunching (BitBar, SwiftBar) can look like a drag; tick "Ignore
drags" on its row to keep it where you put it.

## Requirements

macOS 13 Ventura or later. Pre-Ventura (10.13 - 12.x): use
[v1.10](https://github.com/consolelabs/hidden/releases/tag/v1.10), the last release
on the old autostart mechanism.
