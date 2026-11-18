#!/bin/bash
# scripts/release.sh : build and verify the direct (GitHub, Sparkle) release artifacts.
#
#   scripts/release.sh --notes <html-file> [--out <dir>] [--skip-tests] [--no-smoke]
#   scripts/release.sh --check-app <path/to/Hidden Bar.app>
#   scripts/release.sh --guard-selftest
#   scripts/release.sh --help
#
# Stages: preflight, tests, archive + export, app checks, notarize, zips, EdDSA sign,
# appcast, smoke test (with host restore), report. Output under --out (default
# build/release-<version>/): both zips, appcast.xml, checks.md, SHA256SUMS, notary JSON.
#
# It never tags, pushes, creates, uploads or publishes: `gh` and `git` are wrapped to allow
# read verbs only. The publish steps are printed as text at the end of checks.md.
#
# Secrets: the ASC API key lives only in a mode 700 temp dir (files 600) and is truncated as
# soon as notarytool is done; the Sparkle EdDSA key is streamed to sign_update by process
# substitution and never written to disk. Both come from 1Password, local Connect first.
#
# Exit: 0 every check passed (or was skipped on request) | 1 a check failed (checks.md says
# which) | 2 usage or preflight error.
#
# Test seam: RELEASE_SH_SOURCE_ONLY=1 source scripts/release.sh defines the functions and
# runs nothing (scripts/test-release.sh). Bash 3.2 compatible (macOS /bin/bash).

case "$-" in *x*) echo "release.sh: refusing to run with xtrace on (it would print secrets)" >&2; exit 2 ;; esac
case ":${SHELLOPTS:-}:" in *:xtrace:*) echo "release.sh: refusing to run with SHELLOPTS=xtrace" >&2; exit 2 ;; esac

set -u -o pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$ROOT/Hidden Bar.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
PKG_RESOLVED="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CHANGELOG="$ROOT/CHANGELOG.md"
HELPER_SRC="$ROOT/scripts/release-helper.swift"

REPO_SLUG="consolelabs/hidden"
TEAM_ID="W777S7V8TN"
BUNDLE_ID="com.dwarvesv.minimalbar"
INSTALLED_APP="${HB_INSTALLED_APP:-/Applications/Hidden Bar.app}"
# Pinned: change only in a reviewed commit. Installed copies trust exactly this key and feed.
PINNED_FEED_URL="https://github.com/consolelabs/hidden/releases/latest/download/appcast.xml"
PINNED_PUBKEY="C7MH2NS46vKD4nNh9i4BmFzXLSAbP2jM5qZcaPw9u3w="
VAULT="dfoundation-prod"
ASC_TITLE_SUFFIX="Hacker Bar Release"
EDDSA_TITLE="Hidden Bar Sparkle EdDSA private key"
EDDSA_REF="op://$VAULT/$EDDSA_TITLE/password"
CONNECT_HOST="http://127.0.0.1:8090"
CONNECT_TOKEN_FILE="$HOME/op-connect/.connect-token"
SPARKLE_CACHE_ROOT="${HB_SPARKLE_CACHE:-$HOME/.cache/hidden-bar/sparkle}"
PEM_MARK="-----BEGIN PRIVATE"" KEY-----"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# The sha256 GitHub reports for the Sparkle release tarball (trust on first use of GitHub's
# own asset digest). sign_update receives the EdDSA key, so an unpinned version stops the run.
sparkle_pinned_digest() {
  case "$1" in
    2.10.1) echo "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27" ;;
    *) return 1 ;;
  esac
}

# ---- read-only guards ---------------------------------------------------------------------

guard_refuse() { echo "release.sh: refused (read-only guard): $*" >&2; exit 2; }
guard_pass() { if [ -n "${GUARD_DRY:-}" ]; then echo "allowed: $*"; return 0; fi; command "$@"; }

gh() {
  local a
  case "${1:-} ${2:-}" in
    "release view"|"release list") ;;
    "release download")
      for a in "$@"; do case "$a" in --clobber|--skip-existing) guard_refuse gh "$@" ;; esac; done ;;
    api\ *)
      for a in "$@"; do
        case "$a" in -X*|--method*|-f*|-F*|--field*|--raw-field*|--input*|graphql) guard_refuse gh "$@" ;; esac
      done ;;
    *) guard_refuse gh "$@" ;;
  esac
  guard_pass gh "$@"
}

git() {
  local a
  case "${1:-}" in status|rev-parse|log|diff|describe|ls-files) ;; *) guard_refuse git "$@" ;; esac
  for a in "$@"; do case "$a" in --output*|--ext-diff|-c|-C) guard_refuse git "$@" ;; esac; done
  guard_pass git "$@"
}

guard_selftest() {
  local ok=1 rc case_
  echo "| Command | Expected | Got |"
  echo "|---|---|---|"
  while IFS= read -r case_; do
    [ -n "$case_" ] || continue
    ( GUARD_DRY=1; eval "$case_" ) >/dev/null 2>&1; rc=$?
    if [ "$rc" = 2 ]; then echo "| \`$case_\` | refused (2) | refused (2) |"
    else echo "| \`$case_\` | refused (2) | ALLOWED ($rc) |"; ok=0; fi
  done <<'EOF'
gh release upload v0.0.0 x.zip
gh release create v0.0.0
gh release edit v0.0.0 --draft=false
gh release delete v0.0.0
gh release download v0.0.0 --clobber
gh api -X POST repos/dwarvesf/hidden/releases
gh api -f tag_name=v0 repos/dwarvesf/hidden/releases
gh api graphql -f query=x
gh pr create
git tag v0.0.0
git push origin HEAD
git -C . push
git commit -m x
git checkout develop
git diff --output=/tmp/x
EOF
  while IFS= read -r case_; do
    [ -n "$case_" ] || continue
    ( GUARD_DRY=1; eval "$case_" ) >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then echo "| \`$case_\` | allowed (0) | allowed (0) |"
    else echo "| \`$case_\` | allowed (0) | REFUSED ($rc) |"; ok=0; fi
  done <<'EOF'
gh release view v1.12.0 -R dwarvesf/hidden
gh release download v1.11.2 -R dwarvesf/hidden --pattern appcast.xml
gh release list -R dwarvesf/hidden
gh api repos/dwarvesf/hidden/releases/latest
git status --porcelain
git rev-parse HEAD
EOF
  [ "$ok" = 1 ] && { echo "guard-selftest: every write refused, every read allowed"; return 0; }
  echo "guard-selftest: FAILED"; return 1
}

# ---- rows and the report ------------------------------------------------------------------

T=""; OUT=""; ROWS_FILE=""; N=0; FAILED=0; SKIPPED=""
VER=""; BUILD=""; HEAD_SHA=""; TREE_NOTE=""; PRIOR_TAG=""; DRAFT_NOTE=""
EDKEY=""; OP_SOURCE=""; ASC_KEY_ID=""; ASC_ISSUER=""
SMOKE_STARTED=0; SMOKE_RESTORED=0; SMOKE_DIR=""

cell() { printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\\|/g'; }

row() { # check, command, result
  N=$((N + 1))
  [ -z "$ROWS_FILE" ] || printf '| %s | %s | `%s` | %s |\n' "$N" "$(cell "$1")" "$(cell "$2")" "$(cell "$3")" >> "$ROWS_FILE"
  printf 'release.sh: [%s] %s: %s\n' "$N" "$1" "$3"
}

fail_row() { row "$1" "$2" "FAIL: $3"; FAILED=1; }

# capture CMD... : run CMD in this shell (so the globals it sets persist), its output into R
R=""
capture() {
  local rc
  "$@" > "$T/capture.txt" 2>&1; rc=$?
  R="$(cat "$T/capture.txt")"; : > "$T/capture.txt"
  return "$rc"
}

make_tmp() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/hb-release.XXXXXX")" || { echo "release.sh: mktemp failed" >&2; exit 2; }
  T="$(cd "$T" && pwd -P)"
  chmod 700 "$T"; mkdir -m 700 "$T/secret"
  ROWS_FILE="$T/rows.md"; : > "$ROWS_FILE"
}

