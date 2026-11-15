# Quality requirements

Each entry names a scenario, the required response, how it is measured, and the check that proves it.

## Release

| ID | Attribute | Scenario | Response | Measure | Check |
|---|---|---|---|---|---|
| Q-REL-1 | security | a full `scripts/release.sh` run | no ASC API key or Sparkle EdDSA private key value appears in stdout, stderr, `checks.md`, or any file left under `--out` or the temp dir after exit | 0 hits | the "No key material left" row of every `checks.md`; `secrets-cleanup-on-failure`, `leak-scan-detects` and `refuse-xtrace` in `scripts/test-release.sh` |
| Q-REL-2 | integrity | a release run with N published prior appcast items | the new appcast holds N+1 items, each prior item byte-identical, each enclosure signature valid against the shipped `SUPublicEDKey` | N of N identical, N+1 of N+1 VALID | the "Prior items verbatim" and "Enclosure" rows of `checks.md`; the `appcast-*` and `cut-cmp-*` cases in `scripts/test-release.sh` |
