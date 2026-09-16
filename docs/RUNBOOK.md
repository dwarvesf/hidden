# Maintainer runbook

Build, verify, and release Hidden Bar. Assumes current Xcode on macOS 13+.

## Build

```sh
# CI-style build, no signing required
xcodebuild -project 'Hidden Bar.xcodeproj' -scheme 'Hidden Bar' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

# runnable local build (uses your Apple Development identity)
xcodebuild -project 'Hidden Bar.xcodeproj' -scheme 'Hidden Bar' \
  -configuration Debug build
```

Both must exit 0 with **no** `MACOSX_DEPLOYMENT_TARGET` override; the floor is
13.0 in the project file. The single expected warning is the deliberately
deprecated `SMLoginItemSetEnabled(false)` call that cleans up legacy installs.

## Behavioral verification (no test target exists; this is the methodology)

The repo has no unit-test infrastructure; behavior is verified against the real
menu bar. Two building blocks make that scriptable:

1. **Truth signal**: the separator's AX size.
   `osascript -e 'tell application "System Events" to tell process "Hidden Bar" to get size of menu bar item 2 of menu bar 2'`
   reads ~20pt expanded vs the collapsed length. Item 1 is the arrow.

   On macOS 27 this proves only that the item took the length, NOT that anything was
   hidden -- an item can hold its length and still displace nothing. Verify hiding
   itself by asking the system what occupies the bar, which is owner-attributed:

   - per-app items and positions: `AXUIElementCreateApplication(pid)` ->
     `AXExtrasMenuBar` -> `AXChildren` -> `AXPosition` / `AXSize`, over every running
     app. Beware: these positions stay stale for items pushed out of the bar.
   - what is actually on the visible bar: `AXUIElementCopyElementAtPosition` swept
     across the bar, printing the owning app at each x. This is the signal that
     settles "did the icon leave the bar", and it is read-only.

   Do not drive the session with synthetic keystrokes to set up these tests.
2. **Real clicks, not AXPress**: `AXPress` on the arrow is a no-op because the
   action handler reads `NSApp.currentEvent` (nil under assistive synthesis;
   known accessibility defect). Post real `CGEvent` mouse clicks at the arrow's
   AX-reported coordinates instead.

Standard checks before any release:

- expand/collapse toggle flips the separator size both ways;
- on macOS 27, a *second* collapse after an expand still removes the icons left of
  the separator (the one-jump growth regression in #360 only showed up there: the
  first collapse at launch hid icons even while re-collapse did nothing);
- with `numberOfSecondForAutoHide` set to 3, an expanded bar survives 2x the
  window while the pointer is parked in the menubar band, collapses within the
  window once the pointer leaves, and collapses normally if the pointer never
  entered;
- `hoverToExpand` off: no monitor log line, hover does nothing; on: dwell
  expands (synthesize a `mouseMoved` stream: cursor warping alone fires no
  events);
- autostart pref on -> `AutoStart: SMAppService.mainApp.status = 1` on stderr;
  off -> `= 0` (run the binary directly to capture stderr);
- localization tables stay parseable: `plutil -lint hidden/*.lproj/*.strings`.

When testing on a machine that runs Hidden Bar daily: export the prefs domain
first (`defaults export com.dwarvesv.minimalbar backup.plist`), quit the
installed app, test the dev build, then re-import and relaunch.

## Release

1. Verify the stack: every PR reviewed, builds green, behavioral checks above run.
2. Bump `MARKETING_VERSION` (both Hidden Bar configurations) and
   `CURRENT_PROJECT_VERSION` in the project file.
3. Archive + notarize (Developer ID), staple, zip, GitHub release with notes
   listing closed issues.
4. App Store (separate lane): the MAS listing has lagged GitHub since v1.8
   (issues #281/#202); decide deliberately whether a release goes there too.
5. Homebrew cask (`brew install --cask hiddenbar`) follows the GitHub release
   artifact; notarization matters (issue #219).
6. Before any public release after the SMAppService migration: one
   upgrade-path run from a launcher-era build (v1.9 or older) verifying System
   Settings shows no ghost LauncherApplication login item.

## Stacked-PR hygiene

Feature stacks land as chained PRs (`develop <- A <- B`). Merge the base PR
first, then retarget the next PR's base to `develop` BEFORE merging it;
deleting a merged branch auto-closes dependents otherwise.

## Issue triage map

The live clusters and their code areas are documented at the end of
[ARCHITECTURE.md](ARCHITECTURE.md#known-architectural-limits): notch, macOS 27
mechanism break, and pointer-vs-open-menu limits. Memory reports (#361 et al.)
have so far not reproduced as leaks (constraint-leak fix landed; `leaks` clean
over toggle stress); re-check with a 24h+ uptime `footprint` sample before
chasing further.
