#!/bin/bash
# scripts/test-release.sh : offline tests for scripts/release.sh and scripts/release-helper.swift.
#
#   bash scripts/test-release.sh
#
# No network, no secrets, no Xcode build, no Apple notary, no 1Password: every external tool the
# stages call (gh, op, curl, xcrun, spctl, trash) is a PATH stub, and release.sh is sourced with
# RELEASE_SH_SOURCE_ONLY=1 so each check runs alone. One PASS/FAIL/SKIP line per case; exit 0
# only when no case failed. The fixture root is left in $TMPDIR for the OS to clean.
#
# Fixtures (scripts/fixtures/release/): payload.bin with a signature by a throwaway Ed25519 key
# (only its public half is kept), a second unrelated public key, the published v1.11.2 appcast
# (prior-1.xml) and the 1.12.0 hand-run appcast (prior-2.xml), both with fixture signatures, and
# the 1.12.0 notes and item as the golden output of `release-helper item`.

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
F="$ROOT/scripts/fixtures/release"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-release-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
STUBS="$WORK/stubs"; mkdir -p "$STUBS" "$WORK/trashed"
export TMPDIR="$WORK"
PASSED=0; FAILED_N=0; SKIPPED_N=0; FAILED_NAMES=""

H="$WORK/release-helper"
if ! swiftc -O "$ROOT/scripts/release-helper.swift" -o "$H" >"$WORK/helper-build.log" 2>&1; then
  echo "FAIL helper-build (see $WORK/helper-build.log)"; exit 1
fi

stub() { cat > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
stub trash <<'EOF'
#!/bin/bash
mv "$1" "$TMPDIR/trashed/" 2>/dev/null
EOF
stub gh <<'EOF'
#!/bin/bash
# scenarios from env: STUB_TAG (absent|draft|published|error), STUB_LATEST ("tag draft has-appcast"), STUB_FEED
case "$*" in
  "release view v"*"--json isDraft"*)
    case "${STUB_TAG:-absent}" in
      absent) echo "release not found" >&2; exit 1 ;;
      draft) echo true ;;
      published) echo false ;;
      *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac ;;
  "release view -R"*"--json tagName"*) echo "${STUB_LATEST:-v1.11.2 false true}" ;;
  "release download"*"--pattern appcast.xml"*)
    dir=""; prev=""
    for a in "$@"; do [ "$prev" = "--dir" ] && dir="$a"; prev="$a"; done
    cp "$STUB_FEED" "$dir/appcast.xml" ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 9 ;;
esac
EOF
stub curl <<'EOF'
#!/bin/bash
# STUB_CURL_RC sets the exit code; STUB_CURL_FILE is copied to the -o target (a download)
if [ -n "${STUB_CURL_FILE:-}" ]; then
  out=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
  [ -z "$out" ] || cp "$STUB_CURL_FILE" "$out"
fi
exit "${STUB_CURL_RC:-0}"
EOF
stub op <<'EOF'
#!/bin/bash
# fake vault: one ASC item (fake PEM) and the EdDSA item. STUB_OP_RC fails every call.
[ -z "${STUB_OP_RC:-}" ] || exit "$STUB_OP_RC"
[ -z "${OP_CONNECT_HOST:-}" ] || echo connect >> "$TMPDIR/op-source.log"
pem="-----BEGIN PRIVATE"" KEY-----"
case "$1 $2" in
  "item list") echo '[{"id":"asc1","title":"Dwarves Hacker Bar Release"},{"id":"ed1","title":"Hidden Bar Sparkle EdDSA private key"}]' ;;
  "item get") printf '{"id":"asc1","fields":[{"id":"f1","label":"p8","value":"%s\\nFAKEFAKE\\n-----END"},{"id":"f2","label":"key id","value":"KEYID123"},{"id":"f3","label":"issuer","value":"ISSUER-UUID"}]}\n' "$pem" ;;
  *) exit 1 ;;
esac
EOF
stub xcrun <<'EOF'
#!/bin/bash
# notarytool and stapler only. STUB_NOTARY=Accepted|Invalid
case "$1 $2" in
  "notarytool submit")
    key=""; prev=""
    for a in "$@"; do [ "$prev" = "--key" ] && key="$a"; prev="$a"; done
    grep -q 'BEGIN PRIVATE' "$key" && echo seen > "$TMPDIR/key-seen-at-submit"
    printf '{"id":"00000000-0000-0000-0000-000000000001","status":"%s","message":"Processing complete"}\n' "$STUB_NOTARY" ;;
  "notarytool log")
    out="${!#}"
    [ -z "${STUB_NOTARY_LOGFAIL:-}" ] || { echo "Error: could not fetch the log" >&2; exit 1; }
    if [ "$STUB_NOTARY" = Accepted ]; then echo '{"status":"Accepted","statusSummary":"Ready for distribution","issues":null}' > "$out"
    else echo '{"status":"Invalid","statusSummary":"Archive contains critical validation errors","issues":[{"message":"The binary is not signed."}]}' > "$out"; fi ;;
  "stapler staple"|"stapler validate") exit 0 ;;
  *) exit 1 ;;
