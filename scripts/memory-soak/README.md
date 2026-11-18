# memory-soak

An hourly, read-only memory sample of the installed Hidden Bar, for a 14-day soak. It exists to answer consolelabs/hidden #386 (footprint reported to grow to 600 MB after weeks of uptime) with our own numbers, using the reporter's method: `footprint` and `heap`.

## What it measures

One line per hour in `~/Library/Logs/hiddenbar-memory-soak.log`:

```
2026-11-16T20:40:00+0700 pid=63409 up=04:12:33 footprint=19235872 peak=19350560 nodes=61739 heap_bytes=6706064 version=1.13.0+21
```

- `footprint`, `peak`: `phys_footprint` and `phys_footprint_peak` in bytes (`footprint -p PID`), the number Activity Monitor shows as Memory.
- `nodes`, `heap_bytes`: the `All zones` line of `heap PID`, the malloc node count and total bytes.
- `up`: process uptime (`ps` etime, `[[dd-]hh:]mm:ss`). `version`: `CFBundleShortVersionString+CFBundleVersion` of /Applications/Hidden Bar.app.
- App not running: `pid=- state=not-running`. If `heap` is denied: `nodes=NA heap=failed`, footprint still logged.

The sampler never signals or changes the app. `heap` pauses the process for a few milliseconds while it walks the malloc zones.

## Run it

```bash scripts/memory-soak/install
scripts/memory-soak/install              # from the MAIN checkout, after merge and pull
scripts/memory-soak/summarize            # first, last, min, max per pid, one screen
scripts/memory-soak/install --uninstall  # stop early; the plist goes to the Trash
```

The LaunchAgent is `mini.hiddenbar-memory-soak`. It runs at load and every 3600 s, and boots itself out once the end date (install time + 14 days, passed as an epoch argument) has passed. Check with `launchctl print gui/$UID/mini.hiddenbar-memory-soak`. Launchd stderr goes to `~/Library/Logs/hiddenbar-memory-soak.err`.

## Heartbeat

Each completed sample pings the `mini.hiddenbar-memory-soak` vps-mon heartbeat (`~/.config/vps-mon/hiddenbar-memory-soak-heartbeat-url`, through vps-mon `bin/hb-ping`). A sample with no footprint reading does not ping. No URL file, or a failed ping, changes nothing. The end-date branch does not ping, so the heartbeat goes silent once the soak is over: at the end epoch (1796051986, 2026-11-30) retire it with vps-mon `bin/retire-heartbeat mini.hiddenbar-memory-soak`. `scripts/memory-soak/test-heartbeat` proves it.

## Reading a leak

A leak is footprint and node count both rising across days at the same pid; a new pid (app restarted) restarts the series, so compare within a pid only.