secrets_wipe() {
  local f
  [ -n "$T" ] && [ -d "$T/secret" ] || return 0
  for f in "$T/secret"/* "$T/secret"/.[!.]*; do [ -f "$f" ] && : > "$f"; done
  return 0
}

tmp_dispose() {
  local dest
  [ -n "$T" ] && [ -d "$T" ] || return 0
  secrets_wipe
  if trash "$T" >/dev/null 2>&1; then T=""; return 0; fi
  if [ -n "$OUT" ] && [ -d "$OUT" ]; then dest="$OUT/.discard-$(basename "$T")"; else dest="$ROOT/build/.discard-$(basename "$T")"; mkdir -p "$ROOT/build"; fi
  mv "$T" "$dest" 2>/dev/null || echo "release.sh: could not trash or move $T (its secret files are truncated)" >&2
  T=""
}

unregister_scratch_copies() {
  local app
  [ -n "$OUT" ] && [ -x "$LSREGISTER" ] || return 0
  for app in "$OUT/export/Hidden Bar.app" "$OUT/unzip/Hidden Bar.app" "$OUT/HiddenBar.xcarchive/Products/Applications/Hidden Bar.app"; do
    [ -d "$app" ] && "$LSREGISTER" -u "$app" >/dev/null 2>&1
  done
  return 0
}

on_exit() {
  if [ "$SMOKE_STARTED" = 1 ] && [ "$SMOKE_RESTORED" = 0 ]; then smoke_restore >/dev/null 2>&1; fi
  unregister_scratch_copies
  tmp_dispose
}

setup_traps() {
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

leak_scan() { # paths... : prints "clean" (rc 0) or the files holding key material (rc 1)
  local hits=""
  hits="$(grep -rlF -- "$PEM_MARK" "$@" 2>/dev/null)"
  if [ -n "$EDKEY" ]; then hits="$hits$(grep -rlF -f <(printf '%s\n' "$EDKEY") "$@" 2>/dev/null)"; fi
  if [ -z "$hits" ]; then echo clean; return 0; fi
  printf '%s\n' "$hits" | sort -u | tr '\n' ' '; return 1
}

write_report() { # exit-code
  local code="$1" scan
  [ -n "$OUT" ] && [ -d "$OUT" ] || return 0
  if scan="$(leak_scan "$OUT")"; then
    row "No key material left" "grep -rlF <PEM marker> and <EdDSA key from memory> over --out and the run log" "0 hits"
  else
    fail_row "No key material left" "grep -rlF over --out" "key material found in: $scan"; code=1
  fi
  if [ -f "$OUT/appcast.xml" ]; then
    ( cd "$OUT" && shasum -a 256 Hidden-Bar-v"$VER"-macos.zip Hidden-Bar-macos.zip appcast.xml release-notes.html > SHA256SUMS 2>/dev/null )
  fi
  {
    echo "# Hidden Bar v$VER release checks"
    echo
    printf 'Built %s on %s (macOS %s, %s), branch `%s`, HEAD `%s` (%s). Build %s. Nothing was tagged or uploaded.' \
      "$(LC_ALL=C date -u '+%Y-%m-%d %H:%M UTC')" "$(scutil --get ComputerName 2>/dev/null || hostname)" "$(sw_vers -productVersion)" \
      "$(xcodebuild -version 2>/dev/null | head -1)" "$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null)" "${HEAD_SHA:-?}" "${TREE_NOTE:-tree not checked}" "${BUILD:-?}"
    [ -z "$SKIPPED" ] || printf ' SKIPPED on request:%s.' "$SKIPPED"
    echo
    echo
    echo "| # | Check | Command | Result |"
    echo "|---|---|---|---|"
    cat "$ROWS_FILE"
    echo
    if [ "$code" = 0 ]; then
      echo "Result: every check passed${SKIPPED:+ (skipped:$SKIPPED)}. Checksums: \`SHA256SUMS\`."
    else
      echo "Result: FAILED (exit $code). Do not publish anything from this folder."
    fi
    echo
    echo "## Notes for the publish step"
    echo
    echo "- Valid only while the latest published release is \`${PRIOR_TAG:-?}\` (the appcast keeps its items). If another release was published since, rerun."
    echo "- Tag the release commit \`v$VER\` (HEAD above), then create the release as a draft: \`gh release create v$VER --draft --title 'v$VER' -R $REPO_SLUG\`.${DRAFT_NOTE:+ $DRAFT_NOTE}"
    echo "- Upload three assets to the draft: \`gh release upload v$VER Hidden-Bar-v$VER-macos.zip Hidden-Bar-macos.zip appcast.xml -R $REPO_SLUG\`."
    echo "- Publish the draft, then check \`curl -sIL $PINNED_FEED_URL\` ends in 200 and \`curl -sIL https://github.com/$REPO_SLUG/releases/download/v$VER/Hidden-Bar-v$VER-macos.zip\` ends in 200."
    echo "- The appcast pubDate is the build time; Sparkle orders by build number, so a later publish time does not matter."
    echo "- Homebrew cask and App Store are separate, manual steps."
  } > "$OUT/checks.md"
  return "$code"
}

finish() { # exit-code
  local code="$1"
  [ "$code" = 0 ] && [ "$FAILED" = 1 ] && code=1
  write_report "$code" || code=$?
  [ -z "$OUT" ] || echo "release.sh: wrote $OUT/checks.md (exit $code)"
  exit "$code"
}

# ---- inputs -------------------------------------------------------------------------------

read_versions() { # pbxproj : prints "<marketing> <build>", rc 1 with the distinct values when they disagree
  local mv cv
  mv="$(grep -o 'MARKETING_VERSION = [^;]*;' "$1" | sed 's/.*= //; s/;$//' | sort | uniq -c)"
  cv="$(grep -o 'CURRENT_PROJECT_VERSION = [^;]*;' "$1" | sed 's/.*= //; s/;$//' | sort | uniq -c)"
  if [ "$(printf '%s\n' "$mv" | grep -c .)" != 1 ] || [ "$(printf '%s\n' "$cv" | grep -c .)" != 1 ]; then
    echo "versions disagree: MARKETING_VERSION [$(echo $mv)], CURRENT_PROJECT_VERSION [$(echo $cv)]"; return 1
  fi
  mv="$(echo $mv | awk '{print $2}')"; cv="$(echo $cv | awk '{print $2}')"
  case "$mv" in *[!0-9.]*|"") echo "MARKETING_VERSION '$mv' is not numeric"; return 1 ;; esac
  case "$cv" in *[!0-9]*|"") echo "CURRENT_PROJECT_VERSION '$cv' is not an integer"; return 1 ;; esac
  echo "$mv $cv"
}

check_changelog() { # file version
  grep -qE "^## v${2//./\\.}([[:space:]]|\$)" "$1"
}

check_notes() { # file : prints the reason and rc 1 when unusable
  [ -f "$1" ] || { echo "notes file $1 not found"; return 1; }
  grep -q '[^[:space:]]' "$1" || { echo "notes file is empty"; return 1; }
  if grep -qF ']]>' "$1"; then echo "notes contain ]]>, which would end the CDATA"; return 1; fi
  if grep -qE '</?item' "$1"; then echo "notes contain an <item> tag"; return 1; fi
  if LC_ALL=C grep -q $'\r' "$1"; then echo "notes contain CR bytes"; return 1; fi
  return 0
}

check_clean_tree() { # dir : prints the dirty paths, rc 1 when dirty
  local st
  st="$(cd "$1" && git status --porcelain --untracked-files=all)" || { echo "git status failed"; return 1; }
  [ -z "$st" ] && return 0
  printf '%s\n' "$st" | head -10 | tr '\n' ';'; return 1
}

tree_state() { # dir : "<head sha> <porcelain digest>"
  (cd "$1" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(git status --porcelain --untracked-files=all | shasum -a 256 | cut -c1-16)")
}

check_tree_unchanged() { # dir expected-state : rc 1 and the changed paths when HEAD or the tree moved
  local now
  now="$(tree_state "$1")"
  [ "$now" = "$2" ] && return 0
  echo "HEAD or tree changed since preflight (was ${2%% *}, now ${now%% *}): $(cd "$1" && git status --porcelain --untracked-files=all | head -5 | tr '\n' ';')"
  return 1
}

check_tag_state() { # version : rc 0 absent, 0 + DRAFT_NOTE draft, 1 published, 3 GitHub error
  local out rc
  out="$(gh release view "v$1" -R "$REPO_SLUG" --json isDraft --jq .isDraft 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    case "$out" in
      true) DRAFT_NOTE="A draft release v$1 already exists; upload to it instead of creating one."; return 0 ;;
      false) return 1 ;;
    esac
    return 3
  fi
  case "$out" in *"release not found"*|*"Not Found"*) return 0 ;; esac
  echo "$out" | head -2; return 3
}

fetch_prior_appcast() { # dest-file : the latest published release's appcast.xml; sets PRIOR_TAG
  local info tag draft has dir
  info="$(gh release view -R "$REPO_SLUG" --json tagName,isDraft,assets \
    --jq '[.tagName, (.isDraft|tostring), (([.assets[].name] | index("appcast.xml")) != null | tostring)] | join(" ")' 2>&1)" \
    || { echo "gh release view (latest) failed: $(echo "$info" | head -1)"; return 3; }
  read -r tag draft has <<EOF
$info
EOF
  [ -n "$tag" ] && [ "$draft" = false ] || { echo "latest release is not a published release: $info"; return 3; }
  [ "$has" = true ] || { echo "latest published release $tag has no appcast.xml asset"; return 1; }
  dir="$(dirname "$1")/prior-feed"; mkdir -p "$dir"
  gh release download "$tag" -R "$REPO_SLUG" --pattern appcast.xml --dir "$dir" >/dev/null 2>&1 \
    || { echo "could not download appcast.xml from $tag"; return 3; }
  mv "$dir/appcast.xml" "$1" || return 3
  PRIOR_TAG="$tag"
}

sparkle_version() { # Package.resolved : the pinned Sparkle version
  local i=0 id
  while id="$(plutil -extract "pins.$i.identity" raw -o - "$1" 2>/dev/null)"; do
    [ "$id" = sparkle ] && { plutil -extract "pins.$i.state.version" raw -o - "$1"; return; }
    i=$((i + 1))
  done
  return 1
}

sparkle_tools() { # version [extract-dir] : check the cached tarball (download once); extract sign_update fresh
  local ver="$1" dest="${2:-}" want got cache tb copy
  want="$(sparkle_pinned_digest "$ver")" || { echo "no pinned digest for Sparkle $ver; pin it in release.sh after checking GitHub's asset digest"; return 2; }
  cache="$SPARKLE_CACHE_ROOT/$ver"; tb="$cache/Sparkle-$ver.tar.xz"
  if [ ! -f "$tb" ]; then
    mkdir -p "$cache"
    gh release download "$ver" -R sparkle-project/Sparkle --pattern "Sparkle-$ver.tar.xz" --dir "$cache" >/dev/null 2>&1 \
      || { echo "could not download Sparkle-$ver.tar.xz"; return 2; }
  fi
  copy="$tb"
  if [ -n "$dest" ]; then mkdir -p "$dest"; copy="$dest/Sparkle-$ver.tar.xz"; cp "$tb" "$copy" || return 2; fi
  got="$(shasum -a 256 "$copy" | awk '{print $1}')"
  [ "$got" = "$want" ] || { echo "Sparkle-$ver.tar.xz digest mismatch (cache: $tb); refusing to run its sign_update"; return 2; }
  [ -z "$dest" ] && return 0
  tar -xJf "$copy" -C "$dest" ./bin/sign_update 2>/dev/null && [ -x "$dest/bin/sign_update" ] \
    || { echo "sign_update not found in Sparkle-$ver.tar.xz"; return 2; }
}

# ---- 1Password (Connect first, then the ambient service account) ---------------------------

op_connect() { OP_CONNECT_HOST="$CONNECT_HOST" OP_CONNECT_TOKEN="$(cat "$CONNECT_TOKEN_FILE" 2>/dev/null)" command op "$@"; }
op_sa() { env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op "$@"; }
op_run() {
  case "$OP_SOURCE" in
    connect) op_connect "$@" ;;
    service-account) op_sa "$@" ;;
    *) return 1 ;;
  esac
}

op_select_source() { # items-json-out : sets OP_SOURCE, writes the vault item list (metadata only)
  if curl -sf --max-time 3 -o /dev/null "$CONNECT_HOST/heartbeat" 2>/dev/null \
     && op_connect item list --vault "$VAULT" --format json > "$1" 2>/dev/null; then
    OP_SOURCE=connect; return 0
  fi
  if op_sa item list --vault "$VAULT" --format json > "$1" 2>/dev/null; then OP_SOURCE=service-account; return 0; fi
  OP_SOURCE=""; return 1
}

item_ids_matching() { # items-json mode(suffix|exact) text : one id per matching title
  local i=0 title
  while title="$(plutil -extract "$i.title" raw -o - "$1" 2>/dev/null)"; do
    case "$2" in
      suffix) case "$title" in *"$3") plutil -extract "$i.id" raw -o - "$1"; echo ;; esac ;;
      exact) [ "$title" = "$3" ] && { plutil -extract "$i.id" raw -o - "$1"; echo; } ;;
    esac
    i=$((i + 1))
  done
}

asc_fetch() { # writes $T/secret/AuthKey.p8, sets ASC_KEY_ID and ASC_ISSUER; prints a reason on failure
  local list="$T/secret/items.json" item="$T/secret/item.json" ids id i=0 label f
  op_run item list --vault "$VAULT" --format json > "$list" 2>/dev/null || { echo "item list failed via $OP_SOURCE"; return 1; }
  ids="$(item_ids_matching "$list" suffix "$ASC_TITLE_SUFFIX" | grep .)"
  [ "$(printf '%s\n' "$ids" | grep -c .)" = 1 ] || { echo "expected exactly one item titled '*$ASC_TITLE_SUFFIX'"; return 1; }
  id="$ids"
  op_run item get "$id" --vault "$VAULT" --format json > "$item" 2>/dev/null || { echo "item get failed"; return 1; } # raw-op-ok: one read per release, Connect first
  ASC_KEY_ID=""; ASC_ISSUER=""
  while plutil -extract "fields.$i" raw -o - "$item" >/dev/null 2>&1; do
    label="$(plutil -extract "fields.$i.label" raw -o - "$item" 2>/dev/null) $(plutil -extract "fields.$i.id" raw -o - "$item" 2>/dev/null)"
    f="$T/secret/field.$i"
    if plutil -extract "fields.$i.value" raw -o "$f" "$item" >/dev/null 2>&1; then
      if grep -qF -- "$PEM_MARK" "$f"; then cat "$f" > "$T/secret/AuthKey.p8"
      elif printf '%s' "$label" | grep -qiE 'key ?id'; then ASC_KEY_ID="$(cat "$f")"
      elif printf '%s' "$label" | grep -qi 'issuer'; then ASC_ISSUER="$(cat "$f")"
      fi
      : > "$f"
    fi
    i=$((i + 1))
  done
  : > "$item"; : > "$list"
  [ -s "$T/secret/AuthKey.p8" ] && [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER" ] \
    || { echo "ASC item lacks a private key, a key id or an issuer field"; return 1; }
}

# ---- app checks ---------------------------------------------------------------------------

code_parts() { # app : the app, every nested bundle, and every Mach-O executable
  local f
  echo "$1"
  find "$1/Contents" \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' -o -name '*.appex' \) -type d 2>/dev/null
  find "$1/Contents" -type f -perm +111 2>/dev/null | while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q 'Mach-O' && echo "$f"
  done
}

check_identity() { # app : rc 0 when every code part is Developer ID (team), timestamped, hardened runtime
  local part name out bad="" n=0
  while IFS= read -r part; do
    [ -n "$part" ] || continue
    n=$((n + 1))
    name="${part#"$1"/}"; [ "$part" = "$1" ] && name="app"
    out="$(codesign -dvv "$part" 2>&1)"
    if ! printf '%s\n' "$out" | grep -qE "^Authority=Developer ID Application: .*\\($TEAM_ID\\)\$"; then bad="$bad $name (not Developer ID $TEAM_ID)"
    elif ! printf '%s\n' "$out" | grep -q '^Timestamp='; then bad="$bad $name (no secure timestamp)"
    elif ! printf '%s\n' "$out" | grep -qE '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime'; then bad="$bad $name (no hardened runtime)"
    fi
  done <<EOF
$(code_parts "$1")
EOF
  if [ -z "$bad" ]; then echo "$n parts: Developer ID Application ($TEAM_ID), secure timestamp, runtime"; return 0; fi
  echo "$n parts checked;$bad"; return 1
}

check_sandbox() { # app : rc 0 only for an entitlements blob without app-sandbox
  local ent
  ent="$(codesign -d --entitlements - --xml "$1" 2>/dev/null)"
  if [ -z "$ent" ]; then echo "no entitlements blob: unverifiable"; return 1; fi
  if printf '%s' "$ent" | grep -q 'com.apple.security.app-sandbox'; then echo "app-sandbox entitlement present"; return 1; fi
  echo "entitlements present, no app-sandbox"; return 0
}

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

check_pubkey() { # app : the app's SUPublicEDKey equals the pinned key
  local k; k="$(plist_get "$1" SUPublicEDKey)"
  [ "$k" = "$PINNED_PUBKEY" ] && { echo "equals the pinned key"; return 0; }
  echo "SUPublicEDKey differs from the key pinned in release.sh (installed copies would reject updates)"; return 1
}

check_app() { # app [version build] : every row runs; rc 1 when any row failed
  local app="$1" ver="${2:-}" build="${3:-}" r id_ok=0 rc=0 v b
  [ -d "$app/Contents" ] || { fail_row "App bundle" "test -d" "$app is not an app bundle"; return 1; }
  if r="$(check_identity "$app")"; then id_ok=1; row "Signature: identity, timestamp, runtime" "codesign -dvv on every code part" "$r"
  else fail_row "Signature: identity, timestamp, runtime" "codesign -dvv on every code part" "$r"; rc=1; fi
  if r="$(check_sandbox "$app")"; then
    if [ "$id_ok" = 1 ]; then row "Unsandboxed" "codesign -d --entitlements - --xml" "$r"
    else fail_row "Unsandboxed" "codesign -d --entitlements - --xml" "$r, not credited: identity failed"; rc=1; fi
  else fail_row "Unsandboxed" "codesign -d --entitlements - --xml" "$r"; rc=1; fi
  if r="$(codesign --verify --deep --strict "$app" 2>&1)"; then row "Strict verify" "codesign --verify --deep --strict" "valid"
  else fail_row "Strict verify" "codesign --verify --deep --strict" "$(printf '%s' "$r" | head -2)"; rc=1; fi
  if otool -L "$app/Contents/MacOS/$(plist_get "$app" CFBundleExecutable)" 2>/dev/null | grep -q 'Sparkle.framework'; then
    row "Sparkle linked" "otool -L" "Sparkle.framework linked"
  else fail_row "Sparkle linked" "otool -L" "Sparkle.framework not linked"; rc=1; fi
  v="$(plist_get "$app" CFBundleShortVersionString)"; b="$(plist_get "$app" CFBundleVersion)"
  if [ -n "$ver" ] && { [ "$v" != "$ver" ] || [ "$b" != "$build" ]; }; then
    fail_row "Versions" "Info.plist vs project.pbxproj" "app $v ($b), project $ver ($build)"; rc=1
  else row "Versions" "Info.plist vs project.pbxproj" "$v ($b)"; fi
  if [ "$(plist_get "$app" SUFeedURL)" = "$PINNED_FEED_URL" ]; then row "Feed URL" "Info.plist SUFeedURL vs pinned" "$PINNED_FEED_URL"
  else fail_row "Feed URL" "Info.plist SUFeedURL vs pinned" "'$(plist_get "$app" SUFeedURL)' is not the pinned feed"; rc=1; fi
  if r="$(check_pubkey "$app")"; then row "EdDSA public key" "Info.plist SUPublicEDKey vs pinned" "$r"
  else fail_row "EdDSA public key" "Info.plist SUPublicEDKey vs pinned" "$r"; rc=1; fi
  return "$rc"
}

# ---- appcast checks -----------------------------------------------------------------------

first_item() { awk 's==0 && $0=="        <item>"{s=1} s==1{print} s==1 && $0=="        </item>"{exit}' "$1"; }

readback_new_item() { # appcast build short min-os url length : rc 1 and the mismatches
  local it bad=""
  it="$(first_item "$1")"
  printf '%s\n' "$it" | grep -qxF "            <sparkle:version>$2</sparkle:version>" || bad="$bad sparkle:version!=$2"
  printf '%s\n' "$it" | grep -qxF "            <sparkle:shortVersionString>$3</sparkle:shortVersionString>" || bad="$bad shortVersionString!=$3"
  printf '%s\n' "$it" | grep -qxF "            <sparkle:minimumSystemVersion>$4</sparkle:minimumSystemVersion>" || bad="$bad minimumSystemVersion!=$4"
  printf '%s\n' "$it" | grep -qF " url=\"$5\"" || bad="$bad url!=$5"
  printf '%s\n' "$it" | grep -qF " length=\"$6\"" || bad="$bad length!=$6"
  [ -z "$bad" ] && { echo "item 1: $3 ($2), min macOS $4, $6 bytes, $5"; return 0; }
  echo "item 1 disagrees with the build:$bad"; return 1
}

cut_cmp_prior() { # new-appcast prior-appcast scratch : the new feed minus its first item is byte-identical to the prior
  # awk ends its output with a newline, so the prior side gets one too when its last byte is
  # not one (the published 1.13.0 feed has none); every other byte still has to match
  awk 's==0 && $0=="        <item>"{s=1; next} s==1{ if ($0=="        </item>") s=2; next } {print}' "$1" > "$3"
  { cat "$2"; [ -z "$(tail -c 1 "$2")" ] || printf '\n'; } > "$3.prior"
  cmp -s "$3" "$3.prior"
}

count_items() { grep -cxF '        <item>' "$1"; }

# ---- smoke test helpers -------------------------------------------------------------------

running_exes() { # "pid path" for every process whose executable is a Hidden Bar binary
  local pid rest
  ps -axo pid=,comm= 2>/dev/null | while read -r pid rest; do
    case "$rest" in */"Hidden Bar.app/Contents/MacOS/Hidden Bar") echo "$pid $rest" ;; esac
  done
}

