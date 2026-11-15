# SG-04 F1: Type-to-find palette

Model: sonnet
Effort: high
Done-mode: proof
**Branch:** feat/find-hidden-icon
Wall budget: 150 minutes

Read first: `../CONTRACT.md`; boards `Palette-Entry`, `Palette-Light`, `Palette-Dark`, `Palette-Open`, `Palette-Edge`, `Palette-Settings`; SG-01's `MenuBarItemCatalog`, `HotKeyRegistry`, `ShortcutRecorderRow`; `Engine/Native/MenuBarClock.swift` (`NotificationCenterSession`).

Done =
1. Settings, General tab, under the existing shortcut: row "Find a hidden icon" with a `ShortcutRecorderRow` bound to `findHiddenIconShortcut` (unset by default, so the feature is off). Direct build with the native engine only.
2. The shortcut opens a small panel under the arrow on the display with the pointer. It lists hidden and always-hidden apps from the catalog (app icon, name, bundle id, section), filters as you type (name or bundle id, case-insensitive, prefix matches first), arrow keys move the selection.
3. Return: allow that one app, AXPress its menu-bar item so its own menu opens, and re-hide when the menu closes, reusing the clock session pattern (session id, collapse only if Hidden Bar expanded). Cmd+Return moves the app to visible; Option+Return to always hidden (through `PinnedSectionEdits.set`). Escape or losing focus closes the panel.
4. Edge states from `Palette-Edge`: no match, catalog empty or stale, Accessibility missing, app quit since the last read, engine unavailable, item with no AX press.
5. The panel is our own window, so typing in it needs no key monitor and no new permission.
6. Ranking/filter logic and the reveal session state machine are pure types with tests in `HiddenBarTests` (or `HiddenTests` when direct-only); tests fail on develop.
7. Debug hooks `palette-open`, `palette-query <text>`, `palette-select <bundle>`; offscreen snapshots `direct-palette-<state>-<light|dark>.png` for every state on the Light, Dark, Open and Edge boards, from fixture data.
8. Pref-key tests and whitelist per CONTRACT section 3. `bash scripts/test.sh` green, CI green.

## Scope edges

- No Screen Recording, no item images: app icons only.
- No change to the existing expand/collapse shortcut.

## Touches

- hidden/Features/Palette/**
- hidden/Features/Preferences/PreferencesViewController.swift
- hidden/Features/Settings/SettingsSnapshot.swift
- hidden/Features/StatusBar/StatusBarController.swift
- hidden/Extensions/UserDefault+Extension.swift
- hidden/Common/Preferences.swift
- hidden/*.lproj/**
- HiddenTests/**
- HiddenBarTests/**
