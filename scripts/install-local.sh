#!/bin/bash
# scripts/install-local.sh : install a notarized Hidden Bar zip (or swap in a dev build) into
# /Applications, here or over ssh, and put the old app and prefs back.
#
#   scripts/install-local.sh [options] ZIP
#   scripts/install-local.sh [options] --app PATH
#   scripts/install-local.sh [options] --restore [RUN_DIR]
#
#   --app PATH        install a built "Hidden Bar.app" directory instead of a ZIP, to test a branch
#                     build against the real app. It must carry the same Developer ID team as the
#                     installed app. Notarization is NOT required (the table says so); signature,
#                     bundle id and team are still checked. Over --host the app is shipped as a zip
#   --restore [DIR]   undo a run: quit the app, move the current app into DIR as
#                     "Hidden Bar.replaced.<stamp>.app" (never deleted), move the backed-up app
#                     back, `defaults import` the saved prefs, relaunch, and check the restored
#                     CDHash equals the one recorded at backup time. DIR is a backup run folder;
#                     the latest run under --backup-root when omitted
#   --host ALIAS      install on another Mac: ship ZIP and this script with
#                     `mini-run --host ALIAS --with ZIP`; the remote exit code comes back
#   --when-online     with --host: wait for the host to answer ssh first (bounded)
#   --wait-max SECS   bound for --when-online (default 28800, 8 hours)
#   --poll SECS       seconds between probes for --when-online (default 60)
#   --check-only      stage and verify the zip or app (or the backup, with --restore), print the
#                     table, change nothing
#   --backup-root DIR where per-run backup folders go
#                     (default ~/Library/Application Support/HiddenBar-backup)
#
# Order is the design: every check that can refuse runs on the staged copy BEFORE anything in
# /Applications changes. Then: back up prefs, quit the app, move the old app into a per-run
# backup folder (never deleted), ditto the new one in (rolled back on failure), verify, relaunch,
# and print a before/after table. Login items named "Hidden Bar" must all point at
# /Applications/Hidden Bar.app; strays are flagged, never removed. The script never kills a process.
#
# Each run folder also holds meta.txt, which records the CDHash of the app it backed up.
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
app_src=""
dev=0
restore=0
restore_dir=""

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
    --app) [ $# -ge 2 ] || usage; app_src="$2"; dev=1; shift 2 ;;
    --app-zip) [ $# -ge 2 ] || usage; zip="$2"; dev=1; shift 2 ;; # internal: --app after --host shipped it
    --restore) restore=1; shift; case "${1:-}" in ""|-*) ;; *) restore_dir="$1"; shift ;; esac ;;
    --run-local) run_local=1; shift ;;
    -h|--help) usage ;;
    -*) echo "install-local: unknown option $1" >&2; usage ;;
    *) [ -z "$zip" ] || usage; zip="$1"; shift ;;
  esac
done

if [ "$restore" -eq 1 ]; then
  [ -z "$zip" ] && [ -z "$app_src" ] || { echo "install-local: --restore takes no ZIP or --app" >&2; exit 64; }
else
  [ -n "$zip" ] || [ -n "$app_src" ] || usage
  [ -z "$zip" ] || [ -z "$app_src" ] || { echo "install-local: give a ZIP or --app, not both" >&2; exit 64; }