pids_of() { # app : pids running that app's executable
  local pid rest
  running_exes | while read -r pid rest; do [ "$rest" = "$1/Contents/MacOS/Hidden Bar" ] && echo "$pid"; done
}

smoke_assert_process() { # pid app build [exe] : the pid is alive, runs the app under test, and is that build
  local comm b exe="${4:-$2/Contents/MacOS/Hidden Bar}"
  kill -0 "$1" 2>/dev/null || { echo "pid $1 is not running"; return 1; }
  comm="$(ps -o comm= -p "$1" 2>/dev/null)"
  [ "$comm" = "$exe" ] || { echo "pid $1 runs '$comm', not the copy under test"; return 1; }
  b="$(plist_get "$2" CFBundleVersion)"
  [ "$b" = "$3" ] || { echo "the copy under test is build '$b', expected $3"; return 1; }
  echo "pid $1 runs $2 build $b"
}

quit_pid() { # pid : TERM, wait up to 10 s, then KILL
  local i=0
  kill -TERM "$1" 2>/dev/null || return 0
  while kill -0 "$1" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
  kill -0 "$1" 2>/dev/null && kill -KILL "$1" 2>/dev/null
  return 0
}

login_item_paths() { # sorted paths of login items named "Hidden Bar", or "unreadable"
  local raw
  raw="$(osascript -e 'tell application "System Events" to get the path of every login item whose name is "Hidden Bar"' 2>&1)" \
    || { echo "unreadable"; return 1; }
  printf '%s\n' "$raw" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep . | sort
}

