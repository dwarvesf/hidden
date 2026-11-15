# Changelog

## Unreleased

### Changed
- Redesigned Settings window: tabs for General, Appearance, Advanced and About, grouped rows with plain labels, and a status card that says whether Hidden Bar is working and what to do if not. Every setting keeps its stored value.
- The menu bar preview draws the arrow as the edge on macOS 27 (direct build) and the "|" separator elsewhere; the overlapping guide arrow is gone.
- "Automatically hide icon after" and its delay are one "Hide icons again" popup with a Never choice.
- About shows which build you run, links the changelog, and (direct build) has Check for Updates. X replaces Twitter.

### macOS 27 (direct build)
- Pinned sections (beta, on by default): each app keeps the section you gave it when it restarts, instead of falling into the hidden section where macOS puts a relaunched icon. Apps seen for the first time start visible. Settings › Menu Bar Apps lists your menu-bar apps with a section choice per app and "Reset all to visible" (#366, #334, #107).
- Apps set to always hidden stay hidden when the bar expands (#224).
- Menu-bar apps without a Dock icon are now noticed when they start, so they get their section back too.

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
