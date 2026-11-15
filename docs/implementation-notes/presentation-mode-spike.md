# Presentation mode (F4) spike: what macOS lets Hidden Bar know

Goal: `docs/megagoals/next-features/goals/03-f4-spike.md`. Base `develop` at `f2dec5c`. Probed on macOS 27.2.1 (26B131), Mac mini, two external displays, Xcode SDK `MacOSX.sdk` (Swift 6.4.2). Read-only: no display change, no slideshow, no share, no Keynote or Zoom launched, no keystrokes, no pointer input, Hidden Bar not touched, no permission requested.

This file is force-added: `.gitignore` keeps `docs/implementation-notes/` local.

## Summary

| # | Question | Feasibility |
|---|---|---|
| 1 | Display mirroring and a new display, no Screen Recording | Mirroring: feasible. "A display was added": feasible to see, but not a safe trigger (see 1) |
| 2 | Keynote or PowerPoint slideshow, Accessibility only | Unknown: the signals exist and need no new permission, but no real slideshow was observed (rules forbid starting one) |
| 3 | Screen share or recording by another app | Not feasible: no public signal, with or without Screen Recording |
| 4 | Privacy indicator rule | Confirmed; mic and camera are detectable without any permission, screen recording is not |
| 5 | Two allow-lists, swap and fail open | Feasible, with one structural change: every re-activation must come from one desired-list function (see 5) |

No trigger needs Screen Recording or a new TCC permission. Accessibility is already required by the direct build (`inventory.isAuthorized`).

Probe method. The shell that runs probes holds Screen Recording and Accessibility (`CGPreflightScreenCaptureAccess` true, `AXIsProcessTrusted` true), which would hide the effect of a missing permission. Each probe was therefore run twice: directly, and as a throwaway `launchctl submit` job (no TCC grants; removed after each run). Probe sources live in `~/.cache/hidden-bar/spike-probes/`, outside the repo.

## 1. Display mirroring and a new external, projector or AirPlay display

API:
- `CGDisplayIsInMirrorSet`, `CGDisplayIsInHWMirrorSet`, `CGDisplayMirrorsDisplay`: `CoreGraphics.framework/Headers/CGDisplayConfiguration.h` lines 310, 322, 329 ("Return true if the display is in a mirroring set").
- `CGDisplayRegisterReconfigurationCallback` (same header, line 235) with `kCGDisplayMirrorFlag` (line 220) and `kCGDisplayAddFlag` (line 216) in the callback flags.
- `NSApplication.didChangeScreenParametersNotification` (`AppKit.framework/Headers/NSApplication.h` line 652). Hidden Bar already observes it (`StatusBarController.swift` line 84, `handleScreenParametersChanged`), so mirroring needs one more read there, no new observer class.

Probe `p1_displays.swift` (direct run):

```
online displays: 2
display 3: main=true builtin=false active=true ...
  inMirrorSet=false inHWMirrorSet=false mirrorsDisplay=0 primaryOfMirror=3
display 1: main=false builtin=false active=true ...
  inMirrorSet=false inHWMirrorSet=false mirrorsDisplay=0 primaryOfMirror=1
NSScreen.screens count: 2
CGDisplayRegisterReconfigurationCallback result: 0 (0 = success)
callback fired during 3 s idle window: 0
```

The calls return real values and the callback registers without a prompt. The probe did not mirror anything (rule), so the `true` branch is read from the header, not observed here.

Findings that shape the design:
- **Mirroring is a clean signal.** `CGDisplayIsInMirrorSet(id)` for any online display, re-evaluated on the reconfiguration callback and on the screen-parameters notice. Presenting by mirroring to a projector or an AirPlay "mirror" yields a mirror set.
- **"A display was added" is not a safe trigger.** This Mac has no built-in display; both screens are external (`builtin=false`), and a hot-plugged monitor is an ordinary event. An extended AirPlay display looks the same as an extended desk monitor through public API (vendor and model numbers only, no transport flag). Only mirroring means "the room sees what I see". The Entry board lists "AirPlay display added" as automatic; the Settings board only promises "When a display is mirrored". Ship the Settings board's version.
- The callback fires with `kCGDisplayBeginConfigurationFlag` first and again when the change lands. Read mirror state on the second call, not the begin call.

Feasibility: mirroring feasible; a bare new external or AirPlay display not feasible as an automatic trigger.

## 2. Keynote or PowerPoint slideshow, Accessibility only

Keynote is installed here (`com.apple.iWork.Keynote`), not running. PowerPoint is not installed (LibreOffice only), so nothing about PowerPoint was observed; its bundle id (`com.microsoft.Powerpoint`) is not verified here.

