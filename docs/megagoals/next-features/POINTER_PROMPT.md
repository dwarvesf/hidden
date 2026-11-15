# Pointer prompt

Drive `docs/megagoals/next-features/ROADMAP.md` to the SG-07 gate with skill `megagoal-agent-drive` in one lead session. Every worker reads `CONTRACT.md` and its own `goals/NN-*.md` first.

- Waves: dispatch every sub-goal whose dependencies are merged, in one message, Sonnet workers, one scratch clone each.
- After each wave: one Opus verifier per the protocol in `goals/00-wave0-contract.md`; merge only on PASS and green CI; fixes go to the same worker by SendMessage.
- Stop before any release, tag, appcast or App Store action; on any need for Screen Recording or a new TCC permission; on a second verifier FAIL for one sub-goal.
- No em or en dashes in code comments, docs or PR bodies.
