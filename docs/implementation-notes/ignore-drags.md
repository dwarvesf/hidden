# Ignore drags (#487): on screen from /Applications

| Proof | Lock | Magenta px | Pinned / observed | Result | Crop |
|---|---|---|---|---|---|
| Settings, Menu Bar Apps, light | off | | | checkbox shown, unchecked | `ignore-drags-proof/settings-off-light.png` |
| Settings, Menu Bar Apps, dark | off | | | checkbox shown, unchecked | `ignore-drags-proof/settings-off-dark.png` |
| Settings, Menu Bar Apps, light | on | | | checkbox checked; `pinnedDragLocks` holds the probe | `ignore-drags-proof/settings-on-light.png` |
| Settings, Menu Bar Apps, dark | on | | | checkbox checked | `ignore-drags-proof/settings-on-dark.png` |
| Relaunched, then one read, boundary left of the probe | on | 1024 | visible / visible | shown | `ignore-drags-proof/lock-on-2-read-visible-side.png` |
| Boundary moved right of the probe, read again | on | 1024 | visible / hidden | stays shown: the move is ignored | `ignore-drags-proof/lock-on-3-read-hidden-side.png` |
| Relaunched, then one read, boundary left of the probe | off | 1024 | visible / visible | shown | `ignore-drags-proof/lock-off-2-read-visible-side.png` |
| Boundary moved right of the probe, read again | off | 0 | hidden / hidden | drifts to hidden: the move is taken as a drag | `ignore-drags-proof/lock-off-3-read-hidden-side.png` |

A third read after each move gave the same pixels and sections (stable).

## Setup

- Build: `test/onscreen-proof-hooks` (develop with #486 and #487 merged, plus the Debug hooks), Debug-Direct, Developer ID signed, run from /Applications. The installed v1.12.0 (build 19) was renamed aside and renamed back after: CDHash identical, login items identical, prefs identical (test key `pinnedDragLocks` removed after the re-import).
- Probe: a status-item app with a solid magenta 16 pt icon (`foundation.dwarves.pinprobeb`, Developer ID signed), in /Applications. 1024 magenta px = the whole icon at 2x. The menu bar draws it at about sRGB 0.94, 0.35, 0.98, so the count takes r > 0.88, g < 0.45, b > 0.88.
- Input: none. Only the Debug hook (`com.dwarvesv.minimalbar.debug.command`), `open -g`, AX reads and full-display `screencapture -D1` plus a crop (`screencapture -R` fails on macOS 27: "could not create image from rect").
- Settings window: the `settings` hook orders it front without activating the app and draws it as key, as the snapshots do; light and dark are set on the window only, not the system. Window capture: `menubar-shot.sh --window "Menu Bar Apps"`. The pinned table was narrowed to the probe for these shots so the window does not list this Mac's apps.

## Sequence and why

Per run: `pin probe=visible`, `drag-lock probe=on|off`, quit and relaunch the probe, one read, `boundary` to the right of the probe, one more read. Truth per read: dump-state `pinnedSections`, `observedSections`, `launchedSinceRead`, plus the magenta count.

- **A relaunch alone cannot show the lock.** Right after a relaunch the probe is in `launchedSinceRead`, and the resolver never takes a position from a launched app, lock or no lock. The read after the relaunch clears it (dump-state: `launchedSinceRead` without the probe at both reads); the boundary move after that is the drag stand-in.
- **A read is a collapse from an expanded bar.** `withLayout` reads fresh only while no restriction is held, so each read is `expand` then `collapse`. The read sees the expanded bar: there the probe sat at AX x 854 (arrow 921), against 930 (arrow 997) while collapsed. So the boundary values are 840 (probe on the visible side) and 900 (hidden side), not values from the collapsed bar.
- macOS put this probe left of the arrow after every relaunch (observed `hidden` before any boundary). The boundary hook therefore had to move the probe to the visible side first, so that the second read is a real change.

## Not proven here

- A real icon recreation without a relaunch (SwiftBar refresh): stood in for by the boundary move, as in `pinned-sections.md`.
- Toggling the checkbox by a click: the `drag-lock` hook runs the same store call (`LiveMenuBarAppsStore.setIgnoresDrags`), and the window was redrawn from the stored value.
