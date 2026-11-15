# Decision brief: #366 managed overflow / second bar

Status: for decision. Base: `develop` at `af0f151` (v1.11.2). Scope: design only, no code.

SPEC-003, which the epic and `docs/BACKLOG.md` cite, is not in the repo or in any local clone (`dwarvesf/hidden`, `tieubao/hidden`, the scratchpad clones). It lived in the gitignored planning layer and is lost or on another machine. This brief replaces it; the only SPEC-003 trace left is a comment in `LegacyLengthEngine.swift`.

## 1. The problem

Hidden Bar hides by geometry. Up to macOS 26 it inflates a separator so icons left of it fall off-screen (`LegacyLengthEngine`). On macOS 27 that trick is ejected (#360), so the direct build asks a private Apple API to keep an allow-list of apps visible (`NativeVisibilityEngine`). Both engines read "which section is an app in" from where its icon sits right now. That one fact causes most open bugs: macOS puts a new or relaunched icon at the far left, which is the hidden side, and no public API lets one app move another app's icon. On top of that, macOS 27 hides every system item that is not on its short keep-list, wherever the user put it. The epic asks for one design that keeps the user's choice stable.

| Issue | macOS / build | What the user actually wants |
|---|---|---|
| #334 | 15.7, App Store 1.9 | New icons (input method) land in the visible section, not hidden or always-hidden |
| #107 | any, legacy | A setting: do not auto-hide icons of newly launched apps (BitBar, SwiftBar refreshes) |
| #233 | Mojave (below floor) | Icon order kept across reboot |
| #224 | 12.5, App Store | Always-hidden icons stay hidden when the bar expands |
| #242 | 13.1, notch Mac | Never lose icons for good; a way to get them back |
| #327 | 26 Tahoe | Live Activity: choose always shown or always collapsed, or move it |
| #469 | 27.3 | Live Activities not hidden "improperly" (needs info; our Macs are on 27.2) |
| #446 | 27.0 to 27.2 | Siri, Focus, Now Playing, Timer and similar stay visible when right of the arrow |
| #470 | 27.2, 1.11.1 | Same as #446 for Timer and Now Playing |

## 2. Constraints

```
                  macOS <= 26                         macOS 27+
             +---------------------+        +-----------------------------+
 App Store   | Legacy length trick |        | cannot hide at all          |
 (sandbox)   | no AX (assumed)     |        | MacOS27Notice -> direct     |
             +---------------------+        +-----------------------------+
 Direct      | Legacy length trick |        | NativeVisibilityEngine      |
 (no sandbox)| AX optional (notch) |        | AX required + private API   |
             +---------------------+        +-----------------------------+
```

- **macOS 27 private API.** `MenuBarClientCore.framework`, classes `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion` (exam lockdown mode), loaded with `dlopen` so a removal turns into "unavailable", not a crash (`HBNativeVisibilityShim.m`). It takes system item ids plus bundle ids. Facts from code and threads:
  - Granularity is per app. An app with several icons is shown or hidden as a whole (#427, #443).
  - Only 9 system extras have ids (battery, Bluetooth, clock, display, input, sound, Wi-Fi, Control Center, screen mirroring). Focus, Siri, Now Playing, Timer, Stage Manager and more are hidden by macOS whenever any restriction is held (#446). Live Activities on 27.3 are unmapped.
  - The restriction blocks Notification Center from the clock (worked around in 1.11.2) and hides the mic/camera capsule (restriction dropped during capture).
  - It lifts when Hidden Bar exits, so a crash fails open.
  - While held, hidden apps report stale AX frames and hidden system extras leave AX. Sections can only be read from an unrestricted bar.
  - No per-item windows exist on 27: `CGWindowList` shows one `MenuBarAgent` host window (seen on a 27.2 Mac during the #319 auto-collapse work; Thaw hit the same, see the #358 thread and stonerl/Thaw#687). Window capture as in #358 is dead.
  - macOS 27 draws its own overflow chevron in a bar too narrow for its items (`menu-bar-overflow-indicator`).
- **Sandbox (App Store).** The sandbox denies the `com.apple.axserver` mach-lookup even with Accessibility granted, so no inventory, no AXPress. Private framework use is also an App Review risk. Anything below that needs AX or the private API is direct-build only.
- **Accessibility.** Required to read other apps' items (owner, frame) and to press them. Screen Recording is only needed for item images; Bartender and Thaw make it optional and fall back to app icons.
- **Notch.** Legacy: expanded icons can sit under the notch; #420 adds an AX "Show Notch Items" menu (notch Macs only, uses `NSScreen.main`). Native 27 engine: notch-independent, macOS adds the chevron.
- **Multi-display.** Every display has its own bar. Legacy sizes from the widest screen; the native resolver projects frames per display. External-monitor behaviour of 1.11.2 is untested on hardware (#351). Any panel must open on the display the user is looking at.
- **macOS 13 floor.** Deployment target 13.0, login item via `SMAppService`. #233's reporter is on Mojave and stays unsupported. Ice needs 14+.
- **Licences.** Hidden Bar is MIT. Ice and Thaw are GPL-3.0: behaviour reference only, no code. Bartender is closed source. Dozer is MPL-2.0.

### How others do it (public docs only)

| Product | Model | Permissions | macOS 27 state | Source |
|---|---|---|---|---|
| Ice (GPL-3.0) | Length spacer + "Ice Bar" strip under the menu bar showing item screenshots | Accessibility; Screen Recording for images, limited mode without | Last stable 0.11.12 (2024-10), Tahoe issues open, no 27 build | github.com/jordanbaird/Ice, /releases |
| Thaw (GPL-3.0) | Ice fork (v2); v3 is new code for 27; profiles, groups, triggers | Accessibility required; Screen Recording optional | 3.0.0-alpha, moved off window capture (Thaw #687) | github.com/thaw-app/Thaw, getthaw.app/faq |
| Bartender (closed) | Bartender Bar below the menu bar, triggers, presets; on notch Macs hides shown items to make room | Screen Recording optional (icons without it) | Bartender 7 targets 27 | macbartender.com |
| Dozer fork (MPL-2.0) | Stretch trick; on 26 an "invisible wall" because off-edge items stop drawing | none | n/a | pawiromitchel.com/blogs/reviving-dozer-menu-bar-hider-for-macos-26 |
| Apple, macOS 26+ | System Settings > Menu Bar "Allow in the Menu Bar" switches, no overflow panel | n/a | n/a | support.apple.com/guide/mac-help/mchlad96d366/26/mac/26 |

Takeaway: the "second bar" products all pair a panel with their own order or preset model; the panel alone fixes reachability, not drift. Their image capture broke on 26/27 and they fell back to app icons or rewrote.

## 3. Options

### A. Managed overflow bar (Ice Bar / Bartender Bar style)

```
 menu bar (stays collapsed)   [ ... visible apps ... ] [>] [clock]
                                                        |
                                    click / hover / hotkey
                                                        v
 borderless NSPanel           +------------------------------------+
 under the bar, per display   | [icon] [icon] [icon] [icon] ...    |  hidden section only
                              +---|--------------------------------+
                                  | click a proxy
                                  v
             27: allow that bundle (swap restriction) -> AXPress real item -> menu opens
                 in the real bar -> re-hide on menu close
             <=26: expand, AXPress, collapse on close
 images: app icon (no extra permission) or Screen Recording crop of MenuBarAgent window by AX bounds
```

| Issue | Fixed? | Why |
|---|---|---|
| #334, #107 | partial | New icons still land hidden, but are one click away |
| #233 | no | No order model |
| #224 | yes on 27, partial legacy | Panel lists only the hidden section; legacy must expand to capture |
| #242 | partial | Notch-hidden items reachable; off-screen positions unchanged on legacy |
| #327 | partial | Reachable in the panel, still collapsed in the bar |
| #469 | no | Needs info; Apple-hidden items are not in AX while hidden |
| #446, #470 | partial | Proxy click can lift the restriction like the clock path; never visible in the bar |

- **27 / App Store:** direct build only. Capture as in #358 is dead on 27; images need the MenuBarAgent crop (unproven here) or app icons.
- **Risk:** high. Largest new surface (panel, focus, per-display placement, click-through flash per press, two capture paths). Screen Recording prompts scare users (the 2024 Bartender ownership episode, forums.macrumors.com/threads/2428159). Does not solve the drift that most reports are about.
- **Size:** L, 4 to 6 sessions.
- **Test no-input:** new Debug hook `hb cmd overflow-panel` + `dump-state` listing proxies; a helper status-item app that writes a file when its menu opens, pressed via the proxy's AXPress; `screens` shot of the panel.

### B. Pinned sections (Hidden Bar owns the assignment)

```
                 +---------------- section table (UserDefaults) ----------------+
                 | com.raycast.macos -> visible   | org.swiftbar -> hidden       |
                 | com.1password     -> visible   | <never seen> -> default pref |
                 +-------------------^------------------------------+-----------+
                                     |                              |
  read on collapse (AX, unrestricted bar)                           v
    app relaunched since last read? -- yes --> ignore its position   allow-list =
                  | no                                               visible bundles
                  v                                                  |
    section differs from table? -- yes --> user dragged: update      v
                                                            MBAssessmentMode restriction
  Preferences "Menu bar apps" list --- edits table directly ---^     (macOS 27, direct)
```

Positions stop being the source of truth; they only edit the table when the app did not relaunch. The engine already tracks `launchedSinceRead` and a per-bundle `sectionMemory` (#468), so B extends shipped code. "Order" here means section membership: left-to-right order inside a section cannot be set without synthesising ⌘-drags (B+, rejected below).

| Issue | Fixed? | Why |
|---|---|---|
| #334, #107 | yes on 27 direct | Never-seen apps get the "new apps" default; relaunch positions ignored |
| #233 | partial | Membership kept across reboot, order inside a section not |
| #224 | yes on 27 | Always-hidden is a table value, not a separator state |
| #242 | yes on 27 | Nothing is pushed off-screen; "Reset all to visible" in Preferences |
| #327 | no | macOS 26 runs the legacy engine |
| #469 | partial | Kept visible if its owner has a bundle id; if it is a Control Center extra, Apple limit |
| #446, #470 | no | Apple keep-list; the "pause hiding" opt-in stays the answer |

- **27 / App Store:** direct build on 27 only. Same private API and AX as today, no new permission. App Store and legacy are unchanged.
- **Risk:** medium. Deeper reliance on `MenuBarClientCore` (a 27.x or 28 change makes hiding unavailable, failing open as today). An app that recreates its icon without relaunching (SwiftBar refresh) can look like a user drag. Migration: seed the table from `nativeVisibilityLastSections`.
- **Rejected sub-variant B+:** re-apply left-to-right order by posting synthetic ⌘-drags (the Ice approach). Needs event posting on top of AX, is timing-fragile, and has no confirmed working mechanism on 27.
- **Size:** M, 2 to 3 sessions.
- **Test no-input:** unit tests on the resolver and table with the existing fakes (`MenuBarEngineTests`); on screen, a helper status-item app with its own bundle id: launch while collapsed, quit, relaunch, `hb cmd collapse`, `dump-state` shows its table section unchanged; `hb cmd boundary <x>` stands in for a drag.

### C. Minimal patches only

```
 legacy engine (<= 26, App Store)          native engine (27, direct)
   + decouple always-hidden from             (as shipped in 1.11.2)
     "hide separators" (old M2)              + log + docs per new 27.x item
   + "Show everything" recovery command
 issues: close K8 reports as a documented limitation, link the ⌘-drag workaround
```

| Issue | Fixed? | Why |
|---|---|---|
| #334, #107 | partial on 27 (already), no on legacy | 1.11.2 shows a never-seen app until the next collapse |
| #233 | no | |
| #224 | partial | Legacy decouple fixes the separator coupling |
| #242 | partial | Recovery command; positions macOS persisted off-screen remain |
| #327 | no | |
| #469 | needs info | |
| #446, #470 | partial | "Pause hiding" opt-in, shipped |

- **27 / App Store:** no change. **Risk:** low code risk; product risk that K8 stays the top complaint. **Size:** S, 1 session. **Test:** unit tests for the legacy engine; legacy on-screen needs a macOS 26 Mac (this Mini is 27.2.1).

### Summary

| | A overflow bar | B pinned sections | C minimal |
|---|---|---|---|
| Fixes the drift cluster (#334 #107 #233) | partial | yes (27 direct) | no |
| Fixes always-hidden (#224 #242) | partial | yes (27 direct) | partial |
| Apple keep-list (#446 #470 #469) | partial | no | partial |
| New permission | Screen Recording (optional) | none | none |
| Works in App Store build | no | no | yes (legacy only) |
| Size | L | M | S |

## 4. Recommendation

**B now, a thin A later, C for legacy.** Build pinned sections on the macOS 27 direct build, then turn the existing notch overflow menu into a "hidden items" menu with app-icon proxies (no Screen Recording, no panel). Keep the legacy engine on patches.

Why: the drift cluster is the largest and oldest set of reports, and B is the only option that removes its cause, on the platform users are moving to, with code that is half there (`sectionMemory`, `launchedSinceRead`). A full second bar costs the most, needs a capture path that broke for Ice, Thaw and #358 on 26/27, and leaves drift unsolved. No option fixes #446/#470: that is Apple's keep-list, and saying so plainly beats a big build that implies otherwise.

Questions Han must answer:

1. **Is the macOS 27 direct build the primary product now**, with legacy (26 and older) and the App Store build on fixes only? B and its menu give nothing to App Store users.
2. **What is the default section for a never-seen app: visible or hidden?** #107/#334 want visible, #369 wanted hidden. And does a ⌘-drag keep editing the table, or only the Preferences list?
3. **Do we accept a deeper bet on the private `MenuBarClientCore` API and rule out Screen Recording** (app icons only in the hidden-items menu)? A "yes, with an opt-in" to Screen Recording reopens option A's image path.

## 5. Phased plan (recommended)

Each phase ships alone, behind the existing engine split, with `bash scripts/test.sh` green on both schemes plus a negative control.

**Phase 0, Live Activity and keep-list map (S).** Debug hook `dump-inventory` that writes every AX menu-bar item (owner, bundle, system id, frame) to JSON; ask #469 reporters for one dump on 27.3. Add any new system ids to the keep-list.
Done: a 27.3 dump is attached to #469 and the keep-list table in `MenuBarLayout.swift` names Live Activities as keepable or not.

**Phase 1, section table and "new apps" default (M).** Promote `sectionMemory` to the authoritative table; a read updates an app only if it did not launch since the last read; a "Show new menu bar apps" preference (default from Q2) covers never-seen apps.
Done: on this Mini, a helper app relaunched while collapsed, then a collapse, stays in its table section in `dump-state`; mutating the relaunch rule fails a unit test.

**Phase 2, Preferences "Menu bar apps" list (M).** One row per known app with a section popup and "Reset all to visible"; edits apply to the held restriction at once. Keeping always-hidden apps hidden while expanded means holding a restriction while expanded, which blocks the clock; the shipped lift path covers that case.
Done: setting a helper app to always-hidden in the list hides it with the bar expanded and "hide separators" off (#224 on 27); reset brings every app back without a relaunch (#242).

**Phase 3, hidden-items menu (S to M).** Generalise `NotchOverflowController` into a menu off the arrow for all Macs on 27: hidden-section apps with app icons; a click allows that bundle, AXPresses its item, and re-hides when its menu closes (the clock session pattern).
Done: `hb` triggers the menu, a proxy press opens the helper app's menu (the helper writes a marker file), and the bar is collapsed again within one check after it closes.

**Phase L, legacy patches (S, any time).** Decouple always-hidden from "hide separators" and add a "Show everything" recovery command for 26 and older.
Done: unit tests for both on the legacy engine pass and fail under mutation; a macOS 26 machine run is logged before release.

Not planned: a borderless second bar with item images, unless Q3 opens Screen Recording.
