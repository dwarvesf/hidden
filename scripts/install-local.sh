#!/bin/bash
# scripts/install-local.sh : install a notarized Hidden Bar zip into /Applications, here or over ssh.
#
#   scripts/install-local.sh [options] ZIP
#
#   --host ALIAS      install on another Mac: ship ZIP and this script with
#                     `mini-run --host ALIAS --with ZIP`; the remote exit code comes back
#   --when-online     with --host: wait for the host to answer ssh first (bounded)
#   --wait-max SECS   bound for --when-online (default 28800, 8 hours)
#   --poll SECS       seconds between probes for --when-online (default 60)
#   --check-only      stage and verify the zip, print the table, change nothing
#   --backup-root DIR where per-run backup folders go
#                     (default ~/Library/Application Support/HiddenBar-backup)
#
# Order is the design: every check that can refuse runs on the staged copy BEFORE anything in
# /Applications changes. Then: back up prefs, quit the app, move the old app into a per-run
# backup folder (never deleted), ditto the new one in (rolled back on failure), verify, relaunch,
# and print a before/after table. Login items named "Hidden Bar" must all point at
# /Applications/Hidden Bar.app; strays are flagged, never removed. The script never kills a process.
#
# Exit: 0 installed and clean | 1 refused or failed (installed app unchanged) | 4 installed but a
#       post check flagged | 64 usage | 75 --when-online gave up.
#
# Test seams (env): HB_APPS_DIR (install dir, default /Applications), HB_QUIT_WAIT (seconds to
# wait for the app to quit, default 10). Bash 3.2 compatible (macOS /bin/bash).

APPS_DIR="${HB_APPS_DIR:-/Applications}"
QUIT_WAIT="${HB_QUIT_WAIT:-10}"
APP_NAME="Hidden Bar.app"
BUNDLE_ID="com.dwarvesv.minimalbar"
TEAM_ID="W777S7V8TN"
NOTARIZED="Notarized Developer ID"

host=""
when_online=0
wait_max=28800
poll=60
check_only=0
run_local=0
backup_root="$HOME/Library/Application Support/HiddenBar-backup"
zip=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

die() {
  echo "install-local: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) [ $# -ge 2 ] || usage; host="$2"; shift 2 ;;
    --when-online) when_online=1; shift ;;
    --wait-max) [ $# -ge 2 ] || usage; wait_max="$2"; shift 2 ;;
    --poll) [ $# -ge 2 ] || usage; poll="$2"; shift 2 ;;
    --check-only) check_only=1; shift ;;
    --backup-root) [ $# -ge 2 ] || usage; backup_root="$2"; shift 2 ;;
    --run-local) run_local=1; shift ;;
    -h|--help) usage ;;
    -*) echo "install-local: unknown option $1" >&2; usage ;;
    *) [ -z "$zip" ] || usage; zip="$1"; shift ;;
  esac
done

[ -n "$zip" ] || usage
[ "$when_online" -eq 0 ] || [ -n "$host" ] || { echo "install-local: --when-online needs --host" >&2; exit 64; }
case "$wait_max$poll" in *[!0-9]*) echo "install-local: --wait-max and --poll are whole seconds" >&2; exit 64 ;; esac
[ -f "$zip" ] || die "no such file: $zip"

# ---- remote: wait for the host, then ship this script and the zip through mini-run ----------

if [ -n "$host" ] && [ "$run_local" -eq 0 ]; then
  if [ "$when_online" -eq 1 ]; then
    deadline=$(( $(date +%s) + wait_max ))
    echo "waiting for $host (up to ${wait_max}s, probing every ${poll}s)"
    until ssh -o BatchMode=yes -o ConnectTimeout=6 "$host" true >/dev/null 2>&1; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "install-local: $host did not answer within ${wait_max}s, nothing installed" >&2
        exit 75
      fi
      sleep "$poll"
    done
    echo "$host is online"
  fi
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  zip_abs="$(cd "$(dirname "$zip")" && pwd)/$(basename "$zip")"
  remote_args=(--run-local)
  [ "$check_only" -eq 0 ] || remote_args+=(--check-only)
  exec mini-run --host "$host" --with "$zip_abs" "$self" "${remote_args[@]}" "./$(basename "$zip_abs")"
fi

# ---- local helpers -------------------------------------------------------------------------

cs_field() { # app key : one field of `codesign -dvvv`
  codesign -dvvv "$1" 2>&1 | sed -n "s/^$2=//p" | head -1
}

