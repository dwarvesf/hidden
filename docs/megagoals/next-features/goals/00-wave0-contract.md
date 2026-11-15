# SG-00 Wave 0: contract, roadmap, design artifact

Model: lead
Effort: high
**Branch:** docs/next-features-roadmap

Done = this roadmap folder merged to develop; `CONTRACT.md` pinned; the design boards published as one Claude Design artifact (all 23 boards, one publish) and its link recorded in `NOTES.md`.

## Scope

- Lead only, no workers.
- The design publish was refused twice by the daily Artifact cap; it is retried after the UTC reset and does not block Wave 1 (workers read the local `.dc.html` files).

## Verifier protocol (used by every wave verifier)

One Opus verifier per wave, dispatched after every PR in the wave is open and CI green. It is read-only on the repo and never pushes.

1. Per PR: check out the PR head in its own clone under `~/.cache/hidden-bar/verify/<wave>/<slug>`, run `bash scripts/test.sh --dd ~/.cache/hidden-bar/dd-verify-<slug>` (output to a file, read the tail), and record counts per scheme.
2. CI: `gh pr checks <pr>` shows `Build and test both schemes` passing.
3. Negative control: for each new test file or test case, revert only the production files of the PR to the base commit, run those tests, confirm they fail; restore.
4. Offscreen UI: build `Debug-Direct`, run with `-settingsSnapshotDir <dir>`, and compare every new `direct-*` PNG (light and dark) against the matching design board by reading both. Report mismatches by board name.
5. Live hooks run, only when the wave needs one, under the host-state protocol below. Screenshots only; no keystrokes, pointer input or cursor moves.
6. Verdict per PR: PASS or FAIL with numbered findings (file:line, the board, the failing command).

## Host-state protocol (any live run of a test build)

Before:
- `codesign -dvvv "/Applications/Hidden Bar.app" 2>&1 | grep CDHash` and the app version.
- `osascript -e 'tell application "System Events" to get the path of every login item whose name is "Hidden Bar"'`.
- `defaults export com.dwarvesv.minimalbar <backup.plist>`.
- `pgrep -fl "Hidden Bar"`.

Run: launch only with `open -g -n <build path> --args ...`; drive it only with `scripts/hb-cmd`; capture with `screencapture -x -l <window id>`.

After:
- Quit only the PIDs the run started.
- `defaults import com.dwarvesv.minimalbar <backup.plist>`; delete any `SU*` key absent from the backup.
- Compare CDHash, login items and the running `/Applications` instance with the before values. Any difference is a FAIL and is reported, never silently repaired beyond the restore above.
- Remember: the macOS 27 allow-list works only for a copy in `/Applications`, so a test build elsewhere hides its own arrow on collapse. Judge hiding behavior from unit tests and `dump-state`, not from a scratch-path run.
