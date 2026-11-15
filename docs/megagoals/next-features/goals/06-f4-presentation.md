# SG-06 F4: Presentation mode

Model: sonnet
Effort: high
Done-mode: proof
Design: bearing
**Branch:** feat/presentation-mode
Wall budget: 150 minutes

Read first: `../CONTRACT.md`; `docs/implementation-notes/presentation-mode-spike.md` (SG-03, its verdict sets the scope); boards `Present-Entry`, `Present-Light`, `Present-Dark`, `Present-Edge`, `Present-Settings`; `CaptureActivityMonitor.swift`; SG-01's `HotKeyRegistry` and `ShortcutRecorderRow`.

Done =
1. Manual mode always ships: a shortcut (`presentationShortcut`), an item in the arrow's context menu, and the "Presenting" pill as drawn turn presentation mode on and off. While on, every app except the keep-list on the board is hidden, and apps in `presentationSensitiveApps` stay hidden even when the user clicks the arrow.
2. Automatic triggers ship only for those the spike verdict marks feasible without new permissions (`presentationAutoMirrorEnabled`, `presentationAutoSlideshowEnabled`); a trigger the spike rejected has no row and no code.
3. Privacy rule: while the camera or microphone is in use, presentation mode lifts its restriction (the dot must stay visible), shows the paused state from `Present-Edge`, and resumes when capture ends. A unit test covers this.
4. Two lists never leave the wrong one held: turning the mode off restores the exact pre-mode list; quit or crash lifts both (fail open). Tests on the state machine.
5. Settings, General tab: the "Presentation mode" group per `Present-Settings` (rows limited by item 2), with the sensitive-apps editor and the camera footnote. Direct build with the native engine only.
6. Pure state machine (manual, auto, capture pause, list swap) with tests; tests fail on develop.
7. Debug hook `present on|off`; offscreen snapshots `direct-present-<state>-<light|dark>.png` for every state on the boards.
8. Pref-key tests and whitelist per CONTRACT section 3 (`presentationModeActive` is internal). `bash scripts/test.sh` green, CI green.

## Scope edges

- No screen-share detection unless the spike proved a public, permission-free signal.
- No Screen Recording, no new TCC permission: stop and report instead.

## Touches

- hidden/Features/Presentation/**
- hidden/Features/StatusBar/Engine/**
- hidden/Features/StatusBar/StatusBarController.swift
- hidden/Features/Preferences/PreferencesViewController.swift
- hidden/Features/Settings/SettingsSnapshot.swift
- hidden/Extensions/UserDefault+Extension.swift
- hidden/Common/Preferences.swift
- hidden/*.lproj/**
- HiddenTests/**
- HiddenBarTests/**