esac
EOF
stub spctl <<'EOF'
#!/bin/bash
echo "${!#}: accepted"; echo "source=Notarized Developer ID"
EOF

# The stages must see the stubs, never the real gh/op/xcrun.
export PATH="$STUBS:$PATH"
for t in gh op curl xcrun spctl trash; do
  [ "$(command -v "$t")" = "$STUBS/$t" ] || { echo "FAIL stub-shadowing ($t resolves to $(command -v "$t"))"; exit 1; }
done

RELEASE_SH_SOURCE_ONLY=1
# shellcheck source=release.sh
source "$ROOT/scripts/release.sh"
set +e +u
make_tmp
HELPER="$H"
CONNECT_TOKEN_FILE="$WORK/fake-connect-token"; echo fake-token > "$CONNECT_TOKEN_FILE"
SIG="$(cat "$F/payload.sig.b64")"; PUB="$(cat "$F/pub.b64")"

result() { # name rc [reason]
  if [ "$2" = 0 ]; then echo "PASS $1"; PASSED=$((PASSED + 1))
  elif [ "$2" = 77 ]; then echo "SKIP $1${3:+: $3}"; SKIPPED_N=$((SKIPPED_N + 1))
  else echo "FAIL $1${3:+: $3}"; FAILED_N=$((FAILED_N + 1)); FAILED_NAMES="$FAILED_NAMES $1"; fi
}
t() { local name="$1"; shift; "$@" >"$WORK/case.log" 2>&1; result "$name" $? "$(tail -1 "$WORK/case.log")"; }
rc_is() { local want="$1"; shift; "$@"; [ $? = "$want" ]; }

# ---- release-helper verify --------------------------------------------------------------

t verify-valid bash -c '[ "$("$0" verify "$1" "$2" "$3")" = VALID ]' "$H" "$F/payload.bin" "$SIG" "$PUB"
cp "$F/payload.bin" "$WORK/append.bin"; printf 'x' >> "$WORK/append.bin"
t verify-tampered-append rc_is 1 "$H" verify "$WORK/append.bin" "$SIG" "$PUB"
perl -pe 's/^H/h/ if $. == 1' "$F/payload.bin" > "$WORK/flip.bin"
t verify-tampered-flip bash -c '! cmp -s "$1" "$2" && "$0" verify "$1" "$3" "$4"; [ $? = 1 ]' "$H" "$WORK/flip.bin" "$F/payload.bin" "$SIG" "$PUB"
t verify-wrong-key rc_is 1 "$H" verify "$F/payload.bin" "$SIG" "$(cat "$F/wrongkey.pub.b64")"

# ---- release-helper item and appcast ----------------------------------------------------

URL12="https://github.com/dwarvesf/hidden/releases/download/v1.12.0/Hidden-Bar-v1.12.0-macos.zip"
mkitem() { # build short notes out
  "$H" item --version "$1" --short "$2" --min-os 13.0 --notes "$3" \
    --url "https://github.com/dwarvesf/hidden/releases/download/v$2/Hidden-Bar-v$2-macos.zip" --length 2174551 \
    --sig "$SIG" --pubdate 'Sun, 15 Nov 2026 16:33:08 GMT' --link "https://github.com/dwarvesf/hidden/releases/tag/v$2" > "$4"
}
item_exact() { mkitem 19 1.12.0 "$F/notes-1.12.0.html" "$WORK/item-19.xml" && cmp "$WORK/item-19.xml" "$F/item-1.12.0.expected"; }
t item-exact-output item_exact
printf '<ul>\n<li>bad ]]> notes</li>\n</ul>\n' > "$WORK/notes-cdata.html"
t item-refuse-cdata-terminator rc_is 2 mkitem 20 1.13.0 "$WORK/notes-cdata.html" "$WORK/x.xml"