fi
[ "$when_online" -eq 0 ] || [ -n "$host" ] || { echo "install-local: --when-online needs --host" >&2; exit 64; }
case "$wait_max$poll" in *[!0-9]*) echo "install-local: --wait-max and --poll are whole seconds" >&2; exit 64 ;; esac
[ -z "$zip" ] || [ -f "$zip" ] || die "no such file: $zip"
[ -z "$app_src" ] || [ -d "$app_src" ] || die "no such app directory: $app_src"

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
  remote_args=(--run-local)
  [ "$check_only" -eq 0 ] || remote_args+=(--check-only)
  if [ "$restore" -eq 1 ]; then
    remote_args+=(--restore)
    [ -z "$restore_dir" ] || remote_args+=("$restore_dir") # a path on the host
    exec mini-run --host "$host" "$self" "${remote_args[@]}"
  fi
  if [ -n "$app_src" ]; then
    # ship the build as a zip: ditto keeps the signature, and the copy renames it to the name the remote expects
    ship="$(mktemp -d "${TMPDIR:-/tmp}/hb-ship.XXXXXX")" || die "cannot create a ship dir"
    ditto "$app_src" "$ship/$APP_NAME" && ditto -c -k --sequesterRsrc --keepParent "$ship/$APP_NAME" "$ship/Hidden-Bar-dev.zip" \
      || die "cannot zip $app_src for $host"
    zip="$ship/Hidden-Bar-dev.zip"
  fi
  zip_abs="$(cd "$(dirname "$zip")" && pwd)/$(basename "$zip")"
  if [ "$dev" -eq 1 ]; then remote_args+=(--app-zip "./$(basename "$zip_abs")"); else remote_args+=("./$(basename "$zip_abs")"); fi
  exec mini-run --host "$host" --with "$zip_abs" "$self" "${remote_args[@]}"
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