# probe APP : one line "version|cdhash|team|identifier|gatekeeper|gk_ok" ("none" fields when absent)
probe() {
  local app="$1" ver build src out rc ok=0
  if [ ! -d "$app" ]; then echo "none|none|none|none|none|0"; return; fi
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null)"
  out="$(spctl -a -vv -t exec "$app" 2>&1)"; rc=$?
  src="$(printf '%s\n' "$out" | sed -n 's/^source=//p' | head -1)"
  if [ "$rc" -eq 0 ] && [ "$src" = "$NOTARIZED" ]; then ok=1; fi
  if [ "$ok" -eq 0 ]; then
    if [ -n "$src" ]; then src="REJECTED ($src)"; else src="REJECTED"; fi
  fi
  echo "${ver:-?} (${build:-?})|$(cs_field "$app" CDHash)|$(cs_field "$app" TeamIdentifier)|$(cs_field "$app" Identifier)|$src|$ok"
}

app_pids() { pgrep -f "$APPS_DIR/$APP_NAME/Contents/MacOS/Hidden Bar" 2>/dev/null; }

running_text() {
  local pids
  pids="$(app_pids | tr '\n' ' ' | sed 's/ *$//')"
  if [ -n "$pids" ]; then echo "pid $pids"; else echo "no"; fi
}

other_copies() { # running Hidden Bar copies outside the install dir, informational
  local lines
  lines="$(pgrep -fl "Hidden Bar.app/Contents/MacOS/Hidden Bar" 2>/dev/null | grep -v "$APPS_DIR/$APP_NAME/" | sed 's/^[0-9]* //')"
  if [ -n "$lines" ]; then echo "$lines"; else echo "none"; fi
}

# login_items : lines "OK <path>" / "OUTSIDE <path>" for entries named exactly "Hidden Bar",
# "none" when there are none, "unreadable: <why>" when System Events cannot be read.
login_items() {
  local raw rc line name path found=0 out=""
  raw="$(osascript \
    -e 'tell application "System Events"' \
    -e 'set out to ""' \
    -e 'repeat with li in login items' \
    -e 'set out to out & (name of li) & "|" & (path of li) & linefeed' \
    -e 'end repeat' \
    -e 'return out' \
    -e 'end tell' 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "unreadable: $(printf '%s' "$raw" | head -1 | cut -c1-90)"
    return
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%|*}"
    path="${line#*|}"
    [ "$name" = "Hidden Bar" ] || continue
    found=1
    if [ "$path" = "$APPS_DIR/$APP_NAME" ]; then out="${out}OK $path"$'\n'; else out="${out}OUTSIDE $path"$'\n'; fi
  done <<EOF
$raw
EOF
  if [ "$found" -eq 0 ]; then echo "none"; else printf '%s\n' "${out%$'\n'}"; fi
}

# row LABEL BEFORE AFTER : values may hold several lines; they pair up line by line
row() {
  local label="$1" b=() a=() l n i
  while IFS= read -r l; do b+=("$l"); done <<EOF
$2
EOF
  while IFS= read -r l; do a+=("$l"); done <<EOF
$3
EOF
  n=${#b[@]}; [ ${#a[@]} -le "$n" ] || n=${#a[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    printf '%-22s | %-44s | %s\n' "$label" "${b[$i]:-}" "${a[$i]:-}"
    label=""
    i=$((i + 1))
  done
}

table() { # heading-before heading-after, then rows from the B_/A_ variables
  printf '%-22s | %-44s | %s\n' "check" "$1" "$2"
  printf '%-22s-+-%-44s-+-%s\n' "----------------------" "--------------------------------------------" "-------------------"
  row "version" "$B_VER" "$A_VER"
  row "CDHash" "$B_CD" "$A_CD"
  row "Gatekeeper" "$B_GK" "$A_GK"
  row "TeamIdentifier" "$B_TEAM" "$A_TEAM"
  row "running" "$B_RUN" "$A_RUN"
  row "other copies running" "$B_OTHER" "$A_OTHER"
  row "login items" "$B_LI" "$A_LI"
}

# ---- local: stage and preflight (nothing under $APPS_DIR is touched here) ---------------------

app="$APPS_DIR/$APP_NAME"
stage="$(mktemp -d "${TMPDIR:-/tmp}/hb-install.XXXXXX")" || die "cannot create a staging dir"
stage="${stage%/}"
ditto -x -k "$zip" "$stage" || die "cannot unzip $zip"

n_top=0; bad_top=0
for e in "$stage"/* "$stage"/.[!.]*; do
  [ -e "$e" ] || continue
  b="${e##*/}"
  [ "$b" != "__MACOSX" ] || continue
  n_top=$((n_top + 1))
  [ "$b" = "$APP_NAME" ] || bad_top=1
done
[ "$n_top" -eq 1 ] && [ "$bad_top" -eq 0 ] || die "zip must hold exactly '$APP_NAME' at the top level (plus __MACOSX)"
staged="$stage/$APP_NAME"