appcast_1() {
  "$H" appcast --prior "$F/prior-1.xml" --item "$WORK/item-19.xml" --out "$WORK/feed-1.xml" &&
  [ "$(count_items "$WORK/feed-1.xml")" = 2 ] && first_item "$WORK/feed-1.xml" | grep -q '<sparkle:version>19<'
}
t appcast-1-prior appcast_1
mkitem 20 1.13.0 "$F/notes-1.12.0.html" "$WORK/item-20.xml"
appcast_2() {
  "$H" appcast --prior "$F/prior-2.xml" --item "$WORK/item-20.xml" --out "$WORK/feed-2.xml" &&
  [ "$(count_items "$WORK/feed-2.xml")" = 3 ] && first_item "$WORK/feed-2.xml" | grep -q '<sparkle:version>20<'
}
t appcast-2-prior appcast_2
prior_verbatim() {
  # the 1-prior merge reproduces the 1.12.0 hand-run feed byte for byte, and both merges keep
  # every prior item: the feed minus item 1 is the prior file
  cmp "$WORK/feed-1.xml" "$F/prior-2.xml" && cut_cmp_prior "$WORK/feed-1.xml" "$F/prior-1.xml" "$WORK/cut1" &&
  cut_cmp_prior "$WORK/feed-2.xml" "$F/prior-2.xml" "$WORK/cut2"
}
t appcast-prior-verbatim prior_verbatim
cdata_text() {
  awk '{print} /^<ul>$/ && !d {print "<li>quoting </item> and <item> in a note</li>"; print "        </item>"; print "        <item>"; d=1}' "$F/prior-1.xml" > "$WORK/prior-cdata.xml" &&
  "$H" appcast --prior "$WORK/prior-cdata.xml" --item "$WORK/item-19.xml" --out "$WORK/feed-cdata.xml" &&
  cut_cmp_prior "$WORK/feed-cdata.xml" "$WORK/prior-cdata.xml" "$WORK/cut3" && xmllint --noout "$WORK/feed-cdata.xml"
}
t appcast-cdata-item-text cdata_text
sed 's/$/\r/' "$F/prior-1.xml" > "$WORK/prior-crlf.xml"
t appcast-refuse-crlf rc_is 2 "$H" appcast --prior "$WORK/prior-crlf.xml" --item "$WORK/item-19.xml" --out "$WORK/x.xml"
mkitem 16 1.13.0 "$F/notes-1.12.0.html" "$WORK/item-16.xml"
refuse_lower() { "$H" appcast --prior "$F/prior-1.xml" --item "$WORK/item-16.xml" --out "$WORK/x.xml" 2>"$WORK/err"; [ $? = 1 ] && grep -q '1.11.2' "$WORK/err"; }
t appcast-refuse-lower-build refuse_lower
mkitem 17 1.13.0 "$F/notes-1.12.0.html" "$WORK/item-17.xml"
t appcast-refuse-same-build rc_is 1 "$H" appcast --prior "$F/prior-1.xml" --item "$WORK/item-17.xml" --out "$WORK/x.xml"
mkitem 30 1.11.2 "$F/notes-1.12.0.html" "$WORK/item-dup.xml"
refuse_dup() { "$H" appcast --prior "$F/prior-1.xml" --item "$WORK/item-dup.xml" --out "$WORK/x.xml" 2>"$WORK/err"; [ $? = 1 ] && grep -q 'shortVersionString 1.11.2' "$WORK/err"; }
t appcast-refuse-dup-short refuse_dup
numeric_compare() {
  sed 's|<sparkle:version>17<|<sparkle:version>9<|' "$F/prior-1.xml" > "$WORK/prior-9.xml"
  sed 's|<sparkle:version>17<|<sparkle:version>99<|' "$F/prior-1.xml" > "$WORK/prior-99.xml"
  mkitem 10 1.13.0 "$F/notes-1.12.0.html" "$WORK/item-10.xml"; mkitem 100 1.13.0 "$F/notes-1.12.0.html" "$WORK/item-100.xml"
  "$H" appcast --prior "$WORK/prior-9.xml" --item "$WORK/item-10.xml" --out "$WORK/x.xml" &&
  "$H" appcast --prior "$WORK/prior-99.xml" --item "$WORK/item-100.xml" --out "$WORK/x.xml"
}
t appcast-numeric-build-compare numeric_compare
t appcast-xmllint xmllint --noout "$WORK/feed-1.xml" "$WORK/feed-2.xml"

# ---- read-back and cut-and-compare (shell, independent of the Swift merge) ---------------

t readback-new-item-ok readback_new_item "$WORK/feed-1.xml" 19 1.12.0 13.0 "$URL12" 2174551
t readback-wrong-url-fails rc_is 1 readback_new_item "$WORK/feed-1.xml" 19 1.12.0 13.0 "${URL12/v1.12.0\//v1.12/}" 2174551
t readback-wrong-length-fails rc_is 1 readback_new_item "$WORK/feed-1.xml" 19 1.12.0 13.0 "$URL12" 2174552
altered_prior() {
  sed 's|<pubDate>Sun, 15 Nov 2026 06:50:21 GMT|<pubDate>Sun, 15 Nov 2026 06:50:22 GMT|' "$WORK/feed-1.xml" > "$WORK/feed-alt.xml"
  ! cmp -s "$WORK/feed-alt.xml" "$WORK/feed-1.xml" && ! cut_cmp_prior "$WORK/feed-alt.xml" "$F/prior-1.xml" "$WORK/cut4"
}
t cut-cmp-detects-altered-prior altered_prior
prior_no_final_newline() { # a published feed with no newline after </rss> (as v1.13.0's) still compares equal
  [ -n "$(tail -c 1 "$F/prior-1-nonl.xml")" ] &&
  "$H" appcast --prior "$F/prior-1-nonl.xml" --item "$WORK/item-19.xml" --out "$WORK/feed-nonl.xml" &&
  [ "$(count_items "$WORK/feed-nonl.xml")" = 2 ] && cut_cmp_prior "$WORK/feed-nonl.xml" "$F/prior-1-nonl.xml" "$WORK/cut5"
}
t cut-cmp-prior-no-final-newline prior_no_final_newline
altered_prior_no_final_newline() { # the newline allowance never hides a real byte change
  sed 's|<pubDate>Sun, 15 Nov 2026 06:50:21 GMT|<pubDate>Sun, 15 Nov 2026 06:50:22 GMT|' "$WORK/feed-nonl.xml" > "$WORK/feed-nonl-alt.xml"
  ! cmp -s "$WORK/feed-nonl-alt.xml" "$WORK/feed-nonl.xml" && ! cut_cmp_prior "$WORK/feed-nonl-alt.xml" "$F/prior-1-nonl.xml" "$WORK/cut6"
}
t cut-cmp-no-final-newline-detects-altered altered_prior_no_final_newline

