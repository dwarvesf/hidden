# Shared contract: next features (1.13.0)

Every worker on this mega-goal follows this file. It is pinned at Wave 0 and changes only through the lead. Paths are relative to the repo root; line numbers are from develop at `97d6a23` and drift.

## 1. Where you work

- Clone: `git clone -q git@github.com:consolelabs/hidden.git ~/.cache/hidden-bar/clones/<slug>`, then `git checkout -b <branch> origin/develop`. One clone per sub-goal. Never use `/Users/tieubao/workspace/consolelabs/hidden` (the shared checkout) or another worker's clone.
- Derived data: always `HIDDEN_TEST_DD=~/.cache/hidden-bar/dd-<slug>` (or `--dd`). The default `~/.cache/hidden-bar/dd` is shared and parallel runs corrupt it.
- Base: `origin/develop`. Before each push: `git fetch -q origin`, then `git rebase origin/develop` (or merge, if you already pushed and the PR has review comments). Resolve conflicts yourself.
- PR target: `develop`. Never merge. The lead merges after the wave verifier passes.

## 2. Pref keys

- Declare in `hidden/Extensions/UserDefault+Extension.swift`, `enum UserDefaults.Key`: lowerCamelCase, the string equals the identifier, bools end in `Enabled`.
- Accessor: a static var on `enum Preferences` (`hidden/Common/Preferences.swift`). The setter writes, then posts `.prefsChanged`.
- Default-true bools: register in `AppDelegate.defaultPreferenceValues` and read with `object(forKey:) as? Bool ?? true`. Default-false bools need no entry.
- Reserved names (use exactly these; add only what your sub-goal needs):

| Feature | Key | Type | Default | User-facing |
|---|---|---|---|---|
| F3 | `revealOnScrollEnabled` | Bool | false | yes |
| F3 | `revealOnEmptyClickEnabled` | Bool | false | yes |
| F3 | `revealOnShakeEnabled` | Bool | false | yes |
| F1 | `findHiddenIconShortcut` | Data (`GlobalKeybindPreferences` JSON) | unset (feature off) | yes |
| F2 | `newAppDefaultSection` | Int (0 ask, 1 show, 2 hide) | 1 show (1.12 behavior) | yes |
| F2 | `arrivalsPending` | Array of bundle ids | empty | no (internal) |
| F4 | `presentationAutoMirrorEnabled` | Bool | false | yes (only if the spike says automatic is feasible) |
| F4 | `presentationAutoSlideshowEnabled` | Bool | false | yes (same) |
| F4 | `presentationSensitiveApps` | Dictionary `[bundleId: true]` | empty | yes |
| F4 | `presentationShortcut` | Data | unset | yes |
| F4 | `presentationModeActive` | Bool | false | no (internal) |

- Every feature is opt-in: with all defaults, 1.13.0 behaves exactly like 1.12.0.

## 3. Pref-key tests (both must pass)

- `HiddenTests/SettingsWindowTests.swift` `test_everyOldSwitch_stillWritesItsKey`: append each new Bool key to `legacyBoolKeys`; a non-Bool user-facing key goes in `legacyOtherKeys`. The row's control must carry `identifier == key` (use `boundSwitch`) and must be present in `fullContext()` (direct, macOS 27, notch).
- A direct-only row: also add its key to the App Store hidden-rows list in `test_appStoreBuild_hidesDirectOnlyRows`.
- `HiddenTests/AppStoreMigrationTests.swift` `testWhitelistCoversEveryPreferenceKeyTheAppDefines`: every user-facing key goes into `AppStoreSettingsImport.importableKeys` (`hidden/Features/AppStoreMigration/AppStoreMigration.swift`, Bool and Int as `.number`, Data as `.data`, Dictionary as `.dictionary`; no new `Kind`) AND into the test's `appKeys`, in the same commit. Internal keys go in neither.
- A pref with side effects must react to `.prefsChanged` so `AppDelegate.applyImportedPreferences` needs no edit.

## 4. Settings UI (match the 1.12 redesign)

