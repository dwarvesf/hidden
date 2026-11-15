# Notes

Event log, one line per round.

- Wave 0: contract pinned; design artifact publish refused by the daily cap, retry after the UTC reset.
- Wave 1: 3 PRs (#497 foundation, #493 reveal, #492 spike); verifier FAIL then PASS on #497; merged.
- Wave 2: 3 PRs (#503 arrivals, #505 palette, #504 presentation); verifier PASS, then #504 recheck FAIL then PASS; merged.
- CI fix #506: parallel test hosts no longer quit as a second copy; merged during wave 2, after #505 and before #504.
- Wave 3: SG-07 integration branch release/1.13.0-candidate: CHANGELOG, docs, version 1.13.0 build 20, local notarized candidate, nothing published.
- CI fix #507: the settings test bundle runs in one process and test.sh no longer forces parallel testing; merged to develop after #506, not user-facing.