# ---- app checks on throwaway ad-hoc bundles --------------------------------------------

# What the shipped app declares, read from the real plist and never from the pins: the fixture
# bundles carry these values, so a pin that drifted from the plist fails the Feed URL and
# EdDSA rows below instead of being copied into the fixtures.
REAL_PLIST="$ROOT/hidden/Info-Direct.plist"
REAL_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$REAL_PLIST" 2>/dev/null)"
REAL_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$REAL_PLIST" 2>/dev/null)"

make_bundle() { # dir pubkey : a minimal app bundle (a copy of /usr/bin/true as its executable)
  local d="$1/Hidden Bar.app"
  mkdir -p "$d/Contents/MacOS"
  cp /usr/bin/true "$d/Contents/MacOS/Hidden Bar"
  cat > "$d/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Hidden Bar</string>
<key>CFBundleIdentifier</key><string>com.dwarvesv.minimalbar.release-test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.12.0</string>
<key>CFBundleVersion</key><string>19</string>
<key>SUFeedURL</key><string>$REAL_FEED</string>
<key>SUPublicEDKey</key><string>$2</string>
</dict></plist>
PL
  echo "$d"
}
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>\n' > "$WORK/sandbox.entitlements"
cp "$ROOT/hidden/Hidden-Direct.entitlements" "$WORK/empty.entitlements"
APP_SBX="$(make_bundle "$WORK/b-sbx" "$REAL_KEY")"; codesign --force -s - --entitlements "$WORK/sandbox.entitlements" "$APP_SBX" 2>/dev/null
APP_EMPTY="$(make_bundle "$WORK/b-empty" "$REAL_KEY")"; codesign --force -s - --entitlements "$WORK/empty.entitlements" "$APP_EMPTY" 2>/dev/null
APP_NONE="$(make_bundle "$WORK/b-none" "$REAL_KEY")"; codesign --force -s - "$APP_NONE" 2>/dev/null
APP_KEY="$(make_bundle "$WORK/b-key" "$(cat "$F/wrongkey.pub.b64")")"; codesign --force -s - --entitlements "$WORK/empty.entitlements" "$APP_KEY" 2>/dev/null

t check-sandbox-entitled-fails rc_is 1 check_sandbox "$APP_SBX"
t check-sandbox-empty-dict-passes check_sandbox "$APP_EMPTY"
t check-sandbox-no-entitlements-fails rc_is 1 check_sandbox "$APP_NONE"

rows_of() { : > "$ROWS_FILE"; N=0; FAILED=0; "$@" >/dev/null 2>&1; local rc=$?; ROWS="$(cat "$ROWS_FILE")"; return $rc; }
row_has() { printf '%s\n' "$ROWS" | grep -E "^\| [0-9]+ \| $1 \|" | grep -q -- "$2"; }
adhoc_unsandboxed() {
  rows_of check_app "$APP_NONE" 1.12.0 19; [ $? = 1 ] &&
  row_has 'Signature: identity, timestamp, runtime' 'FAIL: .*not Developer ID' && row_has Unsandboxed 'FAIL: no entitlements blob'
}
t check-app-adhoc-unsandboxed-fails adhoc_unsandboxed
adhoc_sandboxed() {
  rows_of check_app "$APP_SBX" 1.12.0 19; [ $? = 1 ] &&
  row_has 'Signature: identity, timestamp, runtime' 'FAIL' && row_has Unsandboxed 'FAIL: app-sandbox entitlement present'
}
t check-app-adhoc-sandboxed-fails adhoc_sandboxed
adhoc_not_credited() {
  rows_of check_app "$APP_EMPTY" 1.12.0 19; [ $? = 1 ] && row_has Unsandboxed 'FAIL: .*not credited: identity failed'
}
t check-app-adhoc-empty-dict-not-credited adhoc_not_credited
wrong_pubkey() { rows_of check_app "$APP_KEY" 1.12.0 19; [ $? = 1 ] && row_has 'EdDSA public key' 'FAIL: SUPublicEDKey differs'; }
t check-app-wrong-pubkey-fails wrong_pubkey
devid_sandboxed() {
  local app ident
  ident="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*(W777S7V8TN)\)".*/\1/p' | head -1)"
  [ -n "$ident" ] || { echo "no Developer ID identity"; return 77; }
  app="$(make_bundle "$WORK/b-devid" "$REAL_KEY")"
  perl -e 'alarm 90; exec @ARGV' codesign --force --sign "$ident" --timestamp --options runtime \
    --entitlements "$WORK/sandbox.entitlements" "$app" >/dev/null 2>&1 || { echo "Developer ID signing with --timestamp failed (offline or locked keychain)"; return 77; }
  rows_of check_app "$app" 1.12.0 19; [ $? = 1 ] &&
  row_has 'Signature: identity, timestamp, runtime' '[0-9] parts: Developer ID' && row_has Unsandboxed 'FAIL: app-sandbox entitlement present' ||
    { echo "rows: $(printf '%s' "$ROWS" | head -2 | tr '\n' ' ')"; return 1; }
}
devid_sandboxed >"$WORK/case.log" 2>&1; result check-app-devid-sandboxed-fails $? "$(tail -1 "$WORK/case.log")"
pin_matches_plist() { # what: the pin in release.sh equals the shipped plist value, both non-empty
  local pin="$2" real="$3"
  [ -n "$real" ] || { echo "$1: hidden/Info-Direct.plist has no value"; return 1; }
  [ "$pin" = "$real" ] || { echo "$1 drifted: release.sh pins '$pin', hidden/Info-Direct.plist has '$real'"; return 1; }
}
t pin-feed-url-matches-plist pin_matches_plist SUFeedURL "$PINNED_FEED_URL" "$REAL_FEED"
t pin-pubkey-matches-plist pin_matches_plist SUPublicEDKey "$PINNED_PUBKEY" "$REAL_KEY"
fixture_rows_pass() { # fixtures built from the real plist pass the Feed URL and EdDSA rows against the pins
  rows_of check_app "$APP_EMPTY" 1.12.0 19
  row_has 'Feed URL' "$REAL_FEED" && ! row_has 'Feed URL' FAIL && row_has 'EdDSA public key' 'equals the pinned key'
}
t check-app-fixture-rows-match-pins fixture_rows_pass
key_check() { rc_is 1 check_pubkey "$APP_KEY" && check_pubkey "$APP_EMPTY"; }
t check-pubkey-rejects-other-key key_check

