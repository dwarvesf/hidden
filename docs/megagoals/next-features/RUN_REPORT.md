# Run report: next features (1.13.0)

Outcome: the four features are merged to develop behind opt-in Settings rows; a local notarized 1.13.0 candidate exists; nothing is published. Release, tag, appcast and App Store stay with Han.

## Outcome

| SG | Sub-goal | PR | Merged | Verifier |
|---|---|---|---|---|
| 00 | Contract, roadmap | #490 | 5c067b4 | lead |
| 01 | Foundation: shortcut recorder, hotkey registry, item catalog, hb-cmd | #497 | 70f6a82 | FAIL (catalog listed apps with no icon), then PASS |
| 02 | F3 Reveal without aiming | #493 | dfa9148 | PASS |
| 03 | F4 spike | #492 | c7cd242 | PASS |
| 05 | F2 Arrivals inbox | #503 | c195025 | PASS |
| 04 | F1 Type-to-find palette | #505 | 47086cf | PASS |
| 06 | F4 Presentation mode (manual + display mirroring) | #504 | b507df0 | PASS, recheck FAIL (palette app stayed allowed), then PASS |
| 07 | Integration: CHANGELOG, docs, version 1.13.0 (20), candidate | #508 | d05470e | PASS |
| fix | Parallel test hosts quit as a second copy | #506 | b148d6f | lead review, 8 to 0 runner errors |
| fix | Settings test bundle in one process | #507 | 3f9c32c | lead review, 2 of 5 to 0 of 5 failed runs |
| fix | Presentation seams (convergence findings) | #509 | 78ac3f5 | PASS |

Spike verdict: automatic (display mirroring). Screen sharing has no public signal; the slideshow trigger was not provable without a live show.

## Timeline

```
Wave 0  |#490|                                   contract, roadmap
Wave 1       |#497 #493 #492|--verify--fix #497--merge
Wave 2                                |#503 #505 #504|--verify--fixes--merge (+#506 #507)
Close                                                         |advisor + seams #509|--#508 rebuild--merge
```

## Workers and verifiers

| Role | Model | Count |
|---|---|---|
| Sub-goal workers (SG-01 to SG-07) | sonnet | 7 |
| Fix workers (#506/#507, #509) | sonnet | 2 |
| Contract extraction | sonnet | 1 |
| Wave verifiers (W1, W2, W3; resumed for every recheck) | opus | 3 |
| Convergence advisor (P5 + P6) | opus | 1 |

Every fix went back to the worker that wrote the code (SendMessage); no sub-goal was respawned.

## Gate matrix

| SG | Tests green | Negative control | CI | Offscreen vs boards | Verifier |
|---|---|---|---|---|---|
| 01 | ● | ● | ● | ● | ● |
| 02 | ● | ● | ● | ● | ● |
| 03 | n/a (docs) | n/a | n/a | n/a | ● |
| 04 | ● | ● | ● | ● | ● |
| 05 | ● | ● | ● | ● | ● |
| 06 | ● | ● | ● | ● | ● |
| 07 | ● | n/a (docs, version) | ● | ● | ● |

● recorded and passed. Live hooks runs were not used: every on-screen state was checked through the offscreen snapshot path, light and dark.

## Candidate

- `~/.cache/hidden-bar/release/1.13.0/Hidden-Bar-v1.13.0-macos.zip` on the Mini; sha256 starts `be821a32` and ends `8dbbca9ff0` (full value and every check in `evidence.txt` next to the zip).
- Notarization b656befd-1cc5-465c-a882-402c27dfa18b Accepted, stapled, Gatekeeper accepted (Notarized Developer ID), no sandbox, 1.13.0 (20), Sparkle feed and key unchanged.
- Not launched; never copied into /Applications. Host state (installed 1.12.0 CDHash, login item) unchanged across every verifier run and the build.

## Incidents and lessons

- The Debug single-instance check quit Xcode's parallel test-host clones (exit 0 before connecting); more test classes made it visible. Fixed in #506; then real parallelism exposed shared-defaults races, fixed in #507.
- Cross-feature seams (presentation with palette, reveal, arrivals, shortcuts) were invisible to per-PR review; the convergence advisor and a seam review found them, fixed in #509. Presentation now follows the 1.12 capture rule instead of the spike's whole-capture pause.
- Other sessions on the Mini quit and relaunched the installed Hidden Bar and once launched a re-signed test copy that showed a "damaged" dialog; none of it came from this run.
- A helper subagent's completion reached the lead instead of the verifier that spawned it; the lead forwarded it.

## Open after this run

See `docs/BACKLOG.md` "Open after 1.13.0". The ones that need Han or a live Mac:
- A live check of the candidate from /Applications (palette Return opening a hidden app's menu, the Presenting capsule, reveal hit test on a real bar).
- Measure the clock and battery system-item ids so presentation can keep only those two.
- A 1.12.0 build must come from ed5eddb (v1.12.0, #483); develop now carries 1.13.0.
- Design boards (23, light and dark): https://claude.ai/code/artifact/d6f7d69e-feed-4e87-9f25-c652da440cc6
