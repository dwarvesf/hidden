# Decisions

Mid-run decisions, one line each.

- Opt-in defaults: every new Bool key defaults to false and `newAppDefaultSection` defaults to Show It, so 1.13.0 with default settings behaves like 1.12.0. The boards suggested Ask Me and two gestures on; the run brief says opt-in, which wins.
- F1 has no separate on/off switch: an unset shortcut is the off state, as on the Palette-Settings board.
- Workers never launch the app live; offscreen snapshots plus wave-verifier hooks runs replace live checks.
- The 1.13.0 smoke test is static (codesign, spctl, stapler) because a Release build launched outside /Applications acts on the real install.
- `presentationSensitiveApps` is stored as a dictionary so the import whitelist needs no new Kind.
