# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, SPEC, or file that holds the detail.

Source of the current state: the v1.11 issue-clearing pass (2026-06-12), branch
`fix/v1-11-batch` / draft PR #365, and SPEC-003. Core-model changes (separator length
math, collapse state machine) are HIGH RISK and require a mandatory review-team pass.

## Blocked on macOS 27 hardware (Han UAT)

- **macOS 27 hide-mechanism capture (#360).** Run the v1.11 build on real macOS 27,
  trigger a collapse, capture the `HideMechanism:` NSLog (requested length / host-window
  width / button width / actual length). This is the unblocker: it reveals which geometry
  signal separates "honored" from "ignored" on 27. Diagnostic-only instrument already
  shipped. See SPEC-003 + `StatusBarController.swift` (collapse path).
- **Redesign the detection signal, then ship Option B (detect-and-degrade).** Review-team
  found `btnSeparate.button?.window?.frame.width` reads the full menu-bar window width
  (~1728pt on 26.5), so `honored` is trivially true on every OS. Switch to a positional
  signal (separator button X-coordinate before vs after collapse). Once the 27 capture
  calibrates it: re-add the one-shot post-collapse check, a one-time context-menu notice
  linking #360, and stop re-inflating on confirmed failure. Depends on the capture above.
- **Fix the 3 review bugs when re-enabling degrade.** (1) move the `hideMechanismChecked`
  latch to AFTER `honored` is measured (a transient nil window currently burns the
  one-shot check); (2) drop the `?? requested` nil-fallback that latches detection moot;
  (3) `degradeHideUnavailable()` must restore the app activation policy under
  "use full menu bar on expanding", or the bar shows while the app stays `.accessory`.
  `StatusBarController.swift:316,318,329`.

## Blocked on external-display hardware

- **#351 external-monitor visible-bar (26.4) verification.** The widest-attached-screen
  fix is code-only; the 26.4 + external-display reproduction was never run. Confirm no
  full-width bar leak on a real second monitor.

## Actionable now (no special hardware)

- **UAT + merge draft PR #365.** Per the local `UAT.md` (one row per fix, click-through
  steps). Merge order matters (stacked dependency). Merge is Han's action, not the agent's.
- **Cut the v1.11 release.** Version + CHANGELOG staged in #365. Needs a Developer ID for
  notarization + App Store submission. Shipping answers the "is this still maintained?"
  issues and unblocks the round-2 close sweep.
- **Upgrade-path BTM verification before any signed release.** Install a pre-v1.11 build,
  update to v1.11, confirm Login Items shows no leftover `LauncherApplication` row (the
  one-shot `SMLoginItemSetEnabled(..., false)` deauth was added but never run on hardware).
- **AXPress accessibility defect.** VoiceOver users cannot toggle the bar: the arrow's
  `AXPress` handler reads `NSApp.currentEvent`, which is nil under assistive synthesis.
- **`hoverToExpand` Preferences checkbox.** Shipped as a Terminal-only `defaults write`;
  add a proper checkbox in `PreferencesViewController`.
- **Surface the `SMAppService` error contract in the prefs UI.** On `register()` failure
  (unsigned build, or user denies in System Settings), the checkbox stays on while the
  system says off; the error is swallowed into NSLog. Fix when the prefs UI is next touched.
  `Common/Util.swift:29-31`.
- **Round-2 issue close sweep (~35 issues).** Obsolete-OS + meta/support candidates,
  deferred until v1.11 ships so the closures carry the strongest answer.
- **24h memory dogfood (#361).** Instruments stress-cycling found no leak; run v1.11 as
  the daily driver for 24h on the Air to close the open report.
- **Old branch decision.** `feature/menubarDetection` (PR #115) and `feature/ghost-mode`
  (PR #57) were kept per never-delete. Review or discard, Han's call.

## v1.12 standalone wins (no Option D needed)

- **#207 show clock/date when collapsed.** Loudest single feature ask (18+ comments).
- **#355** prefs window layout overlap. **#324** single-instance guard. **#276** Cmd+W
  closes the prefs window. Appearance bundle via community PR #194.

## Architectural epic (Option D, #366)

- **Managed-overflow / second-bar redesign.** The real fix that gates ~30 issues across
  four clusters: icon-drift (#28, #156, #181, #230, #231, #239, #252, #254, #275, #283,
  #321, #334), always-hidden (#171, #224, #242, #288), notch (#206, #225, #228, #245,
  #267, #269, #280, #292, #330), and macOS 27 (#360). Replaces length-inflation with a
  managed overflow bar, likely via Accessibility. Needs a design decision from Han +
  macOS 27 hardware. Design + folded M1 (pin icons, persist order) / M2 (decouple
  always-hidden from `areSeparatorsHidden`, recover stuck items) in SPEC-003.
- **Security + behavior review of community PRs #358 and #350 first.** #358 (second bar,
  +1160 lines) and #350 (notch overflow, +429 lines) are the existing starting points.
  Do not merge on description alone; #358 especially needs a real review.
- **#242 permanent icon-loss repro.** Needs a throwaway defaults profile (live repro
  risks losing real menu-bar icons). Required before the always-hidden decouple lands.