# ---- guards and shell safety ------------------------------------------------------------

t guard-refuses-writes guard_selftest
refuse_xtrace() {
  rc_is 2 /bin/bash -x "$ROOT/scripts/release.sh" --help && rc_is 2 env SHELLOPTS=xtrace /bin/bash "$ROOT/scripts/release.sh" --help &&
  /bin/bash "$ROOT/scripts/release.sh" --help >/dev/null
}
t refuse-xtrace refuse_xtrace

# ---- preflight edge cases ---------------------------------------------------------------

REPO="$WORK/repo"; mkdir -p "$REPO"
( cd "$REPO" && command git init -q --template= && echo a > tracked.txt && command git add tracked.txt &&
  command git -c user.email=t@t -c user.name=t commit -qm init )
dirty_tree() { check_clean_tree "$REPO" && echo b > "$REPO/untracked.txt" && rc_is 1 check_clean_tree "$REPO"; }
t preflight-dirty-tree dirty_tree
versions() {
  printf 'MARKETING_VERSION = 1.12.0;\nMARKETING_VERSION = 1.12.0;\nCURRENT_PROJECT_VERSION = 19;\nCURRENT_PROJECT_VERSION = 19;\n' > "$WORK/ok.pbxproj"
  printf 'MARKETING_VERSION = 1.12.0;\nMARKETING_VERSION = 1.11.0;\nCURRENT_PROJECT_VERSION = 19;\nCURRENT_PROJECT_VERSION = 19;\n' > "$WORK/bad.pbxproj"
  local bad
  [ "$(read_versions "$WORK/ok.pbxproj")" = "1.12.0 19" ] && rc_is 1 read_versions "$WORK/bad.pbxproj" &&
  bad="$(read_versions "$WORK/bad.pbxproj")"; case "$bad" in *"1 1.11.0 1 1.12.0"*) ;; *) return 1 ;; esac
  [ "$(read_versions "$PBXPROJ" | wc -w | tr -d ' ')" = 2 ]
}
t preflight-versions-disagree versions
changelog() {
  printf '# Changelog\n\n## v1.12.0 (2026-11-15)\n\n- x\n' > "$WORK/CHANGELOG.md"
  check_changelog "$WORK/CHANGELOG.md" 1.12.0 && rc_is 1 check_changelog "$WORK/CHANGELOG.md" 1.13.0 && rc_is 1 check_changelog "$WORK/CHANGELOG.md" 1.12
}
t preflight-no-changelog changelog
tag_state() {
  STUB_TAG=absent check_tag_state 1.12.0 && STUB_TAG=published rc_is 1 check_tag_state 1.12.0 &&
  STUB_TAG=error rc_is 3 check_tag_state 1.12.0 && { DRAFT_NOTE=""; STUB_TAG=draft check_tag_state 1.12.0; } && [ -n "$DRAFT_NOTE" ]
}
t preflight-tag-published tag_state
no_asset() {
  STUB_LATEST="v1.11.2 false false" rc_is 1 fetch_prior_appcast "$WORK/p.xml" &&
  STUB_LATEST="v1.11.2 false true" STUB_FEED="$F/prior-1.xml" fetch_prior_appcast "$WORK/p.xml" &&
  cmp -s "$WORK/p.xml" "$F/prior-1.xml" && [ "$PRIOR_TAG" = v1.11.2 ]
}
t preflight-no-appcast-asset no_asset
notes_case() { rc_is 1 check_notes "$WORK/notes-cdata.html" && check_notes "$F/notes-1.12.0.html"; }
t preflight-notes-cdata notes_case
no_1password() {
  : > "$TMPDIR/op-source.log"
  STUB_CURL_RC=7 STUB_OP_RC=1 rc_is 1 op_select_source "$WORK/items.json" && [ -z "$OP_SOURCE" ] &&
  STUB_CURL_RC=7 op_select_source "$WORK/items.json" && [ "$OP_SOURCE" = service-account ] &&
  op_select_source "$WORK/items.json" && [ "$OP_SOURCE" = connect ] && grep -q connect "$TMPDIR/op-source.log"
}
t preflight-no-1password no_1password
tree_drift() {
  local s; s="$(tree_state "$REPO")"
  check_tree_unchanged "$REPO" "$s" && echo changed >> "$REPO/tracked.txt" && rc_is 1 check_tree_unchanged "$REPO" "$s"
}
t tree-drift-detected tree_drift