installed_cdhash() { [ -d "$INSTALLED_APP" ] && codesign -dvvv "$INSTALLED_APP" 2>&1 | sed -n 's/^CDHash=//p' | head -1; }

smoke_baseline() {
  mkdir -p "$SMOKE_DIR"
  installed_cdhash > "$SMOKE_DIR/cdhash-before.txt"
  login_item_paths > "$SMOKE_DIR/loginitems-before.txt"
  pids_of "$INSTALLED_APP" > "$SMOKE_DIR/running-before.txt"
  if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    defaults export "$BUNDLE_ID" "$SMOKE_DIR/prefs-before.plist" && plutil -convert xml1 -o "$SMOKE_DIR/prefs-before.xml" "$SMOKE_DIR/prefs-before.plist"
  fi
}

smoke_restore() { # quit the copy under test, restore prefs, relaunch or repair, compare; rc 1 when the host differs
  local pid was_running diff=""
  SMOKE_RESTORED=1
  for pid in $(pids_of "$OUT/unzip/Hidden Bar.app"); do quit_pid "$pid"; done
  [ -f "$SMOKE_DIR/prefs-before.plist" ] && defaults import "$BUNDLE_ID" "$SMOKE_DIR/prefs-before.plist"
  was_running="$(grep -c . "$SMOKE_DIR/running-before.txt" 2>/dev/null)"
  if [ "${was_running:-0}" -gt 0 ] && [ -z "$(pids_of "$INSTALLED_APP")" ]; then open -g "$INSTALLED_APP"; sleep 5; fi
  login_item_paths > "$SMOKE_DIR/loginitems-after.txt"
  if ! cmp -s "$SMOKE_DIR/loginitems-before.txt" "$SMOKE_DIR/loginitems-after.txt" && [ -d "$INSTALLED_APP" ]; then
    open -g "$INSTALLED_APP"; sleep 5          # the installed app re-points its login item at itself
    if [ "${was_running:-0}" = 0 ]; then for pid in $(pids_of "$INSTALLED_APP"); do quit_pid "$pid"; done; fi
    login_item_paths > "$SMOKE_DIR/loginitems-after.txt"
  fi
  installed_cdhash > "$SMOKE_DIR/cdhash-after.txt"
  if [ -f "$SMOKE_DIR/prefs-before.plist" ]; then
    defaults export "$BUNDLE_ID" "$SMOKE_DIR/prefs-after.plist" && plutil -convert xml1 -o "$SMOKE_DIR/prefs-after.xml" "$SMOKE_DIR/prefs-after.plist"
    cmp -s "$SMOKE_DIR/prefs-before.xml" "$SMOKE_DIR/prefs-after.xml" || diff="$diff prefs"
  fi
  cmp -s "$SMOKE_DIR/cdhash-before.txt" "$SMOKE_DIR/cdhash-after.txt" || diff="$diff installed-CDHash"
  cmp -s "$SMOKE_DIR/loginitems-before.txt" "$SMOKE_DIR/loginitems-after.txt" \
    || diff="$diff login-items(before: $(tr '\n' ';' < "$SMOKE_DIR/loginitems-before.txt") after: $(tr '\n' ';' < "$SMOKE_DIR/loginitems-after.txt"))"
  unregister_scratch_copies
  [ -z "$diff" ] && return 0
  echo "differs after restore:$diff"; return 1
}

