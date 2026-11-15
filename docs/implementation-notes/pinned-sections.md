# Pinned sections (#366): delta from the decision brief

Spec: `docs/briefs/DECISION-BRIEF-366-overflow-bar.md` (PR #472), sections 3B, 3C, 5. Han's answers: Q1 yes (macOS 27 direct is the main product), Q2 never-seen apps default to visible, a ⌘-drag keeps editing the table unless the app just relaunched, the Preferences list edits it too, Q3 yes (deeper MenuBarClientCore bet, no Screen Recording). Base `develop` at `af0f151`.

Only what differs from the brief, or what the brief left open, is recorded here.

This file is force-added: `.gitignore` keeps `docs/implementation-notes/` in the local tooling layer, which is how SPEC-003 was lost (brief, top).

## Phase 1: section table

- **A drag is a change between two reads, not a difference from the table.** The brief says "section differs from table: user dragged". That would undo every Preferences edit and every "new apps" default on the next collapse: a never-seen app's icon lands far left, so the next read finds it on the hidden side, which differs from its default `visible`. The resolver compares each app's read section with the section it was read in last time (the existing `nativeVisibilityLastSections` memory, now the "observed" baseline). It updates the table only when that changed and the app did not launch since the last read. The baseline is updated on every read, relaunched apps included, so the position macOS gave a relaunched icon becomes the new reference.
- **An app missing from the table that did not just launch takes its read position** (and is added to the table). Only an app that launched since the last read gets the visible default. Reason: users upgrading from 1.11.0/1.11.1 on 27 have an arrangement but no memory to seed from; taking positions for apps that were already running keeps their arrangement on the first collapse (exactly what v1.11.2 does).
- **No "Show new menu bar apps" preference.** Q2 settled the default (visible); it is a constant (`PinnedSectionResolver.newAppSection`). A toggle is one checkbox later if anyone asks.
- **Seeding is lazy.** `UserDefaultsPinnedSections` returns the v1.11.2 memory until its own key (`pinnedSections`) is first written, which happens at the first read with the beta on. A user who leaves the beta off never gets a table; turning it on later seeds from the memory as it is then.
- **The beta checkbox takes effect at the next collapse**, not at once: a collapsed bar keeps its current restriction until then.
- **"Reset all to visible"** is a Preferences button next to the beta checkbox (the list arrives in phase 2) and the debug hook `reset-pinned`. It resets apps that are not running too.
- **Debug hooks added** (Debug builds only): `pinned-sections on|off`, `pin <bundle>=visible|hidden|alwaysHidden` (what a list row runs), `reset-pinned`. `dump-state` gains `pinsSections`, `pinnedSections`, `observedSections`, `launchedSinceRead`.

| Proof | Result |
|---|---|
| `bash scripts/test.sh` | Direct 220, App Store 176, 0 failed (baseline 209 / 165); +11 `PinnedSectionsTests` |
| Negative controls (local mutation script, one mutant at a time) | relaunch counts as a drag: 2 fail; drag = differs from the table (the brief's literal rule): 4; new app takes its position: 2; beta ignored (= v1.11.2): 5; Preferences edits not applied: 2; launched app uses the read memory: 1 |
| Beta off = v1.11.2 | every pre-existing engine test runs with the beta off (the default in the engine init) and passes unchanged; `testWithTheBetaOffARelaunchedAppGoesWhereMacOSPutsIt` pins the old drift and that the table is untouched |
| Release warnings | Release-Direct (signed) and App Store Release: identical set to `af0f151` |

## Phase 2: Preferences list and always-hidden

- **Always-hidden on 27 with the beta on.** The always-hidden section is held hidden while expanded when the table has an always-hidden app, even with the always-hidden separator disabled (an app can be set always-hidden from the Preferences list alone). The "hide separators" state is set again at every collapse, so Option-click becomes "show everything until the next collapse" instead of a persisted mode. That is what makes #224 hold without the user ever Option-clicking, and the collapse after an Option-click is a read from an unrestricted bar, so ⌘-drags made while everything showed are recorded. Same rule as the legacy decouple (phase 3), one mental model on both engines.
- **"Hide separators" is re-set by the controller, through the engine.** `MenuBarEngine.separatorsHiddenForCollapse(current:)` says what state a collapse should leave; the controller runs its own `hideSeparators()` when that differs, so the stored preference, the Option-click toggle and the engine agree. Native engine: `true` with the beta on, unchanged with it off. Cost: the first collapse after an Option-click reads the bar twice (the re-hide on the expanded bar, then the collapse); the first read is superseded by generation, so only one AX snapshot is used.
- **The list** sits under the beta checkbox in Preferences (macOS 27 direct only): a 150 pt scroll view, one row per table app (NSWorkspace icon and name, a Visible / Hidden / Always hidden popup), then "Reset all to visible". Apps that are not installed any more show their bundle id; Control Center's extras show as "macOS extras". It reloads on open and after every edit; a collapse while it is open does not refresh it (it reloads next time it opens). Row order and naming are `PinnedSectionsList.entries`, unit-tested; the view code is not (Preferences is not in a test target).
- **Finding: NSWorkspace does not post launches of agent apps.** `didLaunchApplicationNotification` skips LSUIElement / background apps, and most menu-bar apps are agents. On screen, the helper (an LSUIElement app) never reached `launchedSinceRead` on the 1.11.2 code path, so it never got the new-app default and took its far-left position (`hidden`); an agent the user keeps visible would likewise read as dragged when macOS re-places it after a relaunch. Fix: `AgentLaunchNotifications` watches `NSWorkspace.runningApplications` (KVO) and posts agent starts and quits on its own center, which the engine observes next to NSWorkspace's; apps with a Dock icon stay with NSWorkspace, so none is reported twice. **This is also why the shipped 1.11.2 launch handling (#446, `a017d6a`) does not help most menu-bar apps.** Decided: it runs with the beta off too (own commit, `AgentLaunchNotifications.isActive(pinnedSectionsEnabled:)`; `testWithPinnedSectionsOffAgentStartsAreStillReported` fails when it returns the beta state, the earlier behavior). So beta off is v1.11.2 plus agent-launch detection.

| Proof | Result |
|---|---|
| `bash scripts/test.sh` | Direct 227, App Store 183, 0 failed |
| Negative controls | pinned always-hidden ignored: 2 fail; no re-hide at collapse: 1; edits skip the expanded bar: 1; list unsorted: 1; agent center not observed: 1; Dock apps reported twice: 1 |
| Release warnings | clean Release-Direct (signed) and App Store Release: identical set to `af0f151` (one new Sendable warning was found and fixed) |
| On screen (this Mini, 27.2.1, two displays) | helper `foundation.dwarves.pinprobe` launched while collapsed: `launchedSinceRead` has it, section visible at once; first read finds its icon at x=686, left of the arrow (x=724-756): observed `hidden`, pinned `visible`; same on a second read; quit and relaunch while collapsed: still `visible`; `pin =hidden` (the list row's action): `hidden`, survives the next read; `boundary 656` (drag stand-in): `visible`; `pin =alwaysHidden` on the expanded bar and `reset-pinned`: table follows, reset leaves 34 apps all `visible`; beta off: the same relaunch reads `hidden` (v1.11.2 drift). Prefs exported before and identical after, no new SU* keys, installed app relaunched. No pointer or key input. |
| Restriction swap on screen | first runs were blocked by a microphone in use; proven after #475, see "On screen from /Applications" below |

## Phase 3: legacy patches (option C)

- **Decouple = re-hide at every collapse.** The legacy engine can only hide the always-hidden section by inflating its separator, so "always hidden" and "hide separators" are the same mechanism; what users hit (#224) is that the stored Option-click state decided it, and enabling the section stores "shown". Now every collapse hides the section again (the same `separatorsHiddenForCollapse` hook as the native beta), so an expand keeps it hidden and Option-click is a reveal until the next collapse. The misplaced-separator guard (`isBtnAlwaysHiddenValidPosition`) still applies: a separator on the wrong side is never inflated.
- **"Show Everything"** is a right-click menu item on the arrow (and the separator), legacy engine only: expands the bar and shows the always-hidden section, until the next collapse. It does not move icons macOS persisted off-screen (#242's permanent case); MANUAL says so.
- **Gated to macOS 26 and earlier** (`osMajorVersion < 27`, injected for tests). The App Store build also runs this engine on 27, where inflating is ejected; nothing changes there, per "no behavior change on 27".
- The controller wiring (when to call `hideSeparators()`, the menu item) is not unit-tested: StatusBarController owns real status items. Engine flags are tested and mutation-checked.
- **No macOS 26 run.** This Mini is on 27.2.1. A run on a 26 Mac is needed before release: enable the always-hidden section, collapse, expand (section stays hidden), Option-click (shows), collapse, expand (hidden again), right-click › Show Everything.

| Proof | Result |
|---|---|
| `bash scripts/test.sh` | Direct 232, App Store 188, 0 failed (baseline 209 / 165) |
| Negative controls | no decouple (= af0f151): 2 fail; no Show Everything (= af0f151): 1; patches on 27: 1 |
| Legacy and App Store = af0f151 apart from C | every pre-existing `LegacyLengthEngineTests` / `MenuBarOrderTests` case is unchanged and passes in both schemes; on 27 the legacy engine reports no patch (`testNothingChangesOnMacOS27`) |
| Release warnings | clean builds, identical set to `af0f151` |

## Phase 4: hidden-items menu (thin A), not built

Follow-up, as the brief's phase 3: generalise `NotchOverflowController` into a menu off the arrow on 27 (direct): one row per app the table has in `hidden` / `alwaysHidden`, app icon from NSWorkspace (no Screen Recording, Q3). A click allows that bundle (swap the restriction, as `allowLaunchedAppsIfIdle` does), AXPresses its item, and re-hides when its menu closes, reusing the `NotificationCenterSession` pattern. The table from this PR gives the menu its rows for free. Test without input: a Debug hook that opens the menu, a helper that writes a marker file when its menu opens, AXPress through the proxy, and `dump-state` showing the restriction back within one check.

## Settings window (after #481)

The redesigned Settings window (#481) replaced the storyboard Preferences, so the phase 1 and 2 UI notes above (checkbox, 150 pt list) are superseded:

- **Menu Bar Apps tab** (`MenuBarAppsSettingsViewController`): registered in `MenuBarAppsPane.makeViewController` at launch when the native engine runs (direct build, macOS 27), after `-settingsSnapshotDir` is checked, so the generic snapshot loop never draws this Mac's apps. Grouped rows: app icon (NSWorkspace, no capture), name without ".app", a Visible / Hidden / Always hidden popup; a second group "Reset all to visible". Beta off: one row "Pinned sections is off" with a Turn On button (the tab stays, so the switch is findable). No apps yet: one row saying apps appear after a collapse. The list scrolls past 360 pt. It rebuilds on open, on every pref change and on `.pinnedSectionsChanged`.
- **Store seam**: the pane reads and writes through `MenuBarAppsStore`; `LiveMenuBarAppsStore` is the app's prefs, `SnapshotMenuBarAppsStore` (Debug) gives the on / off / empty fixtures for `-settingsSnapshotDir` (`direct-menubarapps-<state>-<light|dark>.png`).
- **"Pinned sections (beta)" switch** is in Advanced, native engine only, bound to `pinnedSectionsEnabled`, now also a registered default (`true`) in `AppDelegate.defaultPreferenceValues`.
- **Keys in the tests and the import whitelist**: `pinnedSectionsEnabled` joins `SettingsWindowTests.legacyBoolKeys` (and the App Store build's no-direct-rows list); `pinnedSections` joins `legacyOtherKeys`. Both join `AppStoreSettingsImport.importableKeys` (#474); the table is a dictionary, so the importer gains a `.dictionary` kind.
- New strings carry English text in every locale, like #481's.

| Proof | Result |
|---|---|
| `bash scripts/test.sh` | Direct 285, App Store 210, 0 failed |
| Negative controls | Advanced switch unbound: `test_everyOldSwitch_stillWritesItsKey` fails; popup writes nothing: `test_menuBarApps_popupsAndResetWriteThePinnedTable` fails; beta keys out of the whitelist: `testWhitelistCoversEveryPreferenceKeyTheAppDefines` fails |
| Snapshots | Menu Bar Apps on, off, empty, light and dark, plus Advanced, drawn offscreen with `-settingsSnapshotDir` |

## On screen from /Applications (after #475)

macOS 27 applies the allow-list only to apps it keys by bundle id, which in practice means apps in /Applications; a copy run elsewhere hides even its own arrow. So the #473 Debug-Direct build (head `b0a283d`, Developer ID signed) and a helper status-item app with a magenta 16 pt icon (`foundation.dwarves.pinprobeb`) ran from /Applications. The installed app was renamed aside and renamed back; its CDHash was identical after, login items unchanged, prefs identical (extra test keys removed before the re-import). Truth is pixels: magenta pixels in a screenshot of the menu bar (1024 = the whole icon at 2x), plus AX x of the probe and the arrow. No pointer or key input.

| Step | Beta | Magenta px | Result |
|---|---|---|---|
| New app launched while collapsed | on | 1024 | shown at once (new-app default) |
| Pinned visible, quit and relaunched while collapsed, then a read | on | 1024 | stays shown |
| List sets it hidden (collapsed) | on | 0 | hidden at once |
| Pinned hidden, relaunched while collapsed; expanded; collapsed again | on | 0 / 1024 / 0 | hidden, shown with the bar, hidden again |
| Relaunched, its icon then read on the hidden side (boundary hook) | on | 1024 | stays shown: pinned `visible`, observed `hidden` |
| Same relaunch and read | off | 0 | drifts to hidden (v1.11.2) |

macOS kept this probe's slot right of the arrow across relaunches, so "macOS re-placed the icon on the hidden side" was stood in for with the debug boundary moved just right of the probe after the relaunch, for both runs. Crops: `docs/implementation-notes/pinned-sections-proof/`.

## Decided (Han, 2026-11-15)

1. Agent-launch source for beta-off users too: yes, shipped as its own commit (see the phase 2 finding). Test counts after it: Direct 233, App Store 189.
2. Option-click shows the always-hidden section until the next collapse, on both engines: accepted.
3. For the beta, the Preferences list is the path for always-hidden apps (their icons are hidden while expanded, so a ⌘-drag needs Option-click first): accepted.
4. Apps that recreate their icon without relaunching (SwiftBar refresh) can still look like a drag: later.

## Follow-ups

- Per-app ignore-drags lock, for apps whose icon is recreated without a relaunch (decision 4).
- Hidden-items menu (thin A), phase 4 above.
- macOS 26 run of the legacy patches before release (phase 3).
