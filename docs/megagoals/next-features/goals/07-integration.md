# SG-07 Integration: CHANGELOG 1.13.0, docs, notarized candidate

Model: sonnet
Effort: high
**Branch:** release/1.13.0-candidate
Wall budget: 120 minutes

Read first: `../CONTRACT.md`; `docs/RUNBOOK.md` (Release, Direct vs App Store targets); `CHANGELOG.md` 1.12.0; `docs/MANUAL.md`; `docs/BACKLOG.md`.

Done =
1. `CHANGELOG.md` 1.13.0 entry in the 1.12.0 style: the four features, each marked opt-in, with the Settings path and the permission note (none new).
2. `docs/MANUAL.md`: one row per new Settings row and per new shortcut. `docs/BACKLOG.md`: header refreshed to 1.13.0, shipped items moved, the spike's rejected triggers recorded as open items.
3. `docs/ARCHITECTURE.md`: the catalog, hotkey registry, palette, arrivals and presentation pieces added to the component map.
4. Version bump per RUNBOOK Release step 2: `MARKETING_VERSION = 1.13.0` at every occurrence and `CURRENT_PROJECT_VERSION` incremented; the grep count matches.
5. Local candidate: `Release-Direct` archive, Developer ID signed, notarized and stapled per RUNBOOK. Evidence: `codesign --verify --deep --strict`, `spctl -a -vv`, `xcrun stapler validate`, the Info.plist version. The candidate zip stays local at `~/.cache/hidden-bar/release/1.13.0/`.
6. Smoke test without launching the Release build from a scratch path (a Release build outside `/Applications` runs the install-location check against the real bundle id): static checks in item 5 plus the host-state protocol before and after, showing no change.
7. PR to develop with the docs and version bump; CI green.

## Never

- No tag, no GitHub release, no Sparkle appcast edit or upload, no App Store Connect upload. Stop and report at the candidate.
- Do not copy the candidate into `/Applications`.

## Touches

- CHANGELOG.md
- docs/**
- Hidden Bar.xcodeproj/project.pbxproj