# ---- secrets handling, notarization (stubbed xcrun and op) ------------------------------

make_bundle "$WORK/notary-app" "$REAL_KEY" >/dev/null
notarize_run() { # case-name [STUB_NOTARY value, default the case name] [log-fails] : runs the stage in a subshell with the real EXIT trap
  local case_dir="$WORK/notary-$1"
  mkdir -p "$case_dir/out" "$case_dir/tmp" "$case_dir/tmp/trashed"
  ( export TMPDIR="$case_dir/tmp" STUB_NOTARY="${2:-$1}" STUB_NOTARY_LOGFAIL="${3:-}"; T=""; make_tmp; setup_traps; OUT="$case_dir/out"; OP_SOURCE=connect
    sleep() { :; }     # the log retries wait 10 s each in a real run
    stage_notarize "$WORK/notary-app/Hidden Bar.app" ) > "$case_dir/stdout" 2>&1
  echo $? > "$case_dir/rc"
}
no_key_left() { # case dir : the fake PEM is nowhere on disk, and it did exist at submit time
  [ -f "$1/tmp/key-seen-at-submit" ] && ! grep -rqF -- "$PEM_MARK" "$1" && [ -z "$(find "$1/tmp" -maxdepth 1 -name 'hb-release.*')" ]
}
notarize_run Invalid
invalid() { [ "$(cat "$WORK/notary-Invalid/rc")" = 1 ] && grep -q "Notarization: FAIL: .*status 'Invalid'.*not signed" "$WORK/notary-Invalid/stdout"; }
t notarize-invalid-fails invalid
t secrets-cleanup-on-failure no_key_left "$WORK/notary-Invalid"
notarize_run Accepted
accepted() {
  local o="$WORK/notary-Accepted/stdout"
  [ "$(cat "$WORK/notary-Accepted/rc")" = 0 ] && grep -q 'Notarization: submission .*: Accepted, Ready for distribution' "$o" &&
  grep -q 'Staple: worked' "$o" && grep -q 'Gatekeeper: accepted' "$o" && no_key_left "$WORK/notary-Accepted"
}
t notarize-accepted-passes accepted
notarize_run AcceptedNoLog Accepted 1
log_unreadable() { # Accepted but the log never arrives: a FAILED row, never "issues none"
  local o="$WORK/notary-AcceptedNoLog/stdout"
  [ "$(cat "$WORK/notary-AcceptedNoLog/rc")" = 1 ] && grep -q 'Notarization: FAIL: .*Accepted, but the notary log was unreadable' "$o" &&
  ! grep -q 'issues none' "$o" && no_key_left "$WORK/notary-AcceptedNoLog"
}
t notarize-log-unreadable-fails log_unreadable
leak_detects() {
  mkdir -p "$WORK/leak/clean" "$WORK/leak/pem" "$WORK/leak/ed"
  echo nothing > "$WORK/leak/clean/a.txt"; printf 'x\n%s\n' "$PEM_MARK" > "$WORK/leak/pem/a.txt"
  echo "prefix FAKE-EDDSA-KEY-VALUE suffix" > "$WORK/leak/ed/a.txt"
  EDKEY="FAKE-EDDSA-KEY-VALUE"
  [ "$(leak_scan "$WORK/leak/clean")" = clean ] && rc_is 1 leak_scan "$WORK/leak/pem" && rc_is 1 leak_scan "$WORK/leak/ed"
  local rc=$?; EDKEY=""; return $rc
}
t leak-scan-detects leak_detects

# ---- Sparkle tool pin -------------------------------------------------------------------

digest_mismatch() {
  local sp="$WORK/sp"
  mkdir -p "$sp/2.10.1" "$WORK/fake-sparkle/bin"
  printf '#!/bin/bash\ntouch "%s/fake-sign-update-ran"\n' "$WORK" > "$WORK/fake-sparkle/bin/sign_update"; chmod +x "$WORK/fake-sparkle/bin/sign_update"
  tar -cJf "$sp/2.10.1/Sparkle-2.10.1.tar.xz" -C "$WORK/fake-sparkle" ./bin/sign_update
  SPARKLE_CACHE_ROOT="$sp" rc_is 2 sparkle_tools 2.10.1 "$WORK/sp-extract" &&
  [ ! -e "$WORK/sp-extract/bin/sign_update" ] && [ ! -e "$WORK/fake-sign-update-ran" ]
}
t sparkle-digest-mismatch-refuses digest_mismatch
unknown_version() {
  SPARKLE_CACHE_ROOT="$WORK/sp" rc_is 2 sparkle_tools 9.9.9 "$WORK/sp-x" || return 1
  local real="$HOME/.cache/hidden-bar/sparkle/2.10.1/Sparkle-2.10.1.tar.xz"
  [ -f "$real" ] || return 0     # positive control only where the real tarball is cached
  sparkle_tools 2.10.1 "$WORK/sp-real" && [ -x "$WORK/sp-real/bin/sign_update" ]
}
t sparkle-unknown-version-refuses unknown_version

