# Notes

Event log, one line per round.

- Wave 0: contract pinned; design artifact publish refused by the daily cap, retry after the UTC reset.
- Wave 1: 3 PRs (#497 foundation, #493 reveal, #492 spike); verifier FAIL then PASS on #497; merged.
- Wave 2: 3 PRs (#503 arrivals, #505 palette, #504 presentation); verifier PASS, then #504 recheck FAIL then PASS; merged.
- CI fix #506: parallel test hosts no longer quit as a second copy; merged during wave 2, after #505 and before #504.
- Wave 3: SG-07 integration branch release/1.13.0-candidate: CHANGELOG, docs, version 1.13.0 build 20, local notarized candidate, nothing published.
- CI fix #507: the settings test bundle runs in one process and test.sh no longer forces parallel testing; merged to develop after #506, not user-facing.
- Convergence: advisor P5 (7 findings) and P6 (8 proposals) plus a seam review; fixes in #509 (presentation follows the 1.12 capture rule, guards while presenting, shortcut clash refused, counts instead of names on the shared screen); verifier PASS; merged 78ac3f5.
- Wave 3 close: #508 rebased on #509, candidate rebuilt and notarized (b656befd, Accepted); final verifier PASS; merged d05470e. Run ends at the SG-07 gate.
- Design boards published as one Claude Design canvas (23 boards, light and dark): https://claude.ai/code/artifact/d6f7d69e-feed-4e87-9f25-c652da440cc6