- Rows go on existing tabs only; no new tab. Placement is fixed by the design boards: F1, F3, F4 on General; F2 on Icons.
- Toggle row: `SettingsForm.row(title, caption:, control: boundSwitch(key, read:, write:))`. Group: `addSection(title, rows:)`. Footnote: `addFootnote(_:)`. Refresh: `onRefresh { }`.
- Gate direct-only rows on `context.usesNativeEngine` (F1, F2, F4). F3 rows show in both builds.
- Shortcut recorder: use the shared `ShortcutRecorderRow` that SG-01 extracts. Never copy the inline recorder from `PreferencesViewController.swift`.
- Strings: English text in all 13 `hidden/*.lproj/Localizable.strings`, via `.localized`; `plutil -lint hidden/*.lproj/*.strings` passes. SG-01 adds `merge=union` for these files in `.gitattributes` so local rebases keep both sides.
- Copy follows the boards' wording. No em or en dashes anywhere (code comments, strings, docs, PR bodies).

## 5. Offscreen snapshots (the only UI rendering workers do)

- Build `Debug-Direct` and run the binary with `-settingsSnapshotDir <dir>`; it renders and exits, writes no prefs, needs no Screen Recording.
- New Settings rows appear automatically in `direct-<tab>-<light|dark>.png`.
- Every new non-Settings surface (palette panel, arrivals prompt, presentation pill) adds its own snapshot function in its own file, called from `SettingsSnapshot.swift` with one line, output `direct-<feature>-<state>-<light|dark>.png`, fed by fixture data (no live Accessibility read). Cover every state on that feature's edge board.

## 6. Debug hooks harness

- Transport: `DistributedNotificationCenter` notification `com.dwarvesv.minimalbar.debug.command`, userInfo `command`, `argument`, `out` (`StatusBarController.swift` `handleDebugCommand`, `#if DEBUG`).
- Sender: `scripts/hb-cmd <command> [argument] [--out path]` (added by SG-01). Use it; never post by hand.
- A feature adds its commands as new `case`s in `handleDebugCommand` and new fields in `debugWriteState`, prefixed by feature: `palette-open`, `palette-query <text>`, `palette-select <bundle>`, `arrivals-inject <bundle>`, `arrivals-answer <bundle>=show|hide`, `reveal-sim scroll|click|shake`, `present on|off`. `dump-inventory` comes from SG-01.

## 7. GUI safety on the Mini (Han uses it live)

- Workers do NOT launch the app live. Workers run unit tests and the offscreen snapshot only.
- No keystrokes, no pointer input, no cursor moves, ever: no System Events `keystroke`/`key code`/`click`, no `orca computer click`, no `cliclick`, no menubar-shot.
- Live hooks-harness runs belong to the wave verifier only, under the host-state protocol in `goals/00-wave0-contract.md`.

## 8. Engines and builds

- Expand and collapse only through `StatusBarController` (`expandCollapseIfNeeded`, `showEverything`, the clock session pattern); call `menuBarEngine.userChangedBar()` before a user-driven change. Never write status-item lengths.
- Reveal-then-rehide: copy the `NotificationCenterSession` pattern in `Engine/Native/MenuBarClock.swift` (session id, poll, collapse at the end only if Hidden Bar expanded).
- Native-only code under `#if HIDDENBAR_NATIVE_VISIBILITY`; handle `.unavailable`.
- Both schemes must build. Logic tests in `HiddenBarTests` (run by both schemes); direct-only UI tests in `HiddenTests`. Name test files `<Source>Tests.swift`.
- New Swift files: register with `~/workspace/tieubao/ops-toolkit/tools/pbxproj-merge/bin/pbxproj-add <pbxproj> <file> --group <group> --target "Hidden Bar Direct"` and again with `--target "Hidden Bar"` when the file builds in both. A pbxproj rebase conflict: `pbxproj-merge <pbxproj>`.

## 9. Permissions (hard stop)

- No Screen Recording, no Input Monitoring, no new TCC permission, no new entitlement. Global mouse and scroll monitors are allowed (hover already uses them); a global `keyDown` monitor is not.
- A feature that seems to need one: stop and report to the lead. Do not build around it.

## 10. Tests and proof

- Iterate with `bash scripts/test.sh --changed --scheme direct --dd ~/.cache/hidden-bar/dd-<slug> > <log> 2>&1`, read the tail. Run the full `bash scripts/test.sh --dd ...` once before the PR.
- Negative control: commit first, then revert only the production change (`git show HEAD~1:<path> >| <path>` style), run the new tests, confirm they fail, restore with `git checkout -- <path>`. Record command, exit, and the failing test names.
- CI: workflow `CI`, required job `Build and test both schemes`. Wait with one `gh pr checks <pr> --watch` call.
- PR body: what, why, test counts, negative control result, snapshot file list, the board names matched. No dashes.

## 11. Ship gate

- If a push is refused by the dwarves-kit ship-gate, stop and report the full gate output. Never log an override; the lead does it from your clone.
