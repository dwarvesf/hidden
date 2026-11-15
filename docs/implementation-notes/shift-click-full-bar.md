# Shift-click full bar (#486): on screen from /Applications

| Step | Bar | `NSApp.activationPolicy` (dump-state / NSRunningApplication) | `fullBarThisExpansion` | Hidden Bar app menu | Result | Crops |
|---|---|---|---|---|---|---|
| a. Collapsed | collapsed | accessory / accessory | false | absent | baseline | `shift-click-full-bar-proof/a-collapsed-left.png`, `a-collapsed-right.png` |
| b. `toggle-full-bar-once` | expanded | regular / regular | true | absent: Helium kept the menu bar (`isActive` false) | policy proven; app menu NOT proven | `b-full-bar-once-left.png`, `b-full-bar-once-right.png` |
| c. `toggle` (collapse) | collapsed | accessory / accessory | false | absent | back to accessory | `c-collapsed-after-left.png`, `c-collapsed-after-right.png` |
| d. `toggle` again (plain) | expanded | accessory / accessory | false | absent | one-shot: no full bar on the next plain expand | `d-plain-toggle-left.png`, `d-plain-toggle-right.png` |
| e. `defaults read com.dwarvesv.minimalbar useFullStatusBarOnExpandEnabled` | | | | | `0` before the run, `0` after step d: never written | |

dump-state `useFullStatusBarOnExpand` read false at every step.

## Setup

- Build: `test/onscreen-proof-hooks` (develop with #486 and #487 merged, plus the Debug hooks), Debug-Direct, Developer ID signed, run from /Applications. The installed v1.12.0 (build 19) was renamed aside and renamed back after: CDHash identical, login items identical, prefs identical.
- Input: none. `toggle-full-bar-once` runs what Shift-click runs (`expandCollapseIfNeeded(fullBarOnce: true)`); `toggle` runs what a plain click runs. Truth: dump-state, `NSRunningApplication.activationPolicy` and `isActive`, the AX `AXMenuBar` items of Hidden Bar (width 0 at every step), full-display `screencapture -D1` plus crops.

## Not proven here

- **The app menu in the menu bar (step b).** The policy turned `regular`, but `NSApp.activate(ignoringOtherApps:)` did not make Hidden Bar active: the frontmost app (Helium) kept the menu bar. macOS 27 activation is cooperative; a hook call arrives as a distributed notification, not as user input to Hidden Bar, so the system has no reason to hand over activation. A real Shift-click is input to Hidden Bar's status item and should be allowed to activate it. Proving that needs one real Shift-click, which this run did not send.
- Shift detection on a real click (`ExpandCollapseActionResolver.isShiftPressed`) is covered by `ExpandCollapseActionTests`, not on screen.
