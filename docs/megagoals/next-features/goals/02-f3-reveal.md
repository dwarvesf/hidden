# SG-02 F3: Reveal without aiming

Model: sonnet
Effort: high
Done-mode: proof
**Branch:** feat/reveal-without-aiming
Wall budget: 120 minutes

Read first: `../CONTRACT.md`; boards `Reveal-Entry`, `Reveal-Light`, `Reveal-Dark`, `Reveal-Edge`, `Reveal-Settings` (`.dc.html` files in ops-toolkit `_inbox/hidden-next-features/design-boards/`).

Done =
1. Three opt-in triggers, each its own Bool key (`revealOnScrollEnabled`, `revealOnEmptyClickEnabled`, `revealOnShakeEnabled`, default false):
   - Scroll down on the menu bar of any screen shows hidden icons; scroll up hides them.
   - A click on empty menu-bar space (not on an item, not on the app menus) shows them. Hit-testing uses Accessibility where available; where it is not (App Store build without Accessibility), the row is hidden in that build.
   - A pointer shake at the top of the screen (three quick side-to-side reversals in the menu-bar band, thresholds as constants) shows them.
   - Clicking anywhere off the menu bar hides them again, through the existing auto-collapse path.
2. Monitors install only while their pref is on (same pattern as `hoverToExpand`), are global mouse/scroll monitors only, and need no new permission.
3. Settings, General tab: the hover row moves into a group titled as on `Reveal-Settings` with the three new switches and captions, in both builds where supported.
4. Edge states from `Reveal-Edge` handled (bar already expanded, Hidden Bar's own menu open, full-screen app, multiple displays, notch).
5. Pure gesture logic (scroll direction, shake detector, menu-bar band hit) in testable types with tests in `HiddenBarTests`; tests fail on develop.
6. Debug hook `reveal-sim scroll|click|shake` drives the same code path as a real event.
7. Pref-key tests and whitelist updated per CONTRACT section 3. Snapshot `direct-general-*` and `appstore-general-*` show the group. `bash scripts/test.sh` green, CI green.

## Scope edges

- No key monitors. No change to hover semantics beyond moving its row.
- Runs in parallel with SG-01, which edits `PreferencesViewController.swift`; expect to rebase onto SG-01 before merge.

## Touches

- hidden/Features/Reveal/**
- hidden/Features/StatusBar/StatusBarController.swift
- hidden/Features/Preferences/PreferencesViewController.swift
- hidden/Extensions/UserDefault+Extension.swift
- hidden/Common/Preferences.swift
- hidden/*.lproj/**
- HiddenTests/**
- HiddenBarTests/**
