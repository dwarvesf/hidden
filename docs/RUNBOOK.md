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
   reads ~20pt expanded vs ~2x-screen-width collapsed. Item 1 is the arrow.
2. **Real clicks, not AXPress**: `AXPress` on the arrow is a no-op because the
   action handler reads `NSApp.currentEvent` (nil under assistive synthesis;
   known accessibility defect). Post real `CGEvent` mouse clicks at the arrow's
   AX-reported coordinates instead.

Standard checks before any release:

- expand/collapse toggle flips the separator size both ways;
- with `numberOfSecondForAutoHide` set to 3, an expanded bar survives 2x the
  window while the pointer is parked in the menubar band, collapses within the
  window once the pointer leaves, and collapses normally if the pointer never
  entered;
- `hoverToExpand` off: no monitor log line, hover does nothing; on (the
  Preferences checkbox, no relaunch): dwell expands (synthesize a `mouseMoved` stream: cursor warping alone fires no
  events);
- autostart pref on -> `AutoStart: SMAppService.mainApp.status = 1` on stderr;
  off -> `= 0` (run the binary directly to capture stderr);
- localization tables stay parseable: `plutil -lint hidden/*.lproj/*.strings`.

### Debug hooks harness (`scripts/hb-cmd`)

A Debug build listens for the distributed notification
`com.dwarvesv.minimalbar.debug.command` (userInfo `command`, `argument`, `out`;
`StatusBarController.handleDebugCommand`). `scripts/hb-cmd` is the one sender,
so nothing is posted by hand and no key or pointer input is involved:

```bash docs/RUNBOOK.md
scripts/hb-cmd <command> [argument] [--out path] [--timeout seconds] [--dry-run]
```

- It posts through JXA (`osascript -l JavaScript`, `NSDistributedNotificationCenter`).
- With `--out` it waits (default 15 s) for the app to write that file, newer than
  the call, and exits 1 on timeout; exit 2 is a usage or osascript error. A
  Release build has no hooks and ignores the post, so it times out.
- `--dry-run` posts nothing: it prints what it would send and still runs the wait,
  which is how the argument parsing and the timeout path are tested without an app.
- `dump-state` writes the engine and preference state; `dump-inventory` writes the
  menu-bar app catalog (`MenuBarItemCatalog`: bundle id, name, section, first-seen
  time, running state, and the arrivals of the latest read) as JSON to `out`.
- A feature adds its own commands as new cases in `handleDebugCommand`, prefixed by
  the feature name.
- Run it only against a Debug build you own. An unknown command is logged and, with
  `--out`, answered with the state dump.

When testing on a machine that runs Hidden Bar daily: do not swap by hand. Build the Release-Direct
app signed with the Developer ID team, then `scripts/install-local.sh --app "Hidden Bar.app"` (it
backs up the prefs, quits the app, keeps the installed app aside and relaunches), test, and put
everything back with `scripts/install-local.sh --restore` (see the next section).

## Install a notarized zip on this Mac or another

`scripts/install-local.sh [--host ALIAS [--when-online]] [--check-only] ZIP|--app PATH|--restore [RUN_DIR]`
installs a `Hidden-Bar-vX.Y.Z-macos.zip` into `/Applications`; `--host` goes over `mini-run`, and
`--when-online` waits (bounded, `--wait-max`) for a host that is offline. It refuses a zip that
is not signed by team `W777S7V8TN` or that Gatekeeper does not call `Notarized Developer ID`,
before touching `/Applications`. It then backs up the prefs domain and moves the replaced app
into `~/Library/Application Support/HiddenBar-backup/<stamp>/` (nothing is deleted), installs with
`ditto`, relaunches, and prints a before/after table: version, CDHash, Gatekeeper, and the System
Events login items named "Hidden Bar", which must all point at `/Applications/Hidden Bar.app`
(exit 4 flags a stray; remove it by hand). `--check-only` verifies the zip and shows what is
installed now, changing nothing.

`--app PATH` installs a built `Hidden Bar.app` directory instead (test a branch build against the
real app). It needs the same Developer ID team as the installed app, skips the notarization
requirement and says so in the table (signature, bundle id and team are still checked); over `--host`
the app travels as a zip. Every run writes `meta.txt` into its backup folder with the CDHash of the
app it set aside. `--restore [RUN_DIR]` (latest run when omitted) quits the app, moves the current
app into the run folder as `Hidden Bar.replaced.<stamp>.app`, moves the backed-up app back, runs
`defaults import` on the saved prefs (the replaced prefs stay as `prefs.replaced.<stamp>.plist`),
relaunches, and checks the restored CDHash equals the recorded one (exit 4 if not). Nothing is
deleted. Tests: `bash scripts/test-install-local.sh` (fixtures only, never
the real `/Applications`). Never judge arrow or hiding behaviour on a copy outside `/Applications`.

## Release

1. Verify the stack: every PR reviewed, builds green, behavioral checks above run.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project file
   (every occurrence: the App Store target's four configurations plus the
   Direct target's four; `grep -c MARKETING_VERSION` must match the count you
   edited).