# ---- stages -------------------------------------------------------------------------------

HELPER=""
helper() { "$HELPER" "$@"; }

stage_preflight() { # notes-file : exit 2 on any failure
  local r t v pre missing="" sv
  for t in xcodebuild xcrun codesign ditto xmllint plutil swiftc gh op curl shasum tar trash spctl otool defaults; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  [ "$NO_SMOKE" = 1 ] || command -v osascript >/dev/null 2>&1 || missing="$missing osascript"
  [ -z "$missing" ] || { fail_row "Tools" "command -v" "missing:$missing"; finish 2; }
  row "Tools" "command -v" "all present"
  if r="$(check_clean_tree "$ROOT")"; then :; else fail_row "Clean tree" "git status --porcelain" "dirty: $r"; finish 2; fi
  pre="$(tree_state "$ROOT")"; HEAD_SHA="${pre%% *}"; PRE_STATE="$pre"; TREE_NOTE="clean at preflight"
  row "Clean tree" "git status --porcelain" "clean at $HEAD_SHA"
  row "Versions" "grep MARKETING_VERSION, CURRENT_PROJECT_VERSION in project.pbxproj" "$VER ($BUILD), every value equal"
  check_changelog "$CHANGELOG" "$VER" || { fail_row "CHANGELOG" "grep '^## v$VER'" "no '## v$VER' section"; finish 2; }
  row "CHANGELOG" "grep '^## v$VER'" "section present"
  r="$(check_notes "$1")" || { fail_row "Release notes" "notes file checks" "$r"; finish 2; }
  cp "$1" "$OUT/release-notes.html"
  row "Release notes" "notes file checks" "$(grep -c '<li>' "$1") list items, no ]]>, no item tags"
  security find-identity -v -p codesigning 2>/dev/null | grep -qE "\"Developer ID Application: .*\\($TEAM_ID\\)\"" \
    || { fail_row "Signing identity" "security find-identity -v -p codesigning" "no Developer ID Application ($TEAM_ID) identity"; finish 2; }
  row "Signing identity" "security find-identity -v -p codesigning" "Developer ID Application ($TEAM_ID) present"
  sv="$(sparkle_version "$PKG_RESOLVED")" || { fail_row "Sparkle pin" "Package.resolved" "no sparkle pin"; finish 2; }
  SPARKLE_VER="$sv"
  r="$(sparkle_tools "$sv")" || { fail_row "Sparkle tools" "shasum -a 256 Sparkle-$sv.tar.xz vs pinned" "$r"; finish 2; }
  row "Sparkle tools" "shasum -a 256 Sparkle-$sv.tar.xz vs pinned" "Sparkle $sv tarball matches the pinned digest"
  capture check_tag_state "$VER"; v=$?
  case "$v" in
    0) row "Tag" "gh release view v$VER" "${DRAFT_NOTE:-no release v$VER yet}" ;;
    1) fail_row "Tag" "gh release view v$VER" "v$VER is already a published release"; finish 2 ;;
    *) fail_row "Tag" "gh release view v$VER" "GitHub error: $R"; finish 2 ;;
  esac
  capture fetch_prior_appcast "$T/prior-appcast.xml" || { fail_row "Prior appcast" "gh release view (latest); gh release download --pattern appcast.xml" "$R"; finish 2; }
  xmllint --noout "$T/prior-appcast.xml" 2>/dev/null || { fail_row "Prior appcast" "xmllint --noout" "the published feed is not well-formed"; finish 2; }
  row "Prior appcast" "gh release download $PRIOR_TAG --pattern appcast.xml" "latest published $PRIOR_TAG, $(count_items "$T/prior-appcast.xml") item(s), well-formed"
  op_select_source "$T/secret/items.json" || { fail_row "1Password" "Connect heartbeat; op item list (metadata)" "neither Connect nor a service account can list $VAULT"; finish 2; }
  [ "$(item_ids_matching "$T/secret/items.json" suffix "$ASC_TITLE_SUFFIX" | grep -c .)" = 1 ] \
    || { : > "$T/secret/items.json"; fail_row "1Password" "op item list (metadata)" "not exactly one '*$ASC_TITLE_SUFFIX' item"; finish 2; }
  [ "$(item_ids_matching "$T/secret/items.json" exact "$EDDSA_TITLE" | grep -c .)" = 1 ] \
    || { : > "$T/secret/items.json"; fail_row "1Password" "op item list (metadata)" "no '$EDDSA_TITLE' item"; finish 2; }
  : > "$T/secret/items.json"
  row "1Password" "op item list --vault $VAULT (titles only)" "via $OP_SOURCE; ASC key item and EdDSA item found"
  HELPER="$T/release-helper"
  swiftc -O "$HELPER_SRC" -o "$HELPER" >"$T/helper-build.log" 2>&1 || { fail_row "Helper" "swiftc -O release-helper.swift" "build failed"; finish 2; }
  row "Helper" "swiftc -O scripts/release-helper.swift" "built"
}

