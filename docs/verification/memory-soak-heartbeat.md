# memory-soak heartbeat: proof

| | |
|---|---|
| Change | `scripts/memory-soak/sample` pings the vps-mon heartbeat `mini.hiddenbar-memory-soak` after each completed sample |
| Why | the LaunchAgent was a catalog gap (scheduled job, no monitor); a heartbeat is its liveness signal |
| Live after | merge, pull of the Mini `hidden` checkout, heartbeat provisioned (see PR) |

## Green run

- Command: `scripts/memory-soak/test-heartbeat`
- Exit: 0
- Verdict: PASS

```
PASS sampled     pings=1 exit=0
PASS no-url      pings=0 exit=0
PASS soak-ended  pings=0 exit=0
PASS ping-fails  pings=0 exit=0
PASS running     pings=1 exit=0
PASS no-footprint pings=0 exit=0
-- summary: all cases match
```

Real sample, stub ping helper, temp log, the installed Hidden Bar running: exit 0, one ping, one log line (`pid=... footprint=... nodes=...`).

`running` uses a fake "Hidden Bar" process and the real `footprint`; `no-footprint` stubs `footprint` to print nothing, so the sample logs `footprint=NA` and must not ping.

## NEGATIVE CONTROL

- Command: `negctl.sh` with `sample` swapped for the pre-change copy (`git show HEAD~1:scripts/memory-soak/sample`)
- Exit: 1 under mutation, RED as expected: `FAIL sampled pings=0 (want 1)` and `FAIL ping-fails` (no "heartbeat ping failed" logged)
- Restored: exit 0, Verdict: PASS

## Reproduce

```bash scripts/memory-soak/test-heartbeat
scripts/memory-soak/test-heartbeat
```

## End of soak

The `soak-ended` case is the proof the end-date branch does not ping: the heartbeat then goes silent on purpose. Retire it after the end epoch with vps-mon `bin/retire-heartbeat mini.hiddenbar-memory-soak`.

Second control, review fixes: `negctl.sh` with the closing ping line deleted (`sed -i '' '/ || heartbeat$/d' scripts/memory-soak/sample`): `running` goes RED (pings=0, want 1). With `sample` at the previous commit (no footprint=NA skip): `no-footprint` goes RED (pings=1, want 0).
