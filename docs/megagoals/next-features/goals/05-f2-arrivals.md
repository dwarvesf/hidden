# SG-05 F2: Arrivals inbox

Model: sonnet
Effort: high
Done-mode: proof
Design: bearing
**Branch:** feat/arrivals-inbox
Wall budget: 150 minutes

Read first: `../CONTRACT.md`; boards `Arrivals-Entry`, `Arrivals-Light`, `Arrivals-Dark`, `Arrivals-Edge`, `Arrivals-Settings`; `docs/implementation-notes/pinned-sections.md`; `MenuBarLayout.swift` (`PinnedSectionResolver`, `PinnedSectionEdits`); SG-01's `MenuBarItemCatalog` arrivals diff.

Done =
1. Settings, Icons tab: popup "When an app adds a new icon" with Ask Me, Show It, Hide It, bound to `newAppDefaultSection` (default Show It, the 1.12 behavior: a never-seen app is visible). Direct build with the native engine only.
2. Show It and Hide It place a never-seen app in that section on first sight, through `PinnedSectionEdits.set`, and never ask.
3. Ask Me: a never-seen app stays visible, is added to `arrivalsPending`, the arrow gets a dot, and Hidden Bar asks once, from the arrow, "show or hide?" as drawn on the Light/Dark boards. An answer writes the section and clears the entry. Undecided apps sit first in the Icons list with a NEW tag. An app is asked at most once, also across restarts.
4. Edge states from `Arrivals-Edge`: several arrivals at once, the app quits before an answer, the app was seen before 1.13.0 (never asked: everything already in `pinnedSections` counts as seen on upgrade), pinned sections off, engine unavailable.
5. Arrival decision logic (seen set, pending queue, answer application, upgrade seeding) is a pure type with tests; tests fail on develop.
6. Debug hooks `arrivals-inject <bundle>` and `arrivals-answer <bundle>=show|hide`; offscreen snapshots `direct-arrivals-<state>-<light|dark>.png` for every state on the boards, plus the Icons list with a NEW row.
7. Pref-key tests and whitelist per CONTRACT section 3 (`arrivalsPending` is internal). `bash scripts/test.sh` green, CI green.

## Scope edges

- Do not change `PinnedSectionResolver.newAppSection` for users who keep the default.
- No notification-center banners (no new permission); the prompt lives at the arrow.

## Touches

- hidden/Features/Arrivals/**
- hidden/Features/Settings/MenuBarAppsSettingsViewController.swift
- hidden/Features/Settings/SettingsSnapshot.swift
- hidden/Features/StatusBar/StatusBarController.swift
- hidden/Features/StatusBar/Layout/MenuBarLayout.swift
- hidden/Extensions/UserDefault+Extension.swift
- hidden/Common/Preferences.swift
- hidden/*.lproj/**
- HiddenTests/**
- HiddenBarTests/**
