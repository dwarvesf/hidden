# overflow-probe

One command that re-measures how macOS draws the menu bar overflow « for status items. Hidden Bar's macOS 27 work depends on this behavior and it can change with any macOS update, so re-run it after one.

The probe creates N status items (`P0`..), waits for layout, then reports per item its window frame, occlusion and screen, plus the verdict of the app's own `SystemOverflowMatcher.isItemInSystemOverflow` against `SystemOverflowIndicator().buttons`. `run.sh` compiles `main.swift` together with the real `SystemOverflowIndicator.swift` (and the two layout files it needs to build standalone), not a copy, so the probe and the app cannot drift.

## Expected result (measured on macOS 27.2.1)

| Fact | What the probe should show |
|---|---|
| A full bar | MenuBarAgent shows an AXButton with AXIdentifier `menu-bar-overflow-indicator` (`-expanded` when open). One per display. Listed under `« buttons`. |
| An overflowed item's window | Either stacked under the « with `occlusionState` lacking `.visible` (`in « under «[n]`), or parked at frame origin (0,-30) with `window.screen == nil` (`in « parked`). |
| Notched display (for example 1280x832 on a 13" Air) | No status item lands behind the notch: `behind notch 0`. `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` bound it. Overflow goes to the « right of the notch. |
| Which items overflow first | Not simply leftmost. In one run newer items went into the « while an older app's item stayed. Compare the `on bar` and `in «` lists against creation order. |
| Classifier | `classification vs own window state: N/N placed items agree`. Exit 0. |

If a macOS update breaks one of these, the matching line changes (no « found, items stacked but not classified, items behind the notch, mismatches) and `scripts/overflow-probe/run.sh` exits 1.

Summary line, the last line of output:

```
on bar N, in « M, behind notch K
```

`, unplaced U` is appended when some windows never got a bar position (height 0, not visible, on a screen). That is not overflow: the bar is not laying items out, or something hides them. The usual cause is Hidden Bar itself running, since it hides other apps' items natively on macOS 27. The probe prints a warning when it sees Hidden Bar, so quit it first.

## Run it

Locally:

```bash
scripts/overflow-probe/run.sh --count 30
```

On another Mac (needs `mini-run` and ssh to the alias; the bundle is built for this Mac's architecture, so the target must match):

```bash
scripts/overflow-probe/run.sh --host ALIAS --count 30
```

`--host` ships `OverflowProbe.app` with `mini-run --host ALIAS --with` and launches it there through `open -W -n`, so it runs in that Mac's GUI session. It writes `~/.cache/hidden-bar/overflow-probe/out.txt` on the target and prints it.

| Flag | Default | Meaning |
|---|---|---|
| `--count N` | 30 | status items to create |
| `--out FILE` | none | also write the report to FILE |
| `--settle SECONDS` | 3 | wait for layout before reading |
| `--notch-mode` | off | switch the main display to the same-width HiDPI mode that includes the notch |
| `--notch-width POINTS` | none | with `--notch-mode`: pick the taller mode of this point width (for example 1280) instead of the current mode's pixel width |
| `--build-only` | off | compile and sign, do not run |

Exit codes: 0 ok, 1 classification disagrees with an item's own window state, 3 Accessibility not trusted.

## Accessibility

Reading the « goes through Accessibility. Locally the binary runs directly, so it uses the terminal's Accessibility permission. With `--host` it runs as its own app, so grant `OverflowProbe` once in System Settings > Privacy & Security > Accessibility on that Mac. Without it the report says `accessibility trusted: false` and finds no « (every overflowed item then reads as on the bar). An ad-hoc signature is tied to the exact binary, so a rebuilt probe may need the grant again.

## Warnings

- The probe briefly fills the real menu bar with its own items, for about 4 seconds, then removes them. Other apps' items can shift while it runs.
- `--notch-mode` also switches the main display's resolution for a few seconds (`CGCompleteDisplayConfiguration` with `.forAppOnly`, so macOS restores the mode when the probe exits). The screen flickers. If a run is killed, the mode returns when the process is gone.
- Run it with Hidden Bar quit, or the items may never get a bar position.
