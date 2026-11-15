# Next features (1.13.0): roadmap

Destination: four features from the approved idea ranking, merged to develop behind opt-in Settings rows, with a local notarized 1.13.0 candidate. Han ships; this run never tags, publishes an appcast, or submits to the App Store.

Driver: skill `megagoal-agent-drive`, in one lead session (not the /goal loop). Shared rules: `CONTRACT.md`. Design boards: the "Hidden Bar next features" Design artifact (source files in ops-toolkit `_inbox/hidden-next-features/design-boards/`).

## DAG

```
Wave 0   SG-00 contract + roadmap + design artifact (lead)
            |
Wave 1   SG-01 foundation ----+------------+
         SG-02 F3 reveal      |            |
         SG-03 F4 spike ------|------+     |
            | verifier W1     |      |     |
Wave 2   SG-04 F1 palette <---+      |     |
         SG-05 F2 arrivals <--+      |     |
         SG-06 F4 build <-----+------+     |
            | verifier W2                  |
Wave 3   SG-07 integration + 1.13.0 candidate
            | verifier W3
```

Merge order inside a wave (later PRs rebase): Wave 1 SG-01, SG-03, SG-02. Wave 2 SG-05, SG-04, SG-06.

## Sub-goals

- [x] SG-00 wave0-contract , gate , depends none, #490, merged 5c067b4
- [x] SG-01 foundation (shortcut recorder, item catalog, hb-cmd) , gate , depends SG-00, #497, merged 70f6a82
- [x] SG-02 F3 reveal without aiming , gate , depends SG-00, #493, merged dfa9148
- [x] SG-03 F4 presentation detection spike , gate , depends SG-00, #492, merged c7cd242
- [x] SG-04 F1 type-to-find palette , gate , depends SG-01, #505, merged 47086cf
- [x] SG-05 F2 arrivals inbox , gate , depends SG-01, #503, merged c195025
- [x] SG-06 F4 presentation mode build , gate , depends SG-01 SG-03, #504, merged b507df0
- [ ] SG-07 integration, CHANGELOG 1.13.0, notarized candidate , gate! , depends SG-02 SG-04 SG-05 SG-06

A box flips only with its PR: `- [x] SG-NN ..., #PR, merged <sha>`.

## Merge posture

- Every sub-goal is `gate`: the lead merges a wave's PRs only after that wave's Opus verifier passes and CI `Build and test both schemes` is green.
- SG-07 is `gate!`: the run ends there; release, tag, appcast and App Store stay with Han.
- Deployable terminus: the notarized candidate is built and smoke-tested locally, never published.

## Stop conditions

- Before any public release, tag, Sparkle appcast publish or App Store submission.
- A feature would need Screen Recording or any new TCC permission: stop and ask Han.
- A wave verifier fails twice on the same sub-goal: stop and report.