# ---- smoke assertions -------------------------------------------------------------------

dead_pid() { sleep 0 & local p=$!; wait "$p"; rc_is 1 smoke_assert_process "$p" "$WORK/notary-app/Hidden Bar.app" 19; }
t smoke-assert-dead-pid-fails dead_pid
wrong_path() {
  sleep 30 & local p=$! rc
  rc_is 1 smoke_assert_process "$p" "$WORK/notary-app/Hidden Bar.app" 19; rc=$?
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; return $rc
}
t smoke-assert-wrong-path-fails wrong_path
# Positive control without launching any app bundle: /bin/sleep stands in as the executable
# (the 4th argument), the fixture bundle only supplies the build number. Tests never launch,
# open or exec anything inside an .app bundle.
live_process() {
  local p rc
  /bin/sleep 30 & p=$!
  sleep 0.3; smoke_assert_process "$p" "$APP_EMPTY" 19 /bin/sleep; rc=$?
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; return $rc
}
t smoke-assert-live-process-passes live_process

# ---- stages through stubs ---------------------------------------------------------------

# stage_appcast end to end on fixtures: the built zip is payload.bin (signed by the fixture key,
# which the fixture export app declares), and curl is a stub that serves a prior-release zip
# holding a fixture app with the key under test. Nothing is launched; the zip is only unpacked.
appcast_run() { # case-name prior-app-key [verify-ok|bad-version] : leaves rc, stdout and out/ under $WORK/ac-<case-name>
  local d="$WORK/ac-$1" prior_len
  mkdir -p "$d/out" "$d/tmp/trashed" "$d/src"
  make_bundle "$d/src" "$2" >/dev/null
  ditto -c -k --keepParent "$d/src/Hidden Bar.app" "$d/prior.zip"
  prior_len="$(stat -f %z "$d/prior.zip")"
  ( export TMPDIR="$d/tmp" STUB_CURL_FILE="$d/prior.zip"
    T=""; make_tmp; setup_traps
    OUT="$d/out"; OP_SOURCE=connect; VER=1.12.0; BUILD=19; PRIOR_TAG=v1.11.2; HELPER="$H"
    EXPORT_APP="$(make_bundle "$d/export" "$PUB")"
    /usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$EXPORT_APP/Contents/Info.plist"
    cp "$F/notes-1.12.0.html" "$OUT/release-notes.html"
    VZIP="$OUT/Hidden-Bar-v$VER-macos.zip"; cp "$F/payload.bin" "$VZIP"; ZIP_LEN="$(stat -f %z "$VZIP")"; ZIP_SIG="$SIG"
    sed "s|length=\"2026759\"|length=\"$prior_len\"|" "$F/prior-1.xml" > "$T/prior-appcast.xml"
    [ "${3:-}" != bad-version ] || sed -i '' 's|<sparkle:shortVersionString>1.11.2<|<sparkle:shortVersionString>../x<|' "$T/prior-appcast.xml"
    if [ "${3:-}" = verify-ok ]; then helper() { if [ "$1" = verify ]; then return 0; fi; "$HELPER" "$@"; }; fi   # the fixture cannot sign a prior zip
    stage_appcast ) > "$d/stdout" 2>&1
  echo $? > "$d/rc"
}
appcast_run key-differs "$(cat "$F/wrongkey.pub.b64")"
prior_key_differs() { # the prior-zip branch ran and refused: the latest published app has another key
  local o="$WORK/ac-key-differs/stdout"
  [ "$(cat "$WORK/ac-key-differs/rc")" = 1 ] && grep -q 'Prior app key: FAIL: SUPublicEDKey differs' "$o" &&
  ! grep -q 'Enclosure 1.11.2' "$o" && [ ! -e "$WORK/ac-key-differs/out/appcast.xml" ] && [ -f "$WORK/ac-key-differs/out/appcast.xml.unverified" ]
}
t pubkey-differs-from-prior-fails prior_key_differs
appcast_run key-same "$PINNED_PUBKEY"
prior_key_same() { # positive control: the same branch accepts the pinned key and moves on to the next check
  local o="$WORK/ac-key-same/stdout"
  grep -q 'Prior app key: equals the pinned key' "$o" && ! grep -q 'Prior app key: FAIL' "$o" && grep -q 'Enclosure 1.11.2: FAIL' "$o"
}
t pubkey-equals-prior-passes prior_key_same
appcast_run verified "$PINNED_PUBKEY" verify-ok
appcast_published_after_checks() { # appcast.xml appears only once every check passed
  local d="$WORK/ac-verified"
  [ "$(cat "$d/rc")" = 0 ] && [ -f "$d/out/appcast.xml" ] && [ ! -e "$d/out/appcast.xml.unverified" ] ||
    { echo "rc $(cat "$d/rc"); $(ls "$d/out" | tr '\n' ' ')"; return 1; }
}
t appcast-named-only-after-checks appcast_published_after_checks
appcast_run bad-version "$PINNED_PUBKEY" bad-version
unsafe_version() { # a prior item's shortVersionString never reaches a path or a download
  local o="$WORK/ac-bad-version/stdout"
  [ "$(cat "$WORK/ac-bad-version/rc")" = 1 ] && grep -q "FAIL: a prior item's shortVersionString is not" "$o" &&
  ! grep -q 'Prior app key' "$o"
}
t appcast-unsafe-short-version-refused unsafe_version