# running_exes : "pid path" for every process whose EXECUTABLE is a Hidden Bar binary. `ps comm`
# gives the executable path alone, so a compiler or linker run that merely names the path in its
# arguments (a test bundle build) is not mistaken for a running copy, which pgrep -f would do.
running_exes() {
  local pid rest
  ps -axo pid=,comm= 2>/dev/null | while read -r pid rest; do
    case "$rest" in
      /*"/Hidden Bar.app/Contents/MacOS/Hidden Bar") echo "$pid $rest" ;;
    esac
  done
}

app_pids() {
  local exe="$APPS_DIR/$APP_NAME/Contents/MacOS/Hidden Bar" pid rest
  running_exes | while read -r pid rest; do
    [ "$rest" != "$exe" ] || echo "$pid"
  done
}

running_text() {
  local pids
  pids="$(app_pids | tr '\n' ' ' | sed 's/ *$//')"
  if [ -n "$pids" ]; then echo "pid $pids"; else echo "no"; fi
}

other_copies() { # running Hidden Bar copies outside the install dir, informational
  local lines
  lines="$(running_exes | grep -v " $APPS_DIR/$APP_NAME/" | sed 's/^[0-9]* //')"
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

# quit_app CONTEXT : ask the installed app to quit and wait; die (nothing changed) when it stays up
quit_app() {
  local waited=0
  [ -n "$(app_pids)" ] || return 0
  osascript -e 'tell application "Hidden Bar" to quit' >/dev/null 2>&1
  while [ -n "$(app_pids)" ] && [ "$waited" -lt "$QUIT_WAIT" ]; do sleep 1; waited=$((waited + 1)); done
  [ -z "$(app_pids)" ] || die "Hidden Bar did not quit within ${QUIT_WAIT}s; nothing was changed$1"
}

# relaunch_wait : open the installed app in the background and wait (bounded) for its process
relaunch_wait() {
  local waited=0
  open -g "$app"
  while [ -z "$(app_pids)" ] && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
}

app="$APPS_DIR/$APP_NAME"

# ---- local: restore (put back the app and prefs from a backup run folder) -----------------------

if [ "$restore" -eq 1 ]; then
  rd="$restore_dir"
  if [ -z "$rd" ]; then # run folders are named by UTC stamp, so the last glob match is the latest
    for d in "$backup_root"/*/; do [ -d "$d" ] && rd="$d"; done
  fi
  rd="${rd%/}"
  [ -n "$rd" ] && [ -d "$rd" ] || die "no backup run folder (looked in $backup_root)"
  old="$rd/$APP_NAME"
  [ -d "$old" ] || die "refused: $rd holds no $APP_NAME to restore (that run had no installed app, or it was already restored)"

  IFS='|' read -r R_VER R_CD R_TEAM R_ID R_GK R_GKOK <<EOF
$(probe "$old")
EOF
  codesign --verify --deep --strict "$old" 2>/dev/null || die "refused: backed-up app fails codesign --verify --deep --strict"
  [ "$R_ID" = "$BUNDLE_ID" ] || die "refused: backed-up bundle identifier is '$R_ID', expected $BUNDLE_ID"
  [ "$R_TEAM" = "$TEAM_ID" ] || die "refused: backed-up TeamIdentifier is '$R_TEAM', expected $TEAM_ID"
  [ -n "$R_CD" ] || die "refused: cannot read the CDHash of the backed-up app"
  # the CDHash recorded at backup time is what the restored app must match; a run from before
  # meta.txt existed falls back to the backed-up app's own CDHash
  expect_cd="$R_CD"
  if [ -f "$rd/meta.txt" ]; then
    rec_cd="$(sed -n 's/^backed_up_cdhash=//p' "$rd/meta.txt" | head -1)"
    [ -z "$rec_cd" ] || expect_cd="$rec_cd"
  fi
  [ "$expect_cd" = "$R_CD" ] || die "refused: backed-up app CDHash $R_CD differs from the $expect_cd recorded at backup time; the backup was altered"

  IFS='|' read -r B_VER B_CD B_TEAM B_ID B_GK B_GKOK <<EOF
$(probe "$app")
EOF
  B_RUN="$(running_text)"
  B_OTHER="$(other_copies)"
  B_LI="$(login_items)"

  if [ "$check_only" -eq 1 ]; then
    A_VER="$R_VER"; A_CD="$R_CD"; A_GK="$R_GK"; A_TEAM="$R_TEAM"; A_RUN="-"; A_OTHER="-"; A_LI="-"
    echo "check-only: $rd passed preflight, nothing was changed"
    table "installed now" "backup (would restore)"
    echo "verdict: CHECK-ONLY OK"
    exit 0
  fi

  quit_app " ($rd is untouched)"
  ts="$(date -u +%Y%m%d-%H%M%S)"
  # the prefs being replaced are kept too, so the dev build's settings are not lost
  if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    defaults export "$BUNDLE_ID" "$rd/prefs.replaced.$ts.plist" || die "prefs export failed; nothing was changed"
  fi
  replaced="$rd/Hidden Bar.replaced.$ts.app"
  had_cur=0
  if [ -d "$app" ]; then
    /bin/mv -n "$app" "$replaced" && [ ! -e "$app" ] || die "could not move the current app into $rd"
    had_cur=1
  fi
  /bin/mv -n "$old" "$app"
  if [ ! -d "$app" ] || [ -e "$old" ]; then
    [ "$had_cur" -eq 0 ] || /bin/mv -n "$replaced" "$app"
    die "could not move the backed-up app into $APPS_DIR; the current app was put back"
  fi

  flags=""
  if [ -f "$rd/prefs.plist" ]; then
    defaults import "$BUNDLE_ID" "$rd/prefs.plist" || flags="$flags prefs-import-failed"
  else
    echo "note: $rd has no prefs.plist (the run found no prefs), prefs left as they are"
  fi

  relaunch_wait
  IFS='|' read -r A_VER A_CD A_TEAM A_ID A_GK A_GKOK <<EOF
$(probe "$app")
EOF
  A_RUN="$(running_text)"
  A_OTHER="$(other_copies)"
  A_LI="$(login_items)"

  codesign --verify --deep --strict "$app" 2>/dev/null || flags="$flags signature-invalid"
  [ "$A_CD" = "$expect_cd" ] || flags="$flags CDHASH-differs-from-backup"
  [ "$A_RUN" != "no" ] || flags="$flags not-running"
  case "$A_LI" in *OUTSIDE*) flags="$flags login-item-OUTSIDE-$APPS_DIR" ;; esac
  case "$A_LI" in unreadable*) flags="$flags login-items-unreadable" ;; esac

  echo "restored $R_VER from $rd"
  table "before (replaced)" "after (restored)"
  if [ "$A_CD" = "$expect_cd" ]; then
    echo "CDHash check: restored $A_CD equals the $expect_cd recorded at backup time"
  else
    echo "CDHash check: restored $A_CD DIFFERS from the $expect_cd recorded at backup time"
  fi
  [ "$had_cur" -eq 0 ] || echo "replaced app kept at: $replaced (nothing was deleted)"
  if [ -z "$flags" ]; then
    echo "verdict: OK"
    exit 0
  fi
  echo "verdict: FLAGGED:$flags"
  exit 4
