# Verification: repo URLs point at consolelabs

2026-11-17. `dwarvesf/hidden` moved to the `consolelabs` org by GitHub transfer. GitHub redirects the old URLs. This branch points the repo's own URLs at the new home: the direct build's `SUFeedURL`, the About tab links, README, and the non-dated docs. Bundle ids, team, signing, the CI workflow and the Dwarves Foundation publisher strings are unchanged: the app is still published by Dwarves Foundation.

| Check | Result |
|---|---|
| New `SUFeedURL` serves the appcast | 200, 2 items, 2827 bytes |
| Old feed URL (what installed copies read) | 200 through GitHub's transfer redirect, byte-identical to the new one |
| `plutil -lint hidden/Info-Direct.plist` | OK |
| `rg -i 'dwarvesf/(hidden\|vimmotionpublic\|blurred\|micro-sniff)'` | hits only in `CHANGELOG.md` history and one dated decision brief |
| README sibling links | VimMotion points at `consolelabs/VimMotionApp`; Blurred points at its App Store page (the repo is private); Micro Sniff link removed (the repo is private) |
| Build | not run: URL and string changes only |

## Recorded run

```
Command: curl -sL -o new.xml -w 'new http=%{http_code} size=%{size_download}' https://github.com/consolelabs/hidden/releases/latest/download/appcast.xml
Exit: 0
Output:
consolelabs http=200 size=2827
Verdict: PASS
```

```
Command: curl -sL -o old.xml -w 'old http=%{http_code} size=%{size_download}' https://github.com/dwarvesf/hidden/releases/latest/download/appcast.xml; cmp old.xml new.xml
Exit: 0
Output:
dwarvesf http=200 size=2827
(cmp: no output, files identical)
Verdict: PASS
```

```
Command: plutil -lint hidden/Info-Direct.plist
Exit: 0
Output:
hidden/Info-Direct.plist: OK
Verdict: PASS
```

## Left alone

- `CHANGELOG.md` history entries (issue and release links written at the time).
- `docs/briefs/DECISION-BRIEF-366-overflow-bar.md`, a dated record that names the old clone.
- Appcast enclosure URLs inside the published `appcast.xml` release assets: they still say `dwarvesf/hidden` and resolve through the redirect. The next release regenerates them with the new prefix.
- `@dwarvesf` X handle and the `github.com/dwarvesf` org link in the license line: Dwarves Foundation is still the publisher.

## Rollback

Revert this commit: every URL goes back to `dwarvesf/hidden`, which GitHub still redirects. Builds already shipped keep working either way. Never create a new repo named `dwarvesf/hidden`: that ends the redirect, and installed copies that read the old feed URL stop seeing updates.