3. Archive the GitHub build with the **Hidden Bar** scheme
   (`Release-Direct`; builds the **Hidden Bar Direct** target), then notarize (Developer ID), staple, zip, and publish a
   GitHub release with notes listing closed issues. The **Hidden Bar App Store**
   scheme archives `Release`, the sandboxed App Store build, which cannot hide
   on macOS 27. v1.11 shipped that build to GitHub by mistake. Before zipping,
   confirm the app is unsandboxed:

   ```sh
   codesign -d --entitlements - 'Hidden Bar.app' | grep app-sandbox  # must print nothing
   ```

   The target signs automatically for development, so a plain archive fails
   with "conflicting provisioning settings". Archive with manual Developer ID
   signing, then export with `method` `developer-id` (`signingStyle` manual,
   `signingCertificate` "Developer ID Application"); the export re-signs
   Sparkle's XPC services, `Autoupdate` and `Updater.app` with hardened
   runtime and a timestamp:

   ```sh
   xcodebuild archive -project 'Hidden Bar.xcodeproj' -scheme 'Hidden Bar' \
     -configuration Release-Direct -archivePath build/HiddenBar.xcarchive \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Developer ID Application' \
     DEVELOPMENT_TEAM=W777S7V8TN OTHER_CODE_SIGN_FLAGS=--timestamp
   ```
4. App Store (separate lane, **Hidden Bar App Store** scheme): the MAS listing
   has lagged GitHub since v1.8 (issues #281/#202); decide deliberately whether
   a release goes there too.
5. Homebrew cask (`brew install --cask hiddenbar`) follows the GitHub release
   artifact; notarization matters (issue #219).
6. Sparkle appcast (direct build only, see below): sign the notarized zip, add
   the appcast entry, upload `appcast.xml` to the release.
7. Before any public release after the SMAppService migration: one
   upgrade-path run from a launcher-era build (v1.9 or older) verifying System
   Settings shows no ghost LauncherApplication login item.

## Sparkle appcast

The direct build self-updates through Sparkle 2 (`SUFeedURL` in
`hidden/Info-Direct.plist` is
`https://github.com/dwarvesf/hidden/releases/latest/download/appcast.xml`, so
the appcast must be an asset of the **latest** release). The private EdDSA key
lives in 1Password (`dfoundation-prod`, item "Hidden Bar Sparkle EdDSA private
key"); only the public key (`SUPublicEDKey`) is in the repo. Losing the key
means no installed copy can ever verify another update, so never regenerate it.

Sparkle's `sign_update` and `generate_appcast` come from the Sparkle release
tarball matching the pinned package version (2.10.1, `Sparkle-<ver>.tar.xz`
under `bin/`). Run from a folder that holds only the zip(s) to publish:

```sh
# 1. zip the stapled app (keep the name stable: Hidden-Bar-v<version>-macos.zip,
#    the asset name the Homebrew cask URL expects)
ditto -c -k --sequesterRsrc --keepParent 'Hidden Bar.app' Hidden-Bar-v1.12-macos.zip

# 2. EdDSA signature (key streamed from 1Password, never written to disk)
sign_update --ed-key-file <(op read 'op://dfoundation-prod/Hidden Bar Sparkle EdDSA private key/password') Hidden-Bar-v1.12-macos.zip
# prints: sparkle:edSignature="..." length="..."

# 3. appcast entry (reads the same key; run over a folder holding the new zip
#    plus the previous appcast.xml so history is kept; skip the download on
#    the first Sparkle release)
gh release download --pattern appcast.xml -R dwarvesf/hidden   # from the previous release
generate_appcast --ed-key-file <(op read 'op://dfoundation-prod/Hidden Bar Sparkle EdDSA private key/password') \
  --download-url-prefix 'https://github.com/dwarvesf/hidden/releases/download/v1.12/' \
  --link 'https://github.com/dwarvesf/hidden' .

# 4. publish: the zip and appcast.xml are both release assets
gh release upload v1.12 Hidden-Bar-v1.12-macos.zip appcast.xml --clobber -R dwarvesf/hidden

# 5. also upload a copy of the zip named Hidden-Bar-macos.zip, so
#    releases/latest/download/Hidden-Bar-macos.zip stays stable (a byte-identical
#    copy; the appcast and the Homebrew cask keep using the versioned name)
cp Hidden-Bar-v1.12-macos.zip Hidden-Bar-macos.zip
gh release upload v1.12 Hidden-Bar-macos.zip --clobber -R dwarvesf/hidden
```

Check before announcing: `curl -sIL https://github.com/dwarvesf/hidden/releases/latest/download/appcast.xml`
ends in 200, and the entry's `sparkle:version` equals `CURRENT_PROJECT_VERSION`
(Sparkle compares that, not the marketing version, so it must increase every
release). Because `latest` follows the newest published release, publish the
release as a draft first, upload assets, then publish.

## Direct vs App Store targets

Two targets share the sources. **Hidden Bar Direct** (scheme *Hidden Bar*,
`Debug-Direct`/`Release-Direct`) is unsandboxed, defines `HIDDENBAR_SPARKLE`,
uses `hidden/Info-Direct.plist`, and is the only one that links and embeds
Sparkle. **Hidden Bar** (scheme *Hidden Bar App Store*, `Debug`/`Release`) has
no Sparkle package, flag, or Info.plist keys. SwiftPM cannot link a package
per configuration, which is why this is two targets, not one. The unused
combinations (App Store target in `*-Direct`, Direct target in `Debug`/`Release`)
are named `Hidden Bar (unused)` on purpose: the test bundles resolve their
host app by product path, and two targets producing `Hidden Bar.app` in one
configuration break `build-for-testing`. After archiving the App Store build:

```sh
otool -L 'Hidden Bar.app/Contents/MacOS/Hidden Bar' | grep -c Sparkle   # must print 0
```

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
