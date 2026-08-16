# Changelog

## v1.11 (unreleased)

Requires macOS 13 Ventura or later. (Pre-Ventura users: stay on
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10).)

### Added
- Opt-in hover-to-expand: set `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true` to expand the bar when the pointer dwells in the menu bar.
- Right-clicking the expand/collapse arrow now opens the same context menu as the separator, so Preferences is reachable from the control you already click.

### Fixed
- Multi-display: the collapse width is now sized for the widest attached screen, so icons no longer leak on wider external monitors; the width re-applies on display hot-plug.
- Auto-collapse no longer fires while you are interacting with the menu bar (the timer defers and re-arms while the pointer is in the bar).
- The Preferences window no longer closes when auto-collapse fires with "use full menu bar on expanding" enabled (#170, #66, #151).
- Status items that were dragged off the bar are restored at launch instead of leaving the app unreachable.
- Fixed constraint and observer leaks in the tutorial view rebuild.
- Tutorial strings and F-key shortcut labels now render correctly (no more private-use glyphs).

### Changed
- Start-at-login now uses `SMAppService` (macOS 13+); the legacy launcher helper was removed and any leftover login item is deauthorized automatically on first launch.
- Pinned the HotKey dependency to an exact version and removed an unused file-access entitlement and dead code (no behavior change).

### Fixed (continued)
- macOS 27: hiding works again (#360). The re-architected menu bar discards a status item whose length reaches half the display width instead of clamping it, so the separator — inflated to twice the screen width — was dropped and hid nothing. The collapse length is now sized to just under half the width of the narrowest attached display; the displaced icons move into macOS 27's native overflow menu. macOS 26 and earlier keep the previous behavior. The separator's "|" glyph is also hidden while collapsed on 27, where its span is on-screen rather than off it (the stray line reported mid-menu-bar).

### Known / in progress
- macOS 27 on very wide displays (beyond roughly 2800pt): hiding is not possible there — the icons are further from the overflow boundary than macOS 27 lets a single status item stretch. When displays of different widths are attached, the app therefore collapses nothing by default and leaves every menu bar untouched; `defaults write com.dwarvesv.minimalbar hideWithMixedDisplays -bool true` opts into hiding on the narrowest display instead, at the cost of wider displays showing their icons shifted sideways. Hiding resumes automatically with a single display, or displays of equal width. Fully fixing this needs the managed-overflow redesign (#366).
- New menu-bar icons can appear in the hidden zone because macOS inserts them at the far left; ⌘-drag them to the right of the separator (see the manual). A built-in pin is part of the planned redesign.
