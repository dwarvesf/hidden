# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, PR, or file that holds the detail.
For live numbers use `gh pr list` and `gh issue list`, not this file.

Source of the current state: the v1.11.2 candidate, PR #468 (`release/v1.11.2`), after
the round-2 close sweep of 2026-11-15. Core-model changes (separator length math,
collapse state machine) are HIGH RISK and require a mandatory review-team pass.

## Ship v1.11.2

- **Merge #468 and cut the release.** Steps: `docs/RUNBOOK.md` (notarize, App Store
  submission, Sparkle appcast). The issues that say "ships in the next release" close
  when it lands (for example #324, #355, #410).
- **Sparkle appcast, first release step.** v1.11.1 shipped without Sparkle, so no
  installed build can update itself yet. The first Sparkle-capable release needs the
  signed zip and `appcast.xml` as assets of the LATEST release, then the `curl` check
  in `docs/RUNBOOK.md`.
- **Direct build bundle id.** Release-Direct uses `com.dwarvesv.minimalbar`, the same as
  the App Store build (shared prefs, the two cannot coexist). Confirm that is the
  decision, or move the direct build to `com.dwarvesv.minimalbar.direct`.

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
- **Upgrade-path BTM check, #456.** The fix is in #468. Run on hardware: install the App
  Store build or a pre-v1.11 build, update, confirm Login Items shows no leftover
  `LauncherApplication` row.
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