Window titles need Screen Recording. Probe `p2_windows_ax.swift`, the same binary run two ways, on the same 23 on-screen windows:

```
direct (Screen Recording + Accessibility held)      launchd job (neither held)
ownerName=23 ownerPID=23 bounds=23                  ownerName=23 ownerPID=23 bounds=23
non-empty window name=22                            non-empty window name=2   (system-owned only)
AX windows read: error=0                            AX windows read: error=-25211 (API disabled)
  role=AXWindow subrole=AXStandardWindow
  AXFullScreen=0
```

So, without Screen Recording: owner name, owner PID, bounds and layer stay readable; names do not (`CGWindow.h`: "If present, the name of the window"). Without Accessibility: every AX read fails with `kAXErrorAPIDisabled` (-25211), which Hidden Bar already treats as "needs Accessibility".

Signals available with no new permission:

| Signal | API | Probe result | Weakness |
|---|---|---|---|
| Frontmost app | `NSWorkspace.shared.frontmostApplication.bundleIdentifier` | `net.imput.helium` | none |
| Full-display window by owner | `CGWindowListCopyWindowInfo` owner PID, bounds, layer (no names) | `p3_fullcover`: with no grants it lists `Dock layer=20`, `Finder layer=-2147483603`, `WindowManager`, `Window Server` full-size windows per display | a slideshow window shape (bounds, layer) on 27.2 was not observed |
| Full-screen window state | AX `AXFullScreen` on the focused window | `0` on a normal window | `AXFullScreen` is not a constant in the SDK headers (`AXAttributeConstants.h` has only `kAXFullScreenButtonAttribute`); and a Keynote editor in macOS full screen also reads true |
| Display-sleep assertion by the app | `IOPMCopyAssertionsByProcess` (`IOKit/pwr_mgt`) | `p4_pm`: succeeds in both contexts, lists type, name and pid, e.g. `pid 838 PreventUserIdleDisplaySleep "com.apple.universalcontrol.preventDisplaySleep"` | also held by video players and calls; whether Keynote holds one during Play was not observed |

Read: a rule such as "frontmost app is Keynote AND it owns a window covering a whole display above layer 0" is buildable from CGWindow owner and geometry plus the frontmost app, with no new permission. It cannot be proven here because proving it needs a running slideshow, which the rules forbid. The wave verifier can settle it with one live check: start a Keynote slideshow on a scratch deck and record the CGWindow owner, layer and bounds, the AX focused window attributes, and the Keynote display-sleep assertion.

Feasibility: unknown, not disproven. Needs no permission beyond the Accessibility Hidden Bar already holds. PowerPoint: unknown, and unverifiable on this Mac.

## 3. Screen sharing or recording by another app

Expected "no"; confirmed.

- No signal in the SDK. A search of `AppKit`, `CoreGraphics` and `ApplicationServices` headers for `isCaptured`, `isScreenCaptured` and `screenIsCaptured` returns nothing (`UIScreen.isCaptured` is iOS only). `CaptureActivityMonitor.swift` line 37 says the same: "Screen recording has no public equivalent, so it is not covered."
- `kCGWindowSharingState` (`CGWindow.h` line 78) is the window's own sharing type, not "someone is capturing it". Probe: `{0: 21, 1: 2}` without Screen Recording, `{1: 23}` with it, on the same windows with nothing shared, so it varies with the caller, not with capture.
- `ScreenCaptureKit` gives redacted information without TCC (`SCShareableContent.h` line 157) and has no "is anything capturing" call.
- Process presence is no signal: `replayd` has been running for 5 days on this Mac (`ps`: `715 05-18:11:16 /usr/libexec/replayd`) with no share known to be active.
- Zoom, Meet and Teams hold the microphone during calls, which the capture rule (4) already covers, but a muted or listen-only share has no signal. #437 confirms: "Screen recording has no public signal, so it isn't covered."
- A scan of the Control Center and SystemUIServer menu extras by AX returned no readable bar (`AXExtrasMenuBar` error -25212) on this Mac; no route found in the time box.

Feasibility: not feasible (no public signal; not made possible by Screen Recording either, as nothing in the SDK reports capture state). Presentation mode must never claim to detect sharing; the Edge board already says so.

## 4. The privacy indicator rule

