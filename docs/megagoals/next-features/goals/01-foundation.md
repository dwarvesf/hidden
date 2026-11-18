# SG-01 Foundation: shortcut recorder, item catalog, hb-cmd

Model: sonnet
Effort: high
Design: bearing
**Branch:** feat/next-features-foundation
Wall budget: 120 minutes

Read first: `../CONTRACT.md`, `docs/ARCHITECTURE.md`, `docs/implementation-notes/pinned-sections.md`.

Done =
1. `ShortcutRecorderRow`: the inline recorder in `PreferencesViewController.swift` (btnShortcut, btnClear, register/unregister, updateGlobalShortcut, updateModiferFlags, and the keyDown/flagsChanged forwarding in `PreferencesWindowController`) is extracted into one reusable control bound to a `Data` pref key. The existing "Keyboard shortcut" row uses it with no visible change (General snapshot light and dark identical in layout to develop). The control shows a clash warning when the chosen combo equals another Hidden Bar shortcut.
2. `HotKeyRegistry`: AppDelegate's single `hotKey` becomes a registry keyed by pref key, so a feature adds a shortcut with one `register(key:, handler:)` call; re-registers on `.prefsChanged`. The existing expand/collapse shortcut keeps working (unit test on the registry).
3. `MenuBarItemCatalog` (direct only, `#if HIDDENBAR_NATIVE_VISIBILITY`): a cached list of menu-bar apps built from `AccessibilityMenuBarInventory` snapshots taken while nothing is hidden, plus the pinned-sections table. Each entry: bundle id, display name (from the running app or bundle), app icon (`NSWorkspace`), current section, `firstSeen` date, `isRunning`. It publishes `.menuBarCatalogChanged` and an `arrivals` diff (bundle ids seen for the first time since the catalog started persisting). It needs no new permission. Pure diff and merge logic is in a testable type in `HiddenBarTests` style with fixtures.
4. Debug hook `dump-inventory` writes the catalog as JSON to `out`.
5. `scripts/hb-cmd <command> [argument] [--out path]`: posts the debug notification via JXA (`osascript -l JavaScript`, `NSDistributedNotificationCenter`), waits for `out` when given, exits nonzero on timeout. Documented in `docs/RUNBOOK.md` under Behavioral verification.
6. `.gitattributes`: `hidden/*.lproj/Localizable.strings merge=union`.
7. Tests for 1 to 4 fail on develop (negative control recorded). `bash scripts/test.sh` green; CI green.

## Scope edges

- No feature behavior: no palette, no arrivals prompt, no new Settings rows besides the refactored recorder.
- Do not change `PinnedSectionResolver` semantics; the catalog reads the table, it does not decide sections.
- Keep the catalog cheap: refresh on the existing unrestricted reads and on `AgentLaunchNotifications`, never a timer under 30 seconds.

## Touches

- hidden/Features/Settings/**
- hidden/Features/Preferences/**
- hidden/Features/StatusBar/Layout/**
- hidden/AppDelegate.swift
- hidden/Models/**
- scripts/**
- HiddenTests/**
- HiddenBarTests/**
- .gitattributes

## Recorded run (put in the PR body)

Command: `bash scripts/test.sh --dd ~/.cache/hidden-bar/dd-foundation`
Exit: 0
Negative control: the new test names failing on reverted production files.