stage_tests() {
  if [ "$SKIP_TESTS" = 1 ]; then row "Tests" "scripts/test.sh" "SKIPPED (--skip-tests)"; SKIPPED="$SKIPPED tests"; return 0; fi
  if bash "$ROOT/scripts/test.sh" > "$OUT/tests.log" 2>&1; then
    row "Tests" "bash scripts/test.sh" "$(grep -E '^Hidden Bar' "$OUT/tests.log" | awk '{print $(NF-2) " passed " $(NF-1) " failed"}' | tr '\n' ';' | sed 's/;$//'); exit 0"
  else
    fail_row "Tests" "bash scripts/test.sh" "failed, see tests.log: $(tail -4 "$OUT/tests.log" | tr '\n' ' ')"; finish 1
  fi
}

stage_build() {
  local archive="$OUT/HiddenBar.xcarchive" r
  xcodebuild archive -project "$PROJECT" -scheme 'Hidden Bar' -configuration Release-Direct -archivePath "$archive" \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Developer ID Application' \
    DEVELOPMENT_TEAM="$TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp > "$OUT/archive.log" 2>&1 \
    || { fail_row "Archive" "xcodebuild archive, Release-Direct, manual Developer ID, --timestamp" "failed, see archive.log"; finish 1; }
  row "Archive" "xcodebuild archive, Release-Direct, manual Developer ID, --timestamp" "ARCHIVE SUCCEEDED"
  r="$(check_tree_unchanged "$ROOT" "$PRE_STATE")" || { fail_row "Tree after archive" "git rev-parse HEAD; git status --porcelain" "$r"; finish 1; }
  /usr/libexec/PlistBuddy -c 'Add :method string developer-id' -c 'Add :destination string export' \
    -c "Add :teamID string $TEAM_ID" -c 'Add :signingStyle string manual' \
    -c 'Add :signingCertificate string Developer ID Application' "$T/export.plist" >/dev/null
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$T/export.plist" -exportPath "$OUT/export" > "$OUT/export.log" 2>&1 \
    || { fail_row "Export" "xcodebuild -exportArchive, method developer-id" "failed, see export.log"; finish 1; }
  row "Export" "xcodebuild -exportArchive, method developer-id" "EXPORT SUCCEEDED"
  r="$(check_tree_unchanged "$ROOT" "$PRE_STATE")" || { fail_row "Tree after export" "git rev-parse HEAD; git status --porcelain" "$r"; finish 1; }
  TREE_NOTE="clean; HEAD and tree re-checked after archive and export"
  row "Tree after build" "git rev-parse HEAD; git status --porcelain" "unchanged since preflight ($HEAD_SHA)"
}

stage_notarize() { # app
  local app="$1" r rc id status summary issues_type i log_ok=0 issues_note
  capture asc_fetch || { secrets_wipe; fail_row "ASC API key" "op item get (fields by pattern)" "$R"; return 1; }
  row "ASC API key" "op item get via $OP_SOURCE, fields by pattern" "read into a mode 700 temp dir, key file mode 600"
  ditto -c -k --keepParent "$app" "$T/submit.zip"
  xcrun notarytool submit "$T/submit.zip" --key "$T/secret/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait --timeout 2h --output-format json > "$OUT/notary-submit.json" 2> "$T/notary-submit.err"; rc=$?
  id="$(plutil -extract id raw -o - "$OUT/notary-submit.json" 2>/dev/null)"
  status="$(plutil -extract status raw -o - "$OUT/notary-submit.json" 2>/dev/null)"
  if [ -n "$id" ]; then
    for i in 1 2 3; do
      if xcrun notarytool log "$id" --key "$T/secret/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" "$OUT/notary-log.json" >/dev/null 2>&1; then log_ok=1; break; fi
      sleep 10
    done
  fi
  secrets_wipe; ASC_KEY_ID=""; ASC_ISSUER=""
  if [ "$log_ok" = 1 ]; then issues_note="$(plutil -extract issues json -o - "$OUT/notary-log.json" 2>/dev/null | head -c 300)"
  else issues_note="notary log unreadable after 3 tries"; fi
  if [ "$status" != Accepted ]; then
    fail_row "Notarization" "xcrun notarytool submit --wait --timeout 2h" "submission ${id:-none} status '${status:-none}' (rc $rc); issues: $issues_note"
    return 1
  fi
  [ "$log_ok" = 1 ] || { fail_row "Notarization" "xcrun notarytool log" "submission $id Accepted, but the notary log was unreadable after 3 tries, so its issues are unknown"; return 1; }
  summary="$(plutil -extract statusSummary raw -o - "$OUT/notary-log.json" 2>/dev/null)"
  issues_type="$(plutil -type issues "$OUT/notary-log.json" 2>/dev/null)"
  case "$issues_type" in
    "(any)"|"") ;;
    array) [ "$(plutil -extract issues raw -o - "$OUT/notary-log.json" 2>/dev/null)" = 0 ] \
             || { fail_row "Notarization" "xcrun notarytool log" "Accepted with issues: $(plutil -extract issues json -o - "$OUT/notary-log.json" | head -c 300)"; return 1; } ;;
  esac
  row "Notarization" "xcrun notarytool submit --wait (ASC key via $OP_SOURCE, temp files truncated after)" "submission $id: Accepted, ${summary:-no summary}, issues none"
  for i in 1 2 3; do xcrun stapler staple "$app" >/dev/null 2>&1 && break; sleep 15; done
  xcrun stapler validate "$app" >/dev/null 2>&1 || { fail_row "Staple" "xcrun stapler staple / validate" "staple failed after 3 tries"; return 1; }
  row "Staple" "xcrun stapler staple / validate" "worked"
  r="$(spctl -a -vvv -t exec "$app" 2>&1)"
  printf '%s\n' "$r" | grep -q '^source=Notarized Developer ID$' || { fail_row "Gatekeeper" "spctl -a -vvv -t exec" "$(printf '%s' "$r" | head -2)"; return 1; }
  row "Gatekeeper" "spctl -a -vvv -t exec" "accepted, source=Notarized Developer ID"
}