fi

# ---- local: stage and preflight (nothing under $APPS_DIR is touched here) ---------------------

stage="$(mktemp -d "${TMPDIR:-/tmp}/hb-install.XXXXXX")" || die "cannot create a staging dir"
stage="${stage%/}"
if [ -n "$app_src" ]; then
  src_label="$app_src"
  ditto "$app_src" "$stage/$APP_NAME" || die "cannot copy $app_src"
else
  src_label="$zip"
  ditto -x -k "$zip" "$stage" || die "cannot unzip $zip"
fi

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
if [ "$dev" -eq 1 ]; then
  # a dev build is Developer ID signed but not notarized: say so instead of refusing on it
  S_GK="not required (--app build)"
elif [ "$S_GKOK" -ne 1 ]; then
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

# a dev swap only goes over an app from the same team; no installed app leaves only the TEAM_ID check
if [ "$dev" -eq 1 ] && [ "$B_TEAM" != "none" ] && [ "$B_TEAM" != "$S_TEAM" ]; then
  die "refused: the installed app is signed by team '$B_TEAM' but the --app build by '$S_TEAM'"
fi

if [ "$check_only" -eq 1 ]; then
  A_VER="$S_VER"; A_CD="$S_CD"; A_GK="$S_GK"; A_TEAM="$S_TEAM"; A_RUN="-"; A_OTHER="-"; A_LI="-"
  echo "check-only: the source passed preflight, nothing was changed"
  if [ "$dev" -eq 1 ]; then table "installed now" "--app build (would install)"; else table "installed now" "zip (would install)"; fi
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

quit_app " (backup folder $bk is empty)"

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  defaults export "$BUNDLE_ID" "$bk/prefs.plist" || die "prefs export failed; nothing was changed"
else
  echo "note: no prefs domain $BUNDLE_ID yet, nothing to back up"
fi

# meta.txt records what was backed up; --restore checks the restored CDHash against it
{
  echo "source=$src_label"
  if [ "$dev" -eq 1 ]; then echo "mode=dev-app"; else echo "mode=release-zip"; fi
  echo "installed_version=$S_VER"
  echo "installed_cdhash=$S_CD"
  if [ -d "$app" ]; then
    echo "backed_up_version=$B_VER"
    echo "backed_up_cdhash=$B_CD"
  fi
} > "$bk/meta.txt" || die "cannot write $bk/meta.txt; nothing was changed"

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

relaunch_wait

IFS='|' read -r A_VER A_CD A_TEAM A_ID A_GK A_GKOK <<EOF
$(probe "$app")
EOF
A_RUN="$(running_text)"
A_OTHER="$(other_copies)"
A_LI="$(login_items)"

flags=""
codesign --verify --deep --strict "$app" 2>/dev/null || flags="$flags signature-invalid"
if [ "$dev" -eq 1 ]; then A_GK="not required (--app build)"; elif [ "$A_GKOK" -ne 1 ]; then flags="$flags gatekeeper-not-notarized"; fi
[ "$A_CD" = "$S_CD" ] || flags="$flags CDHASH-differs-from-zip"
[ "$A_RUN" != "no" ] || flags="$flags not-running"
case "$A_LI" in *OUTSIDE*) flags="$flags login-item-OUTSIDE-$APPS_DIR" ;; esac
case "$A_LI" in unreadable*) flags="$flags login-items-unreadable" ;; esac

echo "installed $S_VER from $src_label"
table "before" "after"
echo "backup: $bk (prefs.plist, meta.txt and the replaced app; nothing was deleted)"
echo "undo: scripts/install-local.sh --restore '$bk'"
if [ -z "$flags" ]; then
  echo "verdict: OK"
  exit 0
fi
echo "verdict: FLAGGED:$flags"
exit 4
