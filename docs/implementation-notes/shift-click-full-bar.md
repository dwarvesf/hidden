# Shift-click full bar (#486): on screen from /Applications

| Step | Bar | `NSApp.activationPolicy` (dump-state / NSRunningApplication) | `fullBarThisExpansion` | Hidden Bar app menu | Result | Crops |
|---|---|---|---|---|---|---|
| a. Collapsed | collapsed | accessory / accessory | false | absent | baseline | `shift-click-full-bar-proof/a-collapsed-left.png`, `a-collapsed-right.png` |
| b. `toggle-full-bar-once` | expanded | regular / regular | true | absent: Helium kept the menu bar (`isActive` false) | policy proven; app menu NOT proven | `b-full-bar-once-left.png`, `b-full-bar-once-right.png` |
| c. `toggle` (collapse) | collapsed | accessory / accessory | false | absent | back to accessory | `c-collapsed-after-left.png`, `c-collapsed-after-right.png` |
| d. `toggle` again (plain) | expanded | accessory / accessory | false | absent | one-shot: no full bar on the next plain expand | `d-plain-toggle-left.png`, `d-plain-toggle-right.png` |
| f. Real Shift-click by Han (the only input in this run) | expanded | regular / regular | true | absent: System Settings kept the menu bar (`isActive` false, frontmost System Settings) | NOT a pass: policy switched, app menu not shown at capture time (no delay) | `real-click-expanded-left.png`, `real-click-expanded-right.png` |
| g. Collapse after the real click (hook) | collapsed | accessory / accessory | false | absent | back to accessory | `real-click-collapsed-left.png`, `real-click-collapsed-right.png` |
| e. `defaults read com.dwarvesv.minimalbar useFullStatusBarOnExpandEnabled` | | | | | `0` before the run, `0` after step d: never written | |

dump-state `useFullStatusBarOnExpand` read false at every step.

## Setup

- Build: `test/onscreen-proof-hooks` (develop with #486 and #487 merged, plus the Debug hooks), Debug-Direct, Developer ID signed, run from /Applications. The installed v1.12.0 (build 19) was renamed aside and renamed back after: CDHash identical, login items identical, prefs identical.
- Input: none. `toggle-full-bar-once` runs what Shift-click runs (`expandCollapseIfNeeded(fullBarOnce: true)`); `toggle` runs what a plain click runs. Truth: dump-state, `NSRunningApplication.activationPolicy` and `isActive`, the AX `AXMenuBar` items of Hidden Bar (width 0 at every step), full-display `screencapture -D1` plus crops.

## Finding: no app menu on macOS 27, even on a real click

- **Steps b and f: the policy turns `regular`, but Hidden Bar never becomes active**, so the frontmost app keeps the menu bar and the bar is not the "full" one. Step b came from the hook (Helium in front). Step f was a real Shift-click on the arrow, made through Screen Sharing with System Settings in front. Result: policy switched to `regular`, app menu not shown at capture time (captured with no delay after the poll saw the flag, at 01:36:46). Frontmost app (`lsappinfo front`) was sampled at that capture and again at the collapse capture about 2.5 s later: System Settings both times; it was not sampled continuously in between, so a shorter activation in that gap is not ruled out, but Hidden Bar was not frontmost at either sample. `NSApp.activate(ignoringOtherApps:)` is deprecated since macOS 14, and macOS 27 activation is cooperative: the request was not granted from a status item click either.
- The same path serves the stored "use the full menu bar on expand" setting, so that setting likely shows the same on macOS 27; not run here.
- How step f was told apart from noise: other Debug Hidden Bar builds (test hosts of a parallel session) also answer the broadcast hook and wrote the same dump file, which gave two false triggers. Only this build's dump has `fullBarThisExpansion`, so the trigger was that key being true; the capture retried the dump until that key was present.

## Not proven here

- The app menu in the menu bar after a Shift-click: not seen on macOS 27 (finding above). Shift detection itself is proven on screen by step f (`fullBarThisExpansion` true after a real click).
- A real click with Hidden Bar's arrow clicked locally rather than through Screen Sharing.