stage_zips() { # app
  local app="$1" u="$OUT/unzip/Hidden Bar.app" r
  ditto -c -k --sequesterRsrc --keepParent "$app" "$VZIP" && cp "$VZIP" "$SZIP" && cmp -s "$VZIP" "$SZIP" \
    || { fail_row "Zips" "ditto -c -k --sequesterRsrc --keepParent; cp; cmp" "failed"; return 1; }
  ZIP_LEN="$(stat -f %z "$VZIP")"
  row "Zips" "ditto -c -k --sequesterRsrc --keepParent; cp; cmp" "$(basename "$VZIP") $ZIP_LEN bytes; $(basename "$SZIP") byte-identical"
  mkdir -p "$OUT/unzip" && ditto -x -k "$VZIP" "$OUT/unzip" || { fail_row "Zip contents" "ditto -x -k" "unzip failed"; return 1; }
  r="$(spctl -a -vvv -t exec "$u" 2>&1)"
  if printf '%s\n' "$r" | grep -q '^source=Notarized Developer ID$' && xcrun stapler validate "$u" >/dev/null 2>&1 \
     && codesign --verify --deep --strict "$u" >/dev/null 2>&1; then
    row "Zip contents re-checked" "unzip to a fresh dir; spctl; stapler validate; codesign --verify --deep --strict" "Notarized Developer ID; staple valid; verify ok"
  else fail_row "Zip contents re-checked" "spctl; stapler validate; codesign --verify" "the unzipped app does not pass"; return 1; fi
}

stage_sign() {
  local line sig len pub r
  r="$(sparkle_tools "$SPARKLE_VER" "$T/sparkle")" || { fail_row "Sparkle tools" "re-hash the tarball; extract sign_update fresh" "$r"; return 1; }
  EDKEY="$(op_run read "$EDDSA_REF" 2>/dev/null)" # raw-op-ok: one read per release, Connect first
  [ -n "$EDKEY" ] || { fail_row "EdDSA sign" "op read (via $OP_SOURCE)" "could not read the EdDSA key"; return 1; }
  line="$("$T/sparkle/bin/sign_update" --ed-key-file <(printf '%s\n' "$EDKEY") "$VZIP" 2>/dev/null)"
  sig="$(printf '%s' "$line" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  len="$(printf '%s' "$line" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
  [ -n "$sig" ] && [ -n "$len" ] || { fail_row "EdDSA sign" "sign_update (Sparkle $SPARKLE_VER)" "no sparkle:edSignature or length in its output"; return 1; }
  [ "$len" = "$ZIP_LEN" ] || { fail_row "EdDSA sign" "sign_update" "length $len is not the zip size $ZIP_LEN"; return 1; }
  ZIP_SIG="$sig"
  row "EdDSA sign" "sign_update (Sparkle $SPARKLE_VER, tarball re-hashed), key streamed from 1Password via $OP_SOURCE" "signed; length $len"
  pub="$(plist_get "$EXPORT_APP" SUPublicEDKey)"
  if helper verify "$VZIP" "$sig" "$pub" >/dev/null && helper verify "$SZIP" "$sig" "$pub" >/dev/null; then
    row "Signature vs app key" "release-helper verify against the built app's SUPublicEDKey (== pinned)" "VALID for both zips"
  else fail_row "Signature vs app key" "release-helper verify" "INVALID"; return 1; fi
  cp "$VZIP" "$T/tampered.zip" && printf 'x' >> "$T/tampered.zip"
  helper verify "$T/tampered.zip" "$sig" "$pub" >/dev/null; r=$?
  [ "$r" = 1 ] || { fail_row "Negative control" "release-helper verify on the zip + 1 byte" "expected INVALID (exit 1), got exit $r"; return 1; }
  row "Negative control" "release-helper verify on the zip + 1 byte" "INVALID (exit 1)"
}

stage_appcast() {
  local new="$OUT/appcast.xml.unverified" prior="$T/prior-appcast.xml" minos url link pubdate r first=1 v s u l g f n_prior n_new pub
  minos="$(plist_get "$EXPORT_APP" LSMinimumSystemVersion)"
  url="https://github.com/$REPO_SLUG/releases/download/v$VER/Hidden-Bar-v$VER-macos.zip"
  link="https://github.com/$REPO_SLUG/releases/tag/v$VER"
  pubdate="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')"
  helper item --version "$BUILD" --short "$VER" --min-os "$minos" --notes "$OUT/release-notes.html" --url "$url" \
    --length "$ZIP_LEN" --sig "$ZIP_SIG" --pubdate "$pubdate" --link "$link" > "$T/new-item.xml" 2> "$T/item.err" \
    || { fail_row "Appcast item" "release-helper item" "$(cat "$T/item.err")"; return 1; }
  r="$(helper appcast --prior "$prior" --item "$T/new-item.xml" --out "$new" 2>&1)" \
    || { fail_row "Appcast merge" "release-helper appcast" "$r"; return 1; }
  xmllint --noout "$new" 2>/dev/null || { fail_row "Appcast" "xmllint --noout" "not well-formed"; return 1; }
  n_prior="$(count_items "$prior")"; n_new="$(count_items "$new")"
  [ "$n_new" = $((n_prior + 1)) ] || { fail_row "Appcast" "item count" "$n_new items, expected $((n_prior + 1))"; return 1; }
  row "Appcast" "release-helper appcast; xmllint --noout; item count" "well-formed; $n_new items, new item first"
  r="$(readback_new_item "$new" "$BUILD" "$VER" "$minos" "$url" "$ZIP_LEN")" || { fail_row "New item read-back" "fields vs app, zip, tag" "$r"; return 1; }
  row "New item read-back" "item 1 fields vs the built app, the zip size and the tag" "$r"
  cut_cmp_prior "$new" "$prior" "$T/cut.xml" || { fail_row "Prior items verbatim" "awk cut of item 1; cmp with the published feed" "the remaining feed differs from $PRIOR_TAG's appcast.xml"; return 1; }
  row "Prior items verbatim" "awk cut of item 1; cmp with the published feed" "$n_prior prior item(s) byte-identical to $PRIOR_TAG's appcast.xml"
  helper sigs "$new" "$T/sigs.tsv" 2>"$T/sigs.err" || { fail_row "Enclosure signatures" "release-helper sigs" "$(cat "$T/sigs.err")"; return 1; }
  pub="$(plist_get "$EXPORT_APP" SUPublicEDKey)"; mkdir -p "$T/prior"
  while IFS="$(printf '\t')" read -r v s u l g; do
    if [ "$u" = "$url" ]; then f="$VZIP"
    else
      # older items in the published feed still point at dwarvesf/hidden
      case "$u" in
        "https://github.com/$REPO_SLUG/releases/download/"*|"https://github.com/dwarvesf/hidden/releases/download/"*) ;;
        *) fail_row "Enclosure $s" "url allowlist" "foreign url $u"; return 1 ;; esac
      case "$s" in ""|*[!0-9A-Za-z._-]*) fail_row "Enclosure (unsafe version)" "shortVersionString charset" "a prior item's shortVersionString is not [0-9A-Za-z._-]+"; return 1 ;; esac
      f="$T/prior/$s.zip"
      curl -fsSL --proto '=https' --proto-redir '=https' --max-time 300 -o "$f" "$u" || { fail_row "Enclosure $s" "curl $u" "download failed"; return 1; }
      [ "$(stat -f %z "$f")" = "$l" ] || { fail_row "Enclosure $s" "size vs length" "downloaded $(stat -f %z "$f") bytes, item says $l"; return 1; }
      if [ "$first" = 1 ]; then
        first=0
        mkdir -p "$T/prior-app" && ditto -x -k "$f" "$T/prior-app" \
          && r="$(check_pubkey "$T/prior-app/Hidden Bar.app")" \
          || { fail_row "Prior app key" "SUPublicEDKey of $s (latest published) vs pinned" "${r:-cannot read the prior app}"; return 1; }
        row "Prior app key" "SUPublicEDKey of the $s app (latest published) vs pinned" "$r"
      fi
    fi
    if helper verify "$f" "$g" "$pub" >/dev/null; then row "Enclosure $s" "release-helper verify (signature from appcast.xml)" "VALID ($l bytes)"
    else fail_row "Enclosure $s" "release-helper verify" "INVALID"; return 1; fi
  done < "$T/sigs.tsv"
  mv "$new" "$OUT/appcast.xml" || { fail_row "Appcast" "mv appcast.xml.unverified appcast.xml" "rename failed"; return 1; }
}

