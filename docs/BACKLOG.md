# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, PR, or file that holds the detail.
For live numbers use `gh pr list` and `gh issue list`, not this file.

Source of the current state: develop after v1.13.0 (build 21, published 2026-11-16). Core-model changes (separator length math, collapse state machine) are HIGH RISK and require a mandatory review-team pass.

## Merged, not yet a GitHub release

- **Pause switch wording** in Settings › Advanced (#515).
- **Legacy login item fix, #456:** one SMAppService off/on reset removes the launcher-era `LauncherApplication` record; the hint names the "Hidden Bar" row under Allow in the Background (#517).

## Shipped

- **1.13.0 (2026-11-16, build 21):** reveal without aiming, scroll, empty click, shake (#493); type-to-find palette (#505); arrivals inbox (#503); presentation mode with manual start and a mirror trigger (#504, #509, #511); shortcut recorder, hotkey registry and app catalog (#497); the General pane scrolls (#504). Notarized zip, Sparkle appcast (`docs/RUNBOOK.md`).
- **1.12.0:** never released on its own; ships inside 1.13.0. Redesigned Settings, pinned sections (beta) on macOS 27, Ignore drags, Icons list clean-up, Shift-click full bar, the system overflow notice (#473, #481, #487, #488, #495, #498).
- **1.11.2:** the macOS 27 fixes, Sparkle auto-update, arrow styles, the microphone and camera
  fix. v1.11.1 shipped without Sparkle; the first Sparkle-capable release carried the signed zip
  and `appcast.xml` (`docs/RUNBOOK.md`).

## Open after 1.13.0

- **Direct build bundle id.** 1.13.0 shipped Release-Direct as `com.dwarvesv.minimalbar`, the same as the App Store build (shared prefs, the two cannot coexist). Confirm that stays, or move the direct build to `com.dwarvesv.minimalbar.direct`.
- **Upgrade-path BTM check, #456: FAIL on 1.13.0, PASS with the fix (2026-11-16, mac-ui VM, macOS 27.2.1 26B131).** 1.13.0: after v1.9 with Start at login on, an upgrade and a login, `sfltool dumpbtm` still lists `4.com.dwarvesv.LauncherApplication` and every launch logs error 22 from `SMLoginItemSetEnabled`. The fix (#517) resets the main app item once instead; on the same ghosted 1.13.0 state its first launch logs `Unregister error: 0`, `Register error: 0`, status 1, and the legacy record is gone, still gone after a fresh login, one Hidden Bar under Open at Login. A fresh install (no old container) is marked done without touching login items. System Settings has no row of its own for the legacy record: it sits inside the "Hidden Bar" Allow in the Background row, which an SMAppService app has anyway. Release step 7 still owes one run on real hardware before the next release. Evidence: `docs/implementation-notes/upgrade-btm-check-proof/` (`btm-dumps.txt` first run, `retest.txt` the fix).
- **Presentation keeps all system items.** Measure the clock and battery system item ids live,
  then narrow `NativeVisibilityEngine.presentationSystemItems` from all (0..<64) to those two.
- **Slideshow automatic trigger.** Dropped for 1.13.0; needs a live Keynote or PowerPoint check
  (frontmost app plus a whole-display window it owns) before any code.
- **Shortcuts action for presentation mode.** Needs App Intents; not built.
- **Manual presentation mode does not survive a relaunch.** Decide whether it should.
- **Arrivals dot under the new app's own icon.** Needs an overlay window over another app's
  status item; the arrow dot and the NEW tag carry the signal for now.
- **Arrivals 24 hour lapse** is checked only at launch and when the prompt opens, not on a timer.
- **Reveal polish.** A first-use tip, and a live tune of the empty-space hit test (`HitClassifier`
  was written without a live menu bar).
- **Palette polish.** Bundle id second line, matched-letter weight, a primary "Open System
  Settings" button, panel width 379 vs 360 pt, footer wrap.
- **Tests share the real prefs domain: fixed.** The app reads and writes preferences through `AppDefaults.store`, a dedicated suite (`com.dwarvesv.minimalbar.tests`, wiped at first use) under XCTest. A test host also skips Sparkle, the move and migration offers, and status item autosave; login items and the second-copy quit were already skipped. `HiddenTests/PrefsIsolationTests.swift` checks the real domain is unchanged. A test opts back in with `AppDefaults.sideEffectsOptIn` or `HIDDEN_BAR_TEST_HOST_SIDE_EFFECTS=1`.
- **macOS 27 menu extras belong to `com.apple.MenuBarAgent`.** The overflow spike probed the wrong
  process; re-measure against MenuBarAgent.

## macOS 27 (#360, closed)

- **App Store build cannot hide on 27.** The sandbox denies `mach-lookup
  com.apple.axserver`, so the sections cannot be read even with Accessibility granted.
  v1.11.2 ships a notice that points to the direct build (`MacOS27Notice`). Still open:
  a user-picked list of visible apps instead of ⌘-drag (no Accessibility, still private
  API), or a public mechanism if Apple ships one.
- **Live Activities on macOS 27.3, #469.** Needs info from the reporter (version, left or
  right of the arrow, shows on expand). Our test Macs are on 27.2. Related: #327.

## Needs hardware (not yet run)

- **#351 external monitor.** Closed, but the 26.4 external-display reproduction was never
  run. The multi-display rework is in #468; a real hot-plug and a second monitor are
  untested.
- **24h memory dogfood, #361 / #386.** Instruments stress-cycling found no leak. The Air
  now runs the v1.11.2 candidate; read `footprint -p "Hidden Bar"` after a day.

## Unverified on hardware for v1.11.2

- **Mic and camera indicator.** The bar stays whole while an app records (#432, #438).
- **Faded arrow and arrow styles.** Stealth mode (#173) and the arrow style popup (#310),
  in light and dark menu bars.
- **Clock expands the bar, on screen.** A click on the clock opens Notification Center
  (#410, #467).
- **A real Sparkle update.** An installed build fetching the appcast and updating.

## Decisions for Han

- **Old branches.** `feature/menubarDetection` (PR #115) and `feature/ghost-mode`
  (PR #57) were kept per never-delete; both PRs are closed. Review or discard.
- **#242 permanent icon-loss repro.** Needs a throwaway defaults profile (a live repro
  risks losing real menu-bar icons). Required before the always-hidden decouple lands.

## Architectural epic (#366, decided: option B, pinned sections)

- **Decided.** Option B, pinned sections, shipped in 6e33618 (beta, macOS 27 direct build):
  a per-app section table in place of positions. Brief: `docs/briefs/DECISION-BRIEF-366-overflow-bar.md`;
  notes: `docs/implementation-notes/pinned-sections.md`. The cluster list lives in the epic
  body (`gh issue view 366`, then `gh issue list`).
- **Remains.** Hidden-items menu (phase 4, thin A). Per-app drag lock for apps that recreate
  their icon without relaunching (this PR, #107). macOS 26 run of the legacy patches
  (always-hidden decoupled from "hide separators", "Show everything"). A 27.3 inventory dump
  for #469.
- **What already landed that the epic builds on.** Native hiding on 27 (#403), notch
  overflow menu (#420, in #468). The community second-bar PR (#358) was closed as
  superseded: its window capture no longer works on macOS 27, so the idea continues here.
- Design and the folded M1 (pin icons, persist order) / M2 (decouple always-hidden from
  `areSeparatorsHidden`, recover stuck items) are in SPEC-003 (local planning layer).
