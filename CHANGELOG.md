# Changelog

## v1.13.0 (unreleased)

Four ways to reach and control your icons, all opt-in: with every default left alone, 1.13.0 behaves exactly like 1.12.0. None needs a new permission: they use the Accessibility permission hiding already asks for, plus the pointer and scroll monitors hover-to-expand already uses. They never read your screen.

### Added
- **Reveal without aiming** (off by default; Settings › General › "Also show hidden icons when you"). Show the hidden icons without hitting the small arrow: "Scroll down on the menu bar" (scroll up hides them again), "Click empty space in the menu bar" and "Shake the pointer at the top of the screen". Clicking anywhere off the menu bar hides what a gesture showed. Scroll and shake also work in the App Store build; the empty-click row is direct build only, because it needs Accessibility to tell empty space from an icon ([#493](https://github.com/dwarvesf/hidden/pull/493)).
- **Find a hidden icon** (off until you record a shortcut; Settings › General › "Find a hidden icon"; direct build on macOS 27). The shortcut opens a search under the arrow that lists your running hidden apps. Type a few letters of a name or bundle id, then press Return to open that app's own menu without expanding the bar; the app hides again when the menu closes. Command-Return moves the app to visible, Option-Return to always hidden. Once a shortcut is set, the arrow's right-click menu also offers "Find a Hidden Icon..." ([#505](https://github.com/dwarvesf/hidden/pull/505)).
- **Ask about new menu bar apps** (default Show It, which is the 1.12 behavior; Settings › Icons › "When an app adds a new icon": Ask Me, Show It or Hide It; direct build on macOS 27, only with Pinned sections on). With Ask Me, a new app stays visible, the arrow gets a dot, and clicking the arrow asks once, from a popover, whether to show it, hide it or always hide it. Hidden Bar remembers the answer, also after a restart. Apps still waiting for an answer sit first in the Icons list with a NEW tag, and an unanswered question lapses after 24 hours ([#503](https://github.com/dwarvesf/hidden/pull/503)).
- **Presentation mode** (off by default; Settings › General › "Presentation mode"; direct build on macOS 27). While it is on, every third-party app icon is hidden (macOS's own items stay), and the apps you list as "Sensitive apps" stay hidden even if you click the arrow. Start it with your own shortcut (Settings › General › Presentation mode › "Keyboard shortcut") or the arrow's right-click menu, "Start Presentation Mode". A "Presenting" capsule shows how many apps are hidden and stops it; it names no app, since the screen may be shared. The first time it starts, a short tip under the capsule says what is hidden and how to stop it, once, and Settings has a "How it works" note. "Turn on automatically" starts it when a display is mirrored. It follows the "Show all icons when the microphone or camera turns on" switch: with the switch on, a microphone or camera that turns on while presenting pauses hiding once, so macOS can show the capsule that names the app using it, and nothing is hidden meanwhile, sensitive apps included; "Hide again" or any collapse resumes, and hiding resumes by itself when capture ends. With the switch off it never pauses, and a capture already on when presenting starts does not pause it. Reveal gestures and the new-app question wait while presenting, and the find-a-hidden-icon search leaves your sensitive apps out of its list ([#504](https://github.com/dwarvesf/hidden/pull/504), [#509](https://github.com/dwarvesf/hidden/pull/509)).

### Changed
- Settings › General now scrolls when it is taller than the window (the window stops at 720 pt), so the new rows never push it off a small screen ([#504](https://github.com/dwarvesf/hidden/pull/504)).
- The shortcut recorder is one shared control for every shortcut. A bare letter is refused and the old shortcut stays; letting go of every modifier, or pressing Escape, cancels without clearing the stored shortcut; a shortcut that is also used by another Hidden Bar shortcut is refused, with a small orange triangle naming the other ([#497](https://github.com/dwarvesf/hidden/pull/497)).
- The hover setting moved into the new "Also show hidden icons when you" group, with the same stored value ([#493](https://github.com/dwarvesf/hidden/pull/493)).

### Fixed
- Settings › Icons and General keep their cards on the same left and right edges when macOS shows scroll bars all the time: the list's scroller sits inside its card, and nothing is clipped at the right.
- Settings › Icons: the row of an app that is not running (with Remove) is as tall as the other rows, and "Ignore drags" now says in its tooltip and in the note above the list what it does.
- Right-clicking the arrow is hardened: only a plain left click toggles the bar or opens the new-app question, and a popover hanging from the arrow closes before the context menu opens.

### Notes
- Direct build only: palette, arrivals and presentation need macOS 27 and Accessibility. The App Store build keeps scroll and shake reveal; it has no empty-click row.
- Not in this release: an automatic slideshow trigger for presentation mode (it needs a live Keynote or PowerPoint check first) and a Shortcuts action. See the backlog.


## v1.12.0 (2026-11-15)

A redesigned Settings window, pinned sections (beta) on macOS 27, and the fixes from the unreleased 1.11.3 hotfix, which ships as part of this release.

### Fixed
- An app that keeps the microphone open (Wispr Flow, Krisp, Discord, dictation tools) no longer stops the bar from hiding. This was a 1.11.2 regression from the recording-indicator fix (#432). Now the bar expands once when the microphone or a camera turns on, and you can collapse it again as usual. A Settings checkbox, "Show all icons when the microphone or camera turns on", turns that off ([#475](https://github.com/dwarvesf/hidden/pull/475)).
- macOS 27, direct build: when Hidden Bar runs from outside /Applications (Downloads or ~/Applications, for example), it no longer hides its own arrow. It hides nothing until you move it to /Applications ([#475](https://github.com/dwarvesf/hidden/pull/475), [#479](https://github.com/dwarvesf/hidden/pull/479)).
- Switching from the App Store build has no dead ends: if the App Store copy is running, Hidden Bar asks to quit it and switch instead of quitting silently; the offer to move to /Applications shows even if you keep the App Store copy; and when /Applications cannot take it, an alert says what to do ([#479](https://github.com/dwarvesf/hidden/pull/479)).

### Added
- Direct build: switching from the App Store build offers to import your settings, which used to reset ([#464](https://github.com/dwarvesf/hidden/issues/464)), then to move the App Store copy to the Trash, and to move Hidden Bar to /Applications if it runs from somewhere else. Each offer shows once and does nothing until you click ([#474](https://github.com/dwarvesf/hidden/pull/474)).
- App Store build on macOS 27: the notice now shows the `brew install --cask hiddenbar` command ([#474](https://github.com/dwarvesf/hidden/pull/474)).

### Changed
- Shift-click the arrow to expand with the full menu bar for that one expansion, without turning on "Use the full menu bar on expanding" (#482).
- Redesigned Settings window: tabs for General, Appearance, Advanced and About, grouped rows with plain labels, and a status card that says whether Hidden Bar is working and what to do if not. Every setting keeps its stored value ([#481](https://github.com/dwarvesf/hidden/pull/481)).
- The menu bar preview draws the arrow as the edge on macOS 27 (direct build) and the "|" separator elsewhere; the overlapping guide arrow is gone.
- "Automatically hide icon after" and its delay are one "Hide icons again" popup with a Never choice.
- About shows which build you run, links the changelog, and (direct build) has Check for Updates. X replaces Twitter.
- The app icon follows the macOS icon margin and shadow, so it no longer looks oversized in the Dock ([#198](https://github.com/dwarvesf/hidden/issues/198); [#485](https://github.com/dwarvesf/hidden/pull/485)).
- On macOS 27, the notch settings row and the "Show Notch Items" menu item are gone: macOS 27 never puts icons behind the notch, it moves them into its own « button.

### macOS 27 (direct build)
- On a full menu bar, macOS 27 can move the Hidden Bar arrow into its own « button. After you collapse, Hidden Bar now checks for this and, once, says how to reach the arrow: click «, or use the hotkey.
- Pinned sections (beta, on by default): each app keeps the section you gave it when it restarts, instead of falling into the hidden section where macOS puts a relaunched icon. Apps seen for the first time start visible. Settings › Icons lists your menu-bar apps with a section choice per app and "Reset all to visible" (#366, #334, #107; [#473](https://github.com/dwarvesf/hidden/pull/473)).
- Apps set to always hidden stay hidden when the bar expands (#224).
- Menu-bar apps without a Dock icon are now noticed when they start, so they get their section back too.
- Icons has a per-app "Ignore drags" option for apps that recreate their icon without restarting (SwiftBar, BitBar), so their section stays put ([#487](https://github.com/dwarvesf/hidden/pull/487)).
- The Icons pane opens fast, shows real names and icons for system services and app helpers, and tells same-named apps apart.
- Icons marks apps that are not running with "Not running" and lets you remove them from the list. An app you remove comes back as a new app the next time it runs.

### macOS 26 and earlier
- The always-hidden section stays hidden when the bar expands; Option-click shows it until the next collapse (#224).
- "Show Everything" in the arrow's right-click menu shows the always-hidden section to recover icons lost there (#242).

## v1.11.2 (2026-11-15)

Mostly macOS 27 fixes for the direct download build, plus auto-update. Thanks to everyone whose pull requests went into this release: @lllyt8, @bhaveshnigam, @Shigo-45, @kwvg, @renovys, @goosefraba, @DanishjeetSingh, @khallmark, @richarddemann, @antib0t, @Metekilic, @voltangle and @gmcinalli.

### macOS 27 (direct build)
- Clicking the clock while the bar is collapsed opens Notification Center again: the bar expands, the panel opens, and the bar collapses once the panel closes. A bar you expanded yourself is left as it is (#410, #421, #435, #454; #467 by @lllyt8, building on #453 by @bhaveshnigam).
- A clock click within about a second of collapsing no longer leaves the bar stuck until you quit.
- Icons you keep right of the arrow stay visible: third-party items that macOS 27 could not keep visible (Raycast, iStat Menus, apps without a bundle identifier) and slow-to-answer apps are no longer hidden (#443, #429, #465, #446).
- macOS's own extras that macOS 27 hides anyway (Focus, Now Playing, Siri, Stage Manager) are listed in Preferences, with an opt-in "pause hiding" that keeps them visible while they sit right of the arrow (#444, #436, #442, #440, #413, #412, #411, #414).
- The microphone and camera indicators no longer stay hidden: while any app uses the microphone or a camera, the whole bar shows, then hides again when that stops (#432, #437; based on #438 by @khallmark).
- The always-hidden section works: Option-click shows it, and its separator hides with its section (#458, #464; #445 by @Shigo-45).
- The Time Machine extra and other SystemUIServer items follow the arrow like any other icon (#424; #425 by @renovys).
- An app that starts while the bar is collapsed returns to its last known section; an app never seen before shows.
- Preferences explains a missing Accessibility permission with an "Open Settings" button, and an arrow click that cannot hide opens Preferences (#433 by @richarddemann).
- Faster start: menu-bar apps are scanned concurrently, with one retry for slow apps (#450 by @goosefraba).
- The always-hidden tutorial says to drag the translucent bar left of the arrow, since macOS 27 has no "|" separator. This text is English in every language for now.

### Added
- Direct build only: Sparkle auto-update. Context menu "Check for Updates...", plus an "Automatically check for updates" checkbox in Preferences (#220, #197). Updates are EdDSA-signed and served from the GitHub release's `appcast.xml`. The App Store build is unchanged and contains no Sparkle.
- Arrow style picker in Preferences: arrow, chevron, dot or line (#310).
- Optional near-invisible collapsed arrow, off by default (#173).
- Preferences checkbox for hover-to-expand (it was `defaults write` only). It takes effect at once, without relaunching.
- Turkish, Ukrainian and Italian translations (#101; #320 by @Metekilic, #226 by @voltangle, #196 by @gmcinalli).
- App Store build on macOS 27: a one-time notice that the sandboxed build cannot hide icons there, with a link to the direct download (#448, #430, #393).
- README lists the official download sources (#462).

### Fixed
- Multi-display: sections are measured on the same display's menu bar as the arrow, so icons no longer vanish when the arrow sits on another display, and items macOS drops from a narrow, overflowing menu bar keep their last section (#390).
- macOS 26 and earlier: the launch collapse waits for macOS to place new items, so the arrow can no longer hide itself (#336, #381 by @antib0t).
- No Dock icon when "use full menu bar on expanding" is off (#423, #463; #460 by @kwvg).
- Auto-collapse waits while a menu-bar popup is open, then collapses after it closes (#319).
- Upgrading from the App Store build: the legacy login-item cleanup retries on the next launch if it fails, instead of being marked done (#456).
- Lower memory use: auto-hide checks no longer create the Preferences window (#447 by @DanishjeetSingh).
- Preferences: no stray "Custom View" label, and the tab switcher is centered (#460 by @kwvg).
- MANUAL explains why the date can be missing from the clock while the bar is collapsed on macOS 26 and earlier (#207).

## v1.11.1 (2026-09-18)

### Fixed
- macOS 27: the Preferences window showed a "Custom View" placeholder instead of the General/About tabs, and the label overlapped the window once clicked (#406).

## v1.11 (2026-09-18)

Requires macOS 13 Ventura or later. (Pre-Ventura users: stay on
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10).)

### Added
- Opt-in hover-to-expand: set `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true` to expand the bar when the pointer dwells in the menu bar.
- Right-clicking the expand/collapse arrow now opens the same context menu as the separator, so Preferences is reachable from the control you already click.

### Fixed
- macOS 27 (direct download build): hiding works again (#360) using macOS 27's native menu-bar visibility instead of widening the separator, which macOS 27 ejects from the bar. The arrow is the boundary: icons ⌘-dragged to its left hide when collapsed. Needs the Accessibility permission, and Hidden Bar must run from /Applications. Hiding is per app, and macOS's own items always stay visible. The App Store build is unchanged for now.
- Enabling the always-hidden section at runtime no longer creates an invisible (0pt) separator.
- Multi-display: the collapse width is now sized for the widest attached screen, so icons no longer leak on wider external monitors; the width re-applies on display hot-plug.
- Auto-collapse no longer fires while you are interacting with the menu bar (the timer defers and re-arms while the pointer is in the bar).
- The Preferences window no longer closes when auto-collapse fires with "use full menu bar on expanding" enabled (#170, #66, #151).
- Status items that were dragged off the bar are restored at launch instead of leaving the app unreachable.
- Fixed constraint and observer leaks in the tutorial view rebuild.
- Tutorial strings and F-key shortcut labels now render correctly (no more private-use glyphs).

### Changed
- Start-at-login now uses `SMAppService` (macOS 13+); the legacy launcher helper was removed and any leftover login item is deauthorized automatically on first launch.
- Pinned the HotKey dependency to an exact version and removed an unused file-access entitlement and dead code (no behavior change).

### Known / in progress
- macOS 27, App Store build: hiding still does not work (#360). Native hiding needs Accessibility reads that the App Sandbox blocks; an App Store approach is tracked separately.
- New menu-bar icons can appear in the hidden zone because macOS inserts them at the far left; ⌘-drag them to the right of the separator (see the manual). A built-in pin is part of the planned redesign.