stage_smoke() {
  local u="$OUT/unzip/Hidden Bar.app" pid="" i=0 r crash
  if [ "$NO_SMOKE" = 1 ]; then row "Smoke test" "open -g the unzipped app" "SKIPPED (--no-smoke)"; SKIPPED="$SKIPPED smoke"; return 0; fi
  SMOKE_DIR="$OUT/smoke"
  smoke_baseline
  grep -q unreadable "$SMOKE_DIR/loginitems-before.txt" && { fail_row "Smoke baseline" "System Events login items" "unreadable; rerun in a GUI session or with --no-smoke"; return 1; }
  row "Smoke baseline" "codesign -dvvv installed; login items named Hidden Bar; defaults export" \
    "CDHash $(cat "$SMOKE_DIR/cdhash-before.txt"); login items: $(tr '\n' ';' < "$SMOKE_DIR/loginitems-before.txt"); running: $(grep -c . "$SMOKE_DIR/running-before.txt")"
  SMOKE_STARTED=1
  for pid in $(pids_of "$INSTALLED_APP"); do quit_pid "$pid"; done
  : > "$T/smoke-t0"
  open -g -n "$u"
  while [ -z "$pid" ] && [ "$i" -lt 20 ]; do sleep 0.5; pid="$(pids_of "$u" | head -1)"; i=$((i + 1)); done
  if [ -z "$pid" ]; then r="the unzipped copy did not start"
  elif r="$(smoke_assert_process "$pid" "$u" "$BUILD")"; then
    sleep 20
    r="$(smoke_assert_process "$pid" "$u" "$BUILD")" && r="$r; alive after 20 s"
  fi
  crash="$(find "$HOME/Library/Logs/DiagnosticReports" -name 'Hidden Bar*' -newer "$T/smoke-t0" 2>/dev/null | head -1)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ -z "$crash" ] && printf '%s' "$r" | grep -q 'alive after'; then
    row "Smoke test" "open -g -n the unzipped app; pid path, build, alive at 20 s; crash reports" "$r; no crash report"
  else
    fail_row "Smoke test" "open -g -n the unzipped app" "$r${crash:+; crash report $crash}"
  fi
  if r="$(smoke_restore)"; then row "Host restored" "quit by pid; defaults import; relaunch installed; compare" "CDHash, login items and prefs equal the baseline"
  else
    sleep 5; SMOKE_RESTORED=0
    if r="$(smoke_restore)"; then row "Host restored" "restore, one retry" "equal to the baseline after one retry"
    else fail_row "Host restored" "restore, one retry" "$r"; fi
  fi
  SMOKE_RESTORED=1
  [ "$FAILED" = 0 ]
}

# ---- main ---------------------------------------------------------------------------------

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local mode="" notes="" out_arg="" r vb
  SKIP_TESTS=0; NO_SMOKE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --notes) [ $# -ge 2 ] || { usage >&2; exit 2; }; notes="$2"; mode=release; shift ;;
      --out) [ $# -ge 2 ] || { usage >&2; exit 2; }; out_arg="$2"; shift ;;
      --skip-tests) SKIP_TESTS=1 ;;
      --no-smoke) NO_SMOKE=1 ;;
      --check-app) [ $# -ge 2 ] || { usage >&2; exit 2; }; mode=check-app; CHECK_APP="$2"; shift ;;
      --guard-selftest) mode=guard-selftest ;;
      -h|--help) usage; exit 0 ;;
      *) echo "release.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
  case "$mode" in
    guard-selftest) guard_selftest; exit $? ;;
    check-app)
      make_tmp; setup_traps
      vb="$(read_versions "$PBXPROJ")" || { echo "release.sh: $vb" >&2; exit 2; }
      VER="${vb% *}"; BUILD="${vb#* }"
      if check_app "$CHECK_APP" "$VER" "$BUILD"; then echo "check-app: PASS ($CHECK_APP)"; exit 0; fi
      echo "check-app: FAIL ($CHECK_APP)"; exit 1 ;;
    release) ;;
    *) usage >&2; exit 2 ;;
  esac

  [ -n "$notes" ] || { echo "release.sh: --notes is required" >&2; exit 2; }
  case "$notes" in /*) ;; *) notes="$PWD/$notes" ;; esac
  make_tmp; setup_traps
  vb="$(read_versions "$PBXPROJ")" || { echo "release.sh: $vb" >&2; exit 2; }
  VER="${vb% *}"; BUILD="${vb#* }"
  OUT="${out_arg:-$ROOT/build/release-$VER}"
  [ -L "$OUT" ] && { echo "release.sh: --out $OUT is a symlink" >&2; exit 2; }
  if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then echo "release.sh: --out $OUT exists and is not empty; use a new dir" >&2; exit 2; fi
  mkdir -p "$(dirname "$OUT")" && { mkdir "$OUT" 2>/dev/null || [ -d "$OUT" ]; } || { echo "release.sh: cannot create $OUT" >&2; exit 2; }
  OUT="$(cd "$OUT" && pwd -P)"
  exec > >(tee -a "$OUT/release.log") 2>&1
  VZIP="$OUT/Hidden-Bar-v$VER-macos.zip"; SZIP="$OUT/Hidden-Bar-macos.zip"; EXPORT_APP="$OUT/export/Hidden Bar.app"

  stage_preflight "$notes"
  stage_tests
  stage_build
  check_app "$EXPORT_APP" "$VER" "$BUILD" || finish 1
  stage_notarize "$EXPORT_APP" || finish 1
  stage_zips "$EXPORT_APP" || finish 1
  stage_sign || finish 1
  stage_appcast || finish 1
  stage_smoke || finish 1
  finish 0
}

if [ -z "${RELEASE_SH_SOURCE_ONLY:-}" ]; then main "$@"; fi
