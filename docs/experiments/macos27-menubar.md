# Experiment: what macOS 27 exposes for hiding menu-bar icons

**Status:** exploration / not shipped. **Does NOT hide anything.** Read-only probe +
findings, to scope a future macOS-27 hide mechanism (#360, managed-overflow epic #366).

PR #370 makes Hidden Bar detect-and-degrade on macOS 27 (the length-inflation trick is
dead there). This note answers the next question: **is there any path to actually hide
menu-bar icons on macOS 27, and at what cost?** It is the recon the backlog's Option D
("managed-overflow / second-bar redesign, likely via Accessibility") needs before design.

The probe (`experiments/macos27-menubar-probe.swift`) only READS state — it never moves,
presses, hides, or modifies anything.

```sh
swiftc experiments/macos27-menubar-probe.swift -o /tmp/mbprobe && /tmp/mbprobe
```

## Findings (macOS 27.0, build 26A5368g)

### 1. A new agent owns the menu bar, and per-item windows are gone

`MenuBarAgent` (`/System/Library/CoreServices/MenuBarAgent.app`) is running and owns the
status-item area. In the **public** `CGWindowListCopyWindowInfo` list, the menu-bar band
contains a single full-width `Window Server` window — there are **no per-item status
windows** anymore. On macOS ≤ 26 each status item was its own small `CGWindow`; that is
exactly what the length-inflation trick and window-capture tools (Ice/Thaw/Bartender)
relied on, and it is gone. This matches the BetterTouchTool/Thaw reports (`CGSGetProcessMenuBarWindowList`
now returns one window).

### 2. Accessibility still ENUMERATES items and their positions

`AXUIElementCreateApplication(MenuBarAgent).AXExtrasMenuBar` returns an `AXMenuBar` with
the foreign status items as children, with readable positions:

```
AXExtrasMenuBar: role=AXMenuBar childCount=5
  [0] pos=(1307,0)  [1] pos=(1201,0)  [2] pos=(1387,0)  [3] pos=(1345,0)  [4] pos=(1265,0)
```

So a hide mechanism CAN discover items and where they are — but only with **Accessibility
permission** (`AXIsProcessTrusted` must be true; it is incompatible with the App Sandbox).

### 3. ...but Accessibility offers NO primitive to hide, move, or reorder them

Inspecting the items' AX capabilities is where the public path ends:

| Owner | role / subrole | `AXPosition` settable | actions |
|---|---|---|---|
| **MenuBarAgent** (the modern bar) | `AXGroup` / `AXHostingView` (SwiftUI) | **false** | **`[]`** (none) |
| `SystemUIServer` (legacy extra) | `AXMenuBarItem` / `AXMenuExtra` | **false** | `AXPress`, `AXCancel` |

The modern macOS-27 items are read-only SwiftUI hosting views: **no settable position, no
actions at all** — you cannot reposition them (to shove them off-screen) or invoke any
hide. Legacy `AXMenuExtra`s can still be `AXPress`ed (to open their menu) but also can't be
repositioned. There is no `AXHide`, no settable order, no public lever.

## Conclusion

On macOS 27, **public APIs let you READ the menu bar but not REARRANGE it.** No
public-API hide mechanism exists. Restoring real hiding requires a **private** path —
the SkyLight/`CGS*` calls or the `MenuBarAgent` XPC/Stage-Manager-era interfaces that the
maintained tools reverse-engineered — which:

- needs **Accessibility** (and historically Screen-Recording) permission → cannot run in
  the current sandboxed, permission-free build, and is not App-Store-shippable as-is;
- is **unofficial and unstable** — Apple can (and, per the BetterTouchTool author, may)
  change or block it during the macOS 27 beta;
- is a deliberate architecture decision, not a drop-in — exactly the maintainer's Option D
  (#366) "managed-overflow / second-bar redesign, likely via Accessibility."

### Recommended path

1. Treat #366 as the home for real macOS-27 hiding; this recon scopes its public-API
   ceiling (read-only) and its private-API requirement.
2. Reference implementation that already hides on macOS 27 Golden Gate: **`stonerl/Thaw`**
   (MIT, the maintained Ice fork) — see its issue #687. It uses the new menu-bar API +
   Accessibility, in a non-sandboxed build, and is still iterating on reliability.
3. Existing in-repo starting points for the second-bar/overflow UI: community PRs **#358**
   (separate hidden-items bar) and **#350** (notch overflow).
4. If pursued in this repo, the hide module must be isolated behind a build flag
   (e.g. `EXPERIMENTAL_MENUBAR_27`) and a separate **non-sandboxed** target/entitlements,
   so the default sandboxed/MAS build and PR #370's clean posture stay untouched.

PR #370 (detect-and-degrade) remains the correct shipping behavior until such a mechanism
is designed and accepted.