Confirmed from code and #437:
- Every restriction Hidden Bar holds is macOS assessment mode (`MBAssessmentModeAssertion`, `HBNativeVisibilityShim.m`). `NativeVisibilityEngine.swift` header lines 44 to 50: assessment mode "hides the capsule naming the app that uses the microphone or camera (#432, #437; the dot in the screen corner stays)".
- #437 comment: origin `0` is accepted but ignores the allow-list, origin `2` is rejected, so no origin gives the allow-list without assessment mode. The strict presentation list is the same mechanism and has the same side effect.
- Correction to the Edge board copy: it says macOS hides "its camera and microphone light". The measured behavior (#437) is that the menu-bar capsule naming the app is hidden and the corner dot stays. The reporter's table also lists the screen-recording indicator as hidden, and that one cannot be paused for, because it cannot be detected. Reword the pause copy to "the capsule that names the app using the camera or microphone", and note that a screen-share indicator can be hidden while presentation mode holds a list.
- Detection needs no permission. `CaptureActivityMonitor.isActive` (line 69): CoreAudio `kAudioProcessPropertyIsRunningInput` per process (macOS 14.2+), CoreMediaIO "running somewhere" per camera. Probe `p5_capture` in both contexts (no mic or camera grant): 41 audio process objects read, 0 running input, 2 CMIO devices, 0 running; no prompt. #437 also records a Voice Memos recording detected by a hardened app with no audio-input entitlement.

Pause rule for presentation mode (differs from the 1.11.2 rule, which is edge-triggered and lets a later collapse hide while capture continues):

| Event | Action |
|---|---|
| Capture starts while a presentation list is held | Release it at once (`revealAll` path), state Paused, capsule reads "Paused" and explains why once per session |
| Presentation turns on while capture is already active | Never hold; go straight to Paused |
| Capture stops | Wait 2 to 3 seconds (a mic that flaps for a second must not flap the bar), re-evaluate the triggers, hold again only if one still applies |
| Asymmetry | Pausing is immediate; resuming is delayed. Any doubt resolves to visible |

It must be level-triggered: every activation and every re-evaluation reads `captureActivity.isActive` at that moment, not a stored `isCaptureActive` edge. Caveat: apps that keep the microphone open all day (dictation tools, per the engine comment at line 48) keep presentation mode permanently Paused; the Settings footnote already tells users hiding pauses while the camera or microphone is on.

## 5. Two allow-lists: swap and fail open (read only, no live test)

What the engine does today (`NativeVisibilityEngine.swift`):

| Behavior | Where | Verdict |
|---|---|---|
| New assertion is activated before the old is dropped | `activate(allowing:)` lines 403 to 429 (`old?.invalidate()` after the new one is stored) | Safe for a swap: no flash of the whole bar |
| A late success from a superseded activation is invalidated | line 409, `generation == self.generation`, else `stale.invalidate()` | Safe: the wrong list cannot land after a newer one |
| Failure fails open | lines 422 to 427, `releaseAssertion()` then `completion(false)`; callers set `state = .expanded` | Correct for presentation too, but it must be surfaced (see below) |
| Crash or quit lifts the restriction | `NativeVisibilityBridge.swift` line 10 ("until this process exits, when macOS drops it"), `Handle.deinit` line 57; brief section 2 ("It lifts when Hidden Bar exits, so a crash fails open") | Taken from the repo's own record; not re-tested here, as a live test is forbidden. There is no `willTerminate` handler (`rg willTerminate hidden` is empty), so quit relies on process exit and `deinit` |

Gaps found. These are the points where a second list would silently be lost or leak:

1. **`allowLaunchedAppsIfIdle` (lines 657 to 669) would swap the strict list back to the normal one.** It computes `wanted = layout.bundles(in: shownSections)` from `state` alone and re-activates when it differs from `assertionBundles`. Any app launch while presenting (it fires for every agent app start) would replace the presentation list with the normal collapsed list and reveal the user's visible-section apps. This is the main "wrong list held" risk.
2. **`revealAll()` is the fallback of `applyExpandedPresentation` (lines 302 to 323)** when `layout` is nil, Accessibility is off or the app is outside Applications. While presenting, that reveals the sensitive apps. A deliberate presentation fail-open is fine; an accidental one through this fallback is not.
3. **`pressClock` (lines 546 to 587) lifts the restriction for up to `clockLiftHardCap` = 0.6 s** and then re-activates `assertionBundles`. During presentation that is a visible flash on the shared screen, and `notificationCenter.clockClicked` expands the bar, which would also show Notification Center content to the room.
4. **`captureActivityDidChange` (lines 459 to 471)** is edge-triggered and expands once. Presentation needs the level-triggered rule in 4.
5. **`activate` always sends `Self.systemItemsToKeep` (0..<64) plus the own bundle id (lines 59, 406).** The "clock and battery only" list needs the item ids for those two, which the repo does not name (a search for the mapping finds none). #437 says 0..<64 resolves to nine named items (battery, bluetooth, clock, displays, keyboard, volume, wifi, screenMirroring, primaryBentoBox). Measuring which ids are clock and battery needs a live assertion, so it was not done here.
6. **Overlap semantics are unmeasured.** During a swap two assertions are live. MenuBarAgent "combines the origins of all live restrictions" (#437); how it combines two allow-lists with the same origin (union or intersection) was not measured. Either way the swap moves between two states the user chose, so nothing sensitive is exposed that was not already exposed, but verify with one live toggle.

## Design note for SG-06

### Automatic triggers to ship

- Ship: **display mirroring** (`presentationAutoMirrorEnabled`). Evaluate on the reconfiguration callback and the screen-parameters notice, from `CGDisplayIsInMirrorSet` over the online display list. Do not ship "display added" or "AirPlay display added" (1).
- Conditional: **Keynote slideshow** (`presentationAutoSlideshowEnabled`). Build the key and row only if the wave verifier's live Keynote check (2) passes, with the rule frontmost app plus a whole-display window owned by it, and Keynote only. If it fails, drop the key and the row; the contract allows that ("only if the spike says automatic is feasible"). PowerPoint is out unless someone with it installed validates the same rule.
- Manual always: `presentationShortcut`, the arrow menu item, and the Shortcuts action (the Edge board's answer for Zoom, Meet and QuickTime, which cannot be detected).
- Trigger bookkeeping: each automatic trigger records why presentation mode is on; it ends only when its own cause ends. A manual start ends only by a manual stop. The Light board's "Started because 'Meeting Room TV' is mirrored. Ends when mirroring stops." needs the display name from `NSScreen.localizedName`, which reads without any grant (`p1_displays` as a launchd job: `screen name="Studio Display (1)"`, Screen Recording false).

### Capture pause

Exactly the table in 4, implemented as a level-triggered state `paused(reason: capture)` inside the presentation controller, not by reusing `captureActivityDidChange`. Pause on start is immediate, resume after a 2 to 3 second quiet period, start-while-active goes straight to Paused. Copy: say the capsule naming the app, not "the light" (4).

### Two lists: one desired-list function and fail open

```
 triggers (mirror, slideshow, manual, capture, bar state, layout, sensitive set)
                              |
                              v
              desiredHold() -> nil | List(mode, systemItems, bundles)
                              |
                       reconcile()   <- the ONLY caller of activate()/releaseAssertion()
                              |
        same signature as held? -- yes --> nothing
                              | no
                              v
        activate(new) -> success: store, then invalidate old
                      -> stale generation: invalidate the new one
                      -> failure: release, state visible, surface "Couldn't hide"
```

Rules for SG-06:

1. One function computes the list from current state (not from the event that fired). `desiredHold()` returns nil when presentation is Paused, off, or the engine is unavailable.
   - Presentation off: today's lists (collapsed: visible bundles; expanded: visible and hidden).
   - Presentation on, collapsed: own bundle id plus clock and battery only.
   - Presentation on, expanded (arrow click): visible and hidden bundles minus `presentationSensitiveApps`, so "Hidden icons show, sensitive ones do not". The sensitive set must be removed from the visible section too if the user put one there.
2. Compare with a signature of the whole held list (mode, system items, bundles), not `assertionBundles` alone, or a swap between two lists with the same bundles is skipped.
3. `allowLaunchedAppsIfIdle` and `pressClock`'s restore must call `reconcile()` instead of building their own list (gap 1, 3). While presenting, a clock click does nothing special: no lift, no expand.
4. Never fall back to `revealAll()` while presenting because layout is missing: the strict list needs no layout (only the own bundle and system items), so it can be held without a read. The expanded-presenting list needs a layout; if there is none, stay on the strict list rather than revealing.
5. Fail open stays: an activation failure releases the restriction and the controller shows a "Couldn't hide" state on the capsule, since "presenting" must not stay visibly on while icons are in fact shown.
6. Release explicitly on quit (add a `willTerminate` observer) as well as relying on process exit. On launch do not resume a persisted `presentationModeActive` blindly: re-evaluate triggers; a manual session does not survive a relaunch, so a crash plus relaunch never re-hides on its own.
7. Tests, in `HiddenBarTests` with the fake `NativeVisibilityProviding`: out-of-order completions across a swap; failure on the second activation; app launch while presenting (gap 1); capture start, stop and 1 s flap; clock click while presenting; layout nil while presenting; quit releases.
8. Live checks left to the wave verifier (host-state protocol): the clock and battery item ids, the overlap behavior of two assertions, and the Keynote slideshow signals.

Verdict: automatic (display mirroring)
