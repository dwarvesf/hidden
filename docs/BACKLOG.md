# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, SPEC, or file that holds the detail.

Source of the current state: the v1.11 issue-clearing pass (2026-06-12), branch
`fix/v1-11-batch` / draft PR #365, and SPEC-003. Core-model changes (separator length
math, collapse state machine) are HIGH RISK and require a mandatory review-team pass.
The macOS 27 hide mechanism was diagnosed and fixed on hardware on 2026-09-17.

## macOS 27 (#360)

The mechanism is fixed and verified on real hardware (27.0 build 26A428, 1728pt
notched display); see "macOS 27 adjustments" in ARCHITECTURE.md for the measurements.
What remains:

- **Verify on a second display and on a non-notched Mac.** The collapse length is
  derived from the narrowest attached screen because the limit is per display; that
  rule is measured on one display only. A wide single display may also need more push
  than one sub-limit item can deliver -- PR #392 measured ~1500pt needed on a 3008pt
  display against a 1488pt cap, and solved it with extra spacer items. Decide whether
  to adopt spacers after measuring.
- **Always-hidden section on 27.** It routes through the same ramped `setLength`, but
  was not exercised on hardware (enabling it would have disturbed the test machine's
  hand-arranged bar).
- **Item placement is the remaining user-visible defect.** Positions now live in the
  host's layout table: `NSStatusItem Preferred Position ...` is gone from the app's
  defaults, a re-registered item lands far left, and on a busy bar the separator can
  land inside the system overflow (`»`) where the user cannot see it. Today's answer
  is a one-time ⌘-drag, documented in MANUAL.md. A real fix (pin/seed positions) is
  part of #366.
- **Close the duplicate reports** once v1.11 ships: #377, #391, #394, #398 all
  duplicate #360. Community fix attempts to credit/close: #382, #396, #400, #392.

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