# main() with every stage that builds, signs or notarizes replaced by a marker stub, so only
# the orchestration is real: the order of stages, the exit code and the report.
main_run() { # case-name check_app-outcome(pass|fail) : rc, stdout and out/ under $WORK/main-<case-name>
  local d="$WORK/main-$1" outcome="$2"
  mkdir -p "$d/tmp/trashed" "$d/marks"
  ( export TMPDIR="$d/tmp"
    FAILED=0; N=0; SKIPPED=""; DRAFT_NOTE=""; EDKEY=""     # globals earlier cases left behind
    stage_preflight() { PRE_STATE=stub; HEAD_SHA=abc1234; TREE_NOTE="stubbed"; row "Preflight" "stub" "stubbed"; }
    stage_tests() { row "Tests" "stub" "SKIPPED (stub)"; }
    stage_build() { mkdir -p "$OUT/export"; cp -R "$APP_NONE" "$OUT/export/"; : > "$d/marks/build"; }
    stage_notarize() { : > "$d/marks/notarize"; return 0; }
    stage_zips() { : > "$d/marks/zips"; return 0; }
    stage_sign() { : > "$d/marks/sign"; return 0; }
    stage_appcast() { : > "$d/marks/appcast"; return 0; }
    stage_smoke() { : > "$d/marks/smoke"; return 0; }
    if [ "$outcome" = pass ]; then check_app() { row "App checks" "stub" "ok"; return 0; }; fi
    main --notes "$d/notes.html" --out "$d/out" ) > "$d/stdout" 2>&1
  echo $? > "$d/rc"
}
main_run check-app-fails fail
main_check_app_fails() {
  local d="$WORK/main-check-app-fails" c
  c="$d/out/checks.md"
  [ "$(cat "$d/rc")" = 1 ] && [ -f "$d/marks/build" ] && grep -q '^| [0-9]* | Signature: identity, timestamp, runtime | .* | FAIL: ' "$c" &&
  grep -q '^Result: FAILED (exit 1)' "$c" && ! grep -q 'Result: every check passed' "$c" &&
  [ -z "$(ls "$d/marks" | grep -v '^build$')" ]
}
t main-check-app-failure-exits-1 main_check_app_fails
main_run all-pass pass
main_all_pass() { # positive control: the same harness exits 0 and runs every later stage when check_app passes
  local d="$WORK/main-all-pass"
  [ "$(cat "$d/rc")" = 0 ] && grep -q '^Result: every check passed' "$d/out/checks.md" &&
  [ "$(ls "$d/marks" | tr '\n' ' ')" = "appcast build notarize sign smoke zips " ]
}
t main-all-stages-pass-exits-0 main_all_pass

# ---- report -----------------------------------------------------------------------------

report_shape() {
  local o="$WORK/report"; mkdir -p "$o"
  OUT="$o"; VER=1.12.0; BUILD=19; HEAD_SHA=abc1234; TREE_NOTE="clean"; PRIOR_TAG=v1.11.2; : > "$ROWS_FILE"; N=0; FAILED=0
  row "Versions" "grep" "1.12.0 (19)"
  write_report 0 >/dev/null && local c="$o/checks.md" &&
  head -1 "$c" | grep -qx '# Hidden Bar v1.12.0 release checks' && grep -q 'Nothing was tagged or uploaded.' "$c" &&
  grep -qx '| # | Check | Command | Result |' "$c" && grep -q '^| 2 | No key material left | .* | 0 hits |$' "$c" &&
  grep -qx '## Notes for the publish step' "$c" && grep -q 'gh release upload v1.12.0 Hidden-Bar-v1.12.0-macos.zip Hidden-Bar-macos.zip appcast.xml' "$c"
  local rc=$?; OUT=""; return $rc
}
t report-shape report_shape
report_branch() { # the branch line comes from the repo root, whatever the working directory
  local o="$WORK/report-cwd" want
  want="$(command git -C "$ROOT" rev-parse --abbrev-ref HEAD)"; mkdir -p "$o"
  ( cd "$WORK" && OUT="$o"; VER=1.12.0; HEAD_SHA=abc1234; : > "$ROWS_FILE"; write_report 0 >/dev/null )
  grep -qF "branch \`$want\`," "$o/checks.md"
}
t report-branch-from-repo-root report_branch

echo
echo "test-release: $PASSED passed, $FAILED_N failed, $SKIPPED_N skipped${FAILED_NAMES:+ (failed:$FAILED_NAMES)}"
[ "$FAILED_N" = 0 ]
