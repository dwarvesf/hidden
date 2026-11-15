# Decisions

Mid-run decisions, one line each.

- Opt-in defaults: every new Bool key defaults to false and `newAppDefaultSection` defaults to Show It, so 1.13.0 with default settings behaves like 1.12.0. The boards suggested Ask Me and two gestures on; the run brief says opt-in, which wins.
- F1 has no separate on/off switch: an unset shortcut is the off state, as on the Palette-Settings board.
- Workers never launch the app live; offscreen snapshots plus wave-verifier hooks runs replace live checks.
- The 1.13.0 smoke test is static (codesign, spctl, stapler) because a Release build launched outside /Applications acts on the real install.
- `presentationSensitiveApps` is stored as a dictionary so the import whitelist needs no new Kind.
- Presentation mode follows the 1.12 capture rule, not a whole-capture pause: with "show the whole bar when a camera or microphone turns on" on, a fresh capture start while presenting lifts once and shows Paused with a Hide again action, a capture already on when the mode starts begins hidden as a collapsed main bar would not expand for it, and capture ending resumes after the quiet period; with the switch off it never pauses.
- While presentation mode is paused nothing is hidden, sensitive apps included, and the Settings footnote, the Sensitive apps caption and the paused capsule panel say so.
- A collapse during the pause counts as the user choosing to hide again, as on the main bar; the auto-hide timer collapses the same way.
- The empty-click reveal row is direct-only, although the contract said both builds: the App Store build cannot hit test the bar without Accessibility.
- The palette may open non-sensitive hidden apps while presenting; sensitive apps are filtered out of its list, and a refusal from the engine drops the app from the list without naming it.
- Reveal gestures (scroll, empty click, shake) do nothing while presentation mode is on.
- The arrivals question does not open while presentation mode is on; the dot on the arrow stays and the question waits for the first arrow click after the mode ends.
- The palette offers Command-Return and Option-Return only while pinned sections are on, as arrivals does, and its shortcut is registered only where the native engine runs, as the presentation shortcut is.
- The arrow note while presenting gives a count of apps that stay hidden and never their names, since the room sees it.
- A shortcut that clashes with another Hidden Bar shortcut is not saved; the registry makes every binding again whenever any shortcut changes.
- The panel from the Presenting capsule gives counts only and never names an app, since it is on the shared screen; sensitive apps are named and edited only in Settings.