IFS='|' read -r S_VER S_CD S_TEAM S_ID S_GK S_GKOK <<EOF
$(probe "$staged")
EOF

codesign --verify --deep --strict "$staged" 2>/dev/null || die "refused: staged app fails codesign --verify --deep --strict"
[ "$S_ID" = "$BUNDLE_ID" ] || die "refused: bundle identifier is '$S_ID', expected $BUNDLE_ID"
[ "$S_TEAM" = "$TEAM_ID" ] || die "refused: TeamIdentifier is '$S_TEAM', expected $TEAM_ID"
if [ "$S_GKOK" -ne 1 ]; then
  echo "install-local: refused: Gatekeeper does not say '$NOTARIZED' for the zip's app" >&2
  spctl -a -vv -t exec "$staged" 2>&1 | sed 's/^/  spctl: /' >&2
  exit 1
fi

IFS='|' read -r B_VER B_CD B_TEAM B_ID B_GK B_GKOK <<EOF
$(probe "$app")
EOF
B_RUN="$(running_text)"
B_OTHER="$(other_copies)"
B_LI="$(login_items)"

if [ "$check_only" -eq 1 ]; then
  A_VER="$S_VER"; A_CD="$S_CD"; A_GK="$S_GK"; A_TEAM="$S_TEAM"; A_RUN="-"; A_OTHER="-"; A_LI="-"
  echo "check-only: the zip passed preflight, nothing was changed"
  table "installed now" "zip (would install)"
  echo "verdict: CHECK-ONLY OK"
  exit 0
fi

# ---- local: install ---------------------------------------------------------------------------

mkdir -p "$backup_root" || die "cannot create $backup_root"
bk="$backup_root/$(date -u +%Y%m%d-%H%M%S)"
seq=0
until mkdir "$bk" 2>/dev/null; do
  seq=$((seq + 1))
  bk="$backup_root/$(date -u +%Y%m%d-%H%M%S)-$seq"
done

if [ -n "$(app_pids)" ]; then
  osascript -e 'tell application "Hidden Bar" to quit' >/dev/null 2>&1
  waited=0
  while [ -n "$(app_pids)" ] && [ "$waited" -lt "$QUIT_WAIT" ]; do sleep 1; waited=$((waited + 1)); done
  [ -z "$(app_pids)" ] || die "Hidden Bar did not quit within ${QUIT_WAIT}s; nothing was changed (backup folder $bk is empty)"
fi

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  defaults export "$BUNDLE_ID" "$bk/prefs.plist" || die "prefs export failed; nothing was changed"
else
  echo "note: no prefs domain $BUNDLE_ID yet, nothing to back up"
fi

had_old=0
if [ -d "$app" ]; then
  /bin/mv -n "$app" "$bk/$APP_NAME" && [ ! -e "$app" ] || die "could not move the old app into $bk"
  had_old=1
fi

if ! ditto "$staged" "$app"; then
  [ ! -e "$app" ] || /bin/mv -n "$app" "$bk/Hidden Bar.failed.app"
  [ "$had_old" -eq 0 ] || /bin/mv -n "$bk/$APP_NAME" "$app"
  die "copy into $APPS_DIR failed; the old app was put back (partial copy kept at $bk/Hidden Bar.failed.app)"
fi
xattr -dr com.apple.quarantine "$app" 2>/dev/null

# ---- local: verify, relaunch, report ----------------------------------------------------------

open -g "$app"
waited=0
while [ -z "$(app_pids)" ] && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done

IFS='|' read -r A_VER A_CD A_TEAM A_ID A_GK A_GKOK <<EOF
$(probe "$app")
EOF
A_RUN="$(running_text)"
A_OTHER="$(other_copies)"
A_LI="$(login_items)"

flags=""
codesign --verify --deep --strict "$app" 2>/dev/null || flags="$flags signature-invalid"
[ "$A_GKOK" -eq 1 ] || flags="$flags gatekeeper-not-notarized"
[ "$A_CD" = "$S_CD" ] || flags="$flags CDHASH-differs-from-zip"
[ "$A_RUN" != "no" ] || flags="$flags not-running"
case "$A_LI" in *OUTSIDE*) flags="$flags login-item-OUTSIDE-$APPS_DIR" ;; esac
case "$A_LI" in unreadable*) flags="$flags login-items-unreadable" ;; esac

echo "installed $S_VER from $zip"
table "before" "after"
echo "backup: $bk (prefs.plist and the replaced app; nothing was deleted)"
if [ -z "$flags" ]; then
  echo "verdict: OK"
  exit 0
fi
echo "verdict: FLAGGED:$flags"
[ "$had_old" -eq 0 ] || echo "to go back: quit Hidden Bar, then move '$bk/$APP_NAME' over '$app' (move the current one aside first)"
exit 4
