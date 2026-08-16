# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, SPEC, or file that holds the detail.

Source of the current state: the v1.11 issue-clearing pass (2026-06-12), branch
`fix/v1-11-batch` / draft PR #365, and SPEC-003. Core-model changes (separator length
math, collapse state machine) are HIGH RISK and require a mandatory review-team pass.

## macOS 27 cluster (#360) — FIXED 2026-07-29 (hiding works again)

- **DONE: root cause found on 27.0 hardware (26A5388g).** macOS 27 *discards* a
  status item whose length reaches half the display width, instead of clamping
  it as <= 26 did. Hidden Bar requested `widestScreen * 2`, so the separator was
  dropped on every Mac and hid nothing. Measured on a 2056pt display by sweeping
  the length and photographing the real `MenuBarAgent` window: 600/900/1000pt
  hide correctly, 1028pt (= width/2) and above show everything and the separator
  itself disappears. Neither in-process signal distinguishes the regimes
  (`origin.x` clamps to the region edge either way), so the earlier
  detect-and-degrade heuristic was unsound and has been removed.
- **DONE: the fix.** `updateCollapsedLengths` sizes the collapse length at half
  the width of the display under the pointer, minus a margin, recomputed at each
  collapse. Displaced icons land in 27's native overflow menu. The cliff is per
  item, so the always-hidden separator still works alongside it (verified). The
  separator glyph is suppressed while collapsed on 27, where its span is
  on-screen.
- **PARTIAL: wide displays cannot hide (measured 2026-08-16, 2056pt built-in +
  3840pt external).** A bar clears only if the separator spans icons -> overflow
  boundary; that distance grows with width while the cliff is width/2, so they
  cross around ~2800pt. The 3840pt external needs ~2900pt and drops at 1920pt:
  no length hides there. Under the cliff it displaces icons into mid-bar; at or
  over the cliff the item is dropped and the bar is untouched. Two dead ends were
  tried on hardware first: keying the length on the pointer's display made the
  bars flicker between arrangements as the pointer moved, and dropping the item
  whenever a second display was attached stopped hiding everywhere. Shipping
  rule is narrowest-display sizing — stable, hides on the narrow display,
  wider displays show the shift. Cumulative displacement across two items DOES add up, but any
  item we create lands leftmost where inflation pushes nothing, and inflating the
  arrow shoves the visible-zone icons around. Real fix is #366.
- **Verification trap that produced a false "fixed" claim:** the external bar was
  captured right-half only, so icons displaced LEFT fell outside the crop and
  read as hidden. Always capture the FULL bar width per display
  (`screencapture -x -R <x>,<y>,<w>,<h>`, global CG coords, negative origins for
  displays above/left of the main one).
- **Verification method worth reusing:** the menu bar cannot be photographed with
  a plain `screencapture` when a fullscreen space covers it; capture the
  `MenuBarAgent` window by ID instead (`CGWindowListCopyWindowInfo` →
  `screencapture -l <id>`), which works even when that window is offscreen.
- **Still open: #366 managed-overflow redesign.** Unchanged in scope, but no
  longer urgent. For that design: `MenuBarAgent` persists per-item positions in
  the `com.apple.MenuBarAgent` domain (`TrailingItemPreferredPositions`,
  `status:<bundle-id>::<autosave>` keys); unsandboxed managers manipulate that
  layer via a private assertion API not available to a sandboxed App Store app.
- **Untested on hardware we lack:** multi-display (the narrowest-screen rule) and
  notched Macs.

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
