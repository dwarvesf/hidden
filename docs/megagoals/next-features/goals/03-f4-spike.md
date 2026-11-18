# SG-03 F4 spike: can Hidden Bar know it is presenting?

Model: sonnet
Effort: high
**Branch:** docs/presentation-mode-spike
Wall budget: 60 minutes (time box; stop at the box and write what is known)

Read first: `../CONTRACT.md`; boards `Present-Entry`, `Present-Light`, `Present-Edge`, `Present-Settings`; `hidden/Features/StatusBar/Engine/Native/CaptureActivityMonitor.swift`; `docs/briefs/DECISION-BRIEF-366-overflow-bar.md`; issue #437.

Done = `docs/implementation-notes/presentation-mode-spike.md` merged, answering each question with evidence (API name, doc link or header line, a probe command and its real output on this Mac), and ending with one verdict line: `Verdict: automatic (<triggers>)` or `Verdict: manual only`.

Questions:
1. Display mirroring and a new external, projector or AirPlay display: detectable without Screen Recording? (`CGDisplayIsInMirrorSet`, `CGDisplayRegisterReconfigurationCallback`, `NSApplication.didChangeScreenParametersNotification`.)
2. A Keynote or PowerPoint slideshow in front: detectable with Accessibility only (AX window role/subrole, frontmost app, full-screen state), without window titles from `CGWindowListCopyWindowInfo` (titles need Screen Recording)?
3. Screen sharing or recording by another app (Zoom, Meet, Teams, QuickTime, the system share indicator): any public signal without Screen Recording? Expected answer: no; prove or disprove.
4. The privacy indicator rule: confirm from `CaptureActivityMonitor` and #437 that a held restriction hides Apple's camera and mic dot, and specify how presentation mode pauses while capture is active.
5. Two allow-lists: can `NativeVisibilityEngine` swap to a stricter list and back without leaving the wrong one held, and does a crash lift it (fail open)? Read the engine; no live test.

## Rules

- Probes are throwaway Swift or JXA scripts under the scratch clone, outside the repo tree; nothing probe-related is committed.
- Read-only probes only: never change display arrangement or mirroring, never start a slideshow or a share, no keystrokes or pointer input.
- If a trigger would need Screen Recording or any new TCC permission, mark it "not feasible without <permission>" and move on; do not build anything.
- Docs-only PR (CI skips docs-only changes; say so in the PR body).

## Touches

- docs/implementation-notes/presentation-mode-spike.md
