#!/bin/bash
# scripts/test-install-local.sh : tests for scripts/install-local.sh.
#
#   bash scripts/test-install-local.sh [T1 T6 ...]   run all cases, or just the named ones
#
# The --app and --restore cases swap a fixture dev build in and put the fixture release back.
# Every case runs against a throwaway fixture tree: a fake install dir (HB_APPS_DIR), a fake
# backup root, and PATH stubs for codesign, spctl, defaults, osascript, ps, open, ssh,
# mini-run and ditto. Nothing touches the real /Applications, prefs, login items or processes.
# The fixture root is left behind in $TMPDIR for the OS to clean.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/install-local.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-install-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd)"
STUBS="$WORK/stubs"
mkdir -p "$STUBS"

pass=0; fail=0; failed_names=""

write_stub() { # name, body from stdin
  cat > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

write_stub codesign <<'EOF'
#!/bin/bash
if [ "$1" = "--verify" ]; then
  [ "${STUB_CS_VERIFY_RC:-0}" -eq 0 ] || { echo "stub: invalid signature" >&2; exit "$STUB_CS_VERIFY_RC"; }
  exit 0
fi
app="${!#}"
out="$(cat "$app/Contents/.stub-codesign")"
case "$app" in
  "$HB_APPS_DIR"/*) [ -z "${STUB_INSTALLED_CDHASH:-}" ] || out="$(printf '%s\n' "$out" | sed "s/^CDHash=.*/CDHash=$STUB_INSTALLED_CDHASH/")" ;;
esac
printf '%s\n' "$out" >&2
EOF

write_stub spctl <<'EOF'
#!/bin/bash
app="${!#}"
cat "$app/Contents/.stub-spctl"
exit "$(cat "$app/Contents/.stub-spctl-rc")"
EOF

write_stub defaults <<'EOF'
#!/bin/bash
case "$1" in
  read) [ "$2" = "com.dwarvesv.minimalbar" ] && exit "${STUB_PREFS_READ_RC:-0}" ;;
  export) { cat "$STUB_STATE/prefs-store" 2>/dev/null || echo "<plist>stub prefs</plist>"; } > "$3"; exit "${STUB_EXPORT_RC:-0}" ;;
  import) [ "$2" = "com.dwarvesv.minimalbar" ] || exit 1; cp "$3" "$STUB_STATE/prefs-store"; exit "${STUB_IMPORT_RC:-0}" ;;
esac
exec /usr/bin/defaults "$@"
EOF

write_stub osascript <<'EOF'
#!/bin/bash
all="$*"
case "$all" in
  *"System Events"*)
    if [ -n "${STUB_LI_FAIL:-}" ]; then echo "execution error: Not authorized to send Apple events to System Events. (-1743)" >&2; exit 1; fi
    cat "${STUB_LI_FILE:-/dev/null}"; exit 0 ;;
  *quit*)
    echo quit >> "$STUB_STATE/quit.log"
    [ -n "${STUB_QUIT_IGNORES:-}" ] || echo 0 > "$STUB_STATE/running"
    exit 0 ;;
esac
exit 1
EOF

write_stub ps <<'EOF'
#!/bin/bash
# like `ps -axo pid=,comm=`: one line per process, comm is the executable path only
running="$(cat "$STUB_STATE/running" 2>/dev/null)"
inst="$HB_APPS_DIR/Hidden Bar.app/Contents/MacOS/Hidden Bar"
[ "$running" = "1" ] && echo "4242 $inst"
[ -z "${STUB_OTHER_COPY:-}" ] || echo "5151 $STUB_OTHER_COPY"
echo "6060 /usr/bin/clang"
exit 0
EOF

write_stub open <<'EOF'
#!/bin/bash
echo 1 > "$STUB_STATE/running"
EOF

write_stub ssh <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_STATE/ssh.log"
exit "${STUB_SSH_RC:-0}"
EOF

write_stub mini-run <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_STATE/mini-run.args"
exit "${STUB_MINI_RC:-0}"
EOF

write_stub ditto <<'EOF'
#!/bin/bash
dest="${!#}"
case "$dest" in
  "$HB_APPS_DIR"/*) if [ -n "${STUB_DITTO_FAIL:-}" ]; then mkdir -p "$dest"; echo "stub: ditto failed" >&2; exit 1; fi ;;
esac
exec /usr/bin/ditto "$@"
EOF

# make_app DIR VERSION BUILD CDHASH TEAM SPCTL_MODE(ok|rejected) : a fixture "Hidden Bar.app"
make_app() {
  local d="$1/Hidden Bar.app"
  mkdir -p "$d/Contents/MacOS"
  cat > "$d/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>$2</string>
<key>CFBundleVersion</key><string>$3</string>
</dict></plist>
PL
  echo "binary $2" > "$d/Contents/MacOS/Hidden Bar"
  cat > "$d/Contents/.stub-codesign" <<CS
Identifier=com.dwarvesv.minimalbar
CDHash=$4
Authority=Developer ID Application: Dwarves Foundation Company Limited (W777S7V8TN)
TeamIdentifier=$5
CS
  if [ "$6" = "ok" ]; then
    printf '%s\n' "$d: accepted" "source=Notarized Developer ID" "origin=Developer ID Application: Dwarves Foundation Company Limited (W777S7V8TN)" > "$d/Contents/.stub-spctl"
    echo 0 > "$d/Contents/.stub-spctl-rc"
  else
    printf '%s\n' "$d: rejected" "origin=Developer ID Application: Dwarves Foundation Company Limited (W777S7V8TN)" > "$d/Contents/.stub-spctl"
    echo 3 > "$d/Contents/.stub-spctl-rc"
  fi
}

OLD_CD="b69bfce1d7ecc435167efdcba0429f14481e9cfa"
NEW_CD="9bb262e0127f043789c03deb881b2b982612d016"

# fresh_env [no-old] [zip-mode] [zip-team] : sets APPS BK ZIP STATE and exports the stub env
fresh_env() {
  local with_old=1 zmode=ok zteam=W777S7V8TN
  [ "$1" != "no-old" ] || with_old=0
  [ -z "$2" ] || zmode="$2"
  [ -z "$3" ] || zteam="$3"
  CASE_DIR="$(mktemp -d "$WORK/case.XXXXXX")"
  APPS="$CASE_DIR/Applications"; BK="$CASE_DIR/backup"; STATE="$CASE_DIR/state"
  mkdir -p "$APPS" "$STATE" "$CASE_DIR/zipsrc"
  echo 1 > "$STATE/running"
  echo "orig-prefs" > "$STATE/prefs-store"
  if [ "$with_old" -eq 1 ]; then
    make_app "$APPS" 1.11.3 17 "$OLD_CD" W777S7V8TN ok
    echo "old-marker" > "$APPS/Hidden Bar.app/Contents/marker.txt"
  fi
  make_app "$CASE_DIR/zipsrc" 1.12.0 19 "$NEW_CD" "$zteam" "$zmode"
  ZIP="$CASE_DIR/Hidden-Bar-v1.12.0-macos.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$CASE_DIR/zipsrc/Hidden Bar.app" "$ZIP"
  printf '%s\n' "Hidden Bar|$APPS/Hidden Bar.app" "Raycast|/Applications/Raycast.app" > "$CASE_DIR/loginitems.txt"
  export HB_APPS_DIR="$APPS" STUB_STATE="$STATE" STUB_LI_FILE="$CASE_DIR/loginitems.txt"
  export HB_QUIT_WAIT=2
  unset STUB_DITTO_FAIL STUB_LI_FAIL STUB_QUIT_IGNORES STUB_INSTALLED_CDHASH STUB_OTHER_COPY STUB_SSH_RC STUB_MINI_RC STUB_PREFS_READ_RC STUB_EXPORT_RC STUB_IMPORT_RC
}

run_install() { # extra args... ; sets RC and OUT
  OUT="$(PATH="$STUBS:$PATH" /bin/bash "$SCRIPT" --backup-root "$BK" "$@" 2>&1)"
  RC=$?
}

check() { # description, then a command
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); failed_names="$failed_names [$CURRENT: $desc]"
    echo "  FAIL: $desc"
  fi
}

out_has() { printf '%s\n' "$OUT" | grep -q -- "$1"; }
out_lacks() { ! printf '%s\n' "$OUT" | grep -q -- "$1"; }
rc_is() { [ "$RC" -eq "$1" ]; }
installed_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPS/Hidden Bar.app/Contents/Info.plist"; }
is_version() { [ "$(installed_version)" = "$1" ]; }
old_app_intact() { [ -f "$APPS/Hidden Bar.app/Contents/marker.txt" ] && is_version 1.11.3; }
backup_dirs() { find "$BK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; }
only_backup() { backup_dirs | head -1; }
apps_listing() { find "$APPS" -print | sort; }

case_T1() { # happy_path_install
  fresh_env
  run_install "$ZIP"
  check "exit 0" rc_is 0
  check "new version installed" is_version 1.12.0
  check "old app kept in backup" test -f "$(only_backup)/Hidden Bar.app/Contents/marker.txt"
  check "prefs.plist backed up" test -f "$(only_backup)/prefs.plist"
  check "app was quit then relaunched" grep -q quit "$STATE/quit.log"
  check "verdict OK" out_has "verdict: OK"
  check "table shows before CDHash" out_has "$OLD_CD"
  check "table shows after CDHash" out_has "$NEW_CD"
}

case_T2() { # unnotarized_zip_refused
  fresh_env "" rejected
  before="$(apps_listing)"
  run_install "$ZIP"
  check "exit 1" rc_is 1
  check "old app untouched" old_app_intact
  check "install dir listing unchanged" test "$(apps_listing)" = "$before"
  check "no backup folder made" test -z "$(backup_dirs)"
  check "says Gatekeeper refused" out_has "Gatekeeper does not say"
  check "shows raw spctl text" out_has "spctl: .*rejected"
}

case_T3() { # wrong_team_refused
  fresh_env "" ok ABCDE12345
  run_install "$ZIP"
  check "exit 1" rc_is 1
  check "old app untouched" old_app_intact
  check "no backup folder made" test -z "$(backup_dirs)"
  check "names the team" out_has "TeamIdentifier is 'ABCDE12345'"
}

case_T4() { # copy_failure_rolls_back
  fresh_env
  export STUB_DITTO_FAIL=1
  run_install "$ZIP"
  check "exit 1" rc_is 1
  check "old app put back" old_app_intact
  check "partial copy kept aside" test -d "$(only_backup)/Hidden Bar.failed.app"
  check "says it rolled back" out_has "old app was put back"
}

case_T5() { # no_installed_app
  fresh_env no-old
  run_install "$ZIP"
  check "exit 0" rc_is 0
  check "new version installed" is_version 1.12.0
  check "prefs still backed up" test -f "$(only_backup)/prefs.plist"
  check "no old app in backup" test ! -e "$(only_backup)/Hidden Bar.app"
  check "before column says none" out_has "version  *| none"
}

case_T6() { # login_item_outside_applications_flagged
  fresh_env
  printf '%s\n' "Hidden Bar|/private/var/folders/x/T/hb-tul/Hidden Bar.app" "Hacker Bar|/private/var/folders/x/T/Hacker Bar.app" > "$CASE_DIR/loginitems.txt"
  run_install "$ZIP"
  check "exit 4" rc_is 4
  check "OUTSIDE shown" out_has "OUTSIDE /private/var/folders/x/T/hb-tul/Hidden Bar.app"
  check "other app not matched" out_lacks "Hacker Bar"
  check "install kept, not rolled back" is_version 1.12.0
  check "verdict FLAGGED" out_has "verdict: FLAGGED"
}

case_T7() { # login_items_unreadable_exit_4
  fresh_env
  export STUB_LI_FAIL=1
  run_install "$ZIP"
  check "exit 4" rc_is 4
  check "says unreadable" out_has "unreadable"
  check "install kept" is_version 1.12.0
}

case_T8() { # check_only_changes_nothing
  fresh_env
  before="$(apps_listing)"
  run_install --check-only "$ZIP"
  check "exit 0" rc_is 0
  check "install dir listing unchanged" test "$(apps_listing)" = "$before"
  check "old app untouched" old_app_intact
  check "no backup folder made" test ! -e "$BK"
  check "app not quit" test ! -e "$STATE/quit.log"
  check "reports Notarized" out_has "Notarized Developer ID"
  check "reports zip version" out_has "1.12.0"
  fresh_env "" rejected
  run_install --check-only "$ZIP"
  check "check-only still refuses an unnotarized zip" rc_is 1
}

case_T9() { # cdhash_mismatch_flagged
  fresh_env
  export STUB_INSTALLED_CDHASH="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  run_install "$ZIP"
  check "exit 4" rc_is 4
  check "names the mismatch" out_has "CDHASH-differs-from-zip"
}

case_T10() { # host_dispatch_passes_remote_exit_code
  fresh_env
  export STUB_MINI_RC=7
  run_install --host air "$ZIP"
  check "remote exit code returned" rc_is 7
  check "mini-run got --host air" grep -qx -- "air" "$STATE/mini-run.args"
  check "mini-run got --with <zip>" grep -qx -- "$ZIP" "$STATE/mini-run.args"
  check "mini-run got the script" grep -q "scripts/install-local.sh" "$STATE/mini-run.args"
  check "remote runs locally on ./zip" grep -qx -- "./Hidden-Bar-v1.12.0-macos.zip" "$STATE/mini-run.args"
  check "--run-local passed" grep -qx -- "--run-local" "$STATE/mini-run.args"
  check "no ssh probe without --when-online" test ! -e "$STATE/ssh.log"
  check "nothing touched here" old_app_intact
}

case_T11() { # when_online_bounded
  fresh_env
  export STUB_SSH_RC=255
  start=$(date +%s)
  run_install --host air --when-online --wait-max 2 --poll 1 "$ZIP"
  elapsed=$(( $(date +%s) - start ))
  check "exit 75" rc_is 75
  check "gave up inside the bound" test "$elapsed" -le 8
  check "probed ssh at least once" test -s "$STATE/ssh.log"
  check "mini-run never called" test ! -e "$STATE/mini-run.args"
  fresh_env
  run_install --when-online "$ZIP"
  check "--when-online without --host is a usage error" rc_is 64
}

case_T12() { # quit_timeout_refused
  fresh_env
  export STUB_QUIT_IGNORES=1
  run_install "$ZIP"
  check "exit 1" rc_is 1
  check "old app untouched" old_app_intact
  check "says it did not quit" out_has "did not quit"
}

case_T13() { # stray_copy_listed_and_not_counted_as_installed
  fresh_env
  echo 0 > "$STATE/running"
  export STUB_OTHER_COPY="/private/var/x/dd/Hidden Bar.app/Contents/MacOS/Hidden Bar"
  run_install --check-only "$ZIP"
  check "exit 0" rc_is 0
  check "stray copy listed" out_has "/private/var/x/dd/Hidden Bar.app/Contents/MacOS/Hidden Bar"
  check "installed app not running even though a stray copy is" out_has "running  *| no"
  check "unrelated processes not listed" out_lacks "clang"
}

# dev_app [team] : a fixture dev build (signed, NOT notarized) in $CASE_DIR/dev, path in DEV_APP
dev_app() {
  mkdir -p "$CASE_DIR/dev"
  make_app "$CASE_DIR/dev" 1.12.1 20 "$NEW_CD" "${1:-W777S7V8TN}" rejected
  DEV_APP="$CASE_DIR/dev/Hidden Bar.app"
}
cd_of() { sed -n 's/^CDHash=//p' "$1/Contents/.stub-codesign"; }
replaced_app() { find "$(only_backup)" -maxdepth 1 -name 'Hidden Bar.replaced.*.app' | head -1; }

case_T14() { # app_dev_build_happy_path
  fresh_env
  dev_app
  run_install --app "$DEV_APP"
  check "exit 0" rc_is 0
  check "dev version installed" is_version 1.12.1
  check "old app kept in backup" test -f "$(only_backup)/Hidden Bar.app/Contents/marker.txt"
  check "meta records the backed-up CDHash" grep -qx "backed_up_cdhash=$OLD_CD" "$(only_backup)/meta.txt"
  check "meta says dev-app" grep -qx "mode=dev-app" "$(only_backup)/meta.txt"
  check "table says Gatekeeper not required" out_has "not required (--app build)"
  check "no notarization flag" out_lacks "gatekeeper-not-notarized"
  check "verdict OK" out_has "verdict: OK"
  check "tells how to undo" out_has "undo: scripts/install-local.sh --restore"
  fresh_env
  dev_app
  run_install --app "$DEV_APP" "$ZIP"
  check "an app and a ZIP together is a usage error" rc_is 64
  fresh_env
  dev_app
  run_install --app "$ZIP"
  check "--app needs a directory" rc_is 1
}

case_T15() { # app_team_mismatch_refused
  fresh_env
  dev_app ABCDE12345
  run_install --app "$DEV_APP"
  check "foreign team: exit 1" rc_is 1
  check "foreign team: old app untouched" old_app_intact
  check "foreign team: no backup folder" test -z "$(backup_dirs)"
  check "foreign team: names the team" out_has "TeamIdentifier is 'ABCDE12345'"
  fresh_env
  make_app "$APPS" 1.11.3 17 "$OLD_CD" ABCDE12345 ok
  echo "old-marker" > "$APPS/Hidden Bar.app/Contents/marker.txt"
  dev_app
  run_install --app "$DEV_APP"
  check "installed app of another team: exit 1" rc_is 1
  check "installed app of another team: old app untouched" old_app_intact
  check "installed app of another team: no backup folder" test -z "$(backup_dirs)"
  check "installed app of another team: says so" out_has "installed app is signed by team 'ABCDE12345'"
}

case_T16() { # restore_round_trip_identical_cdhash
  fresh_env
  dev_app
  run_install --app "$DEV_APP"
  check "setup: dev build installed" is_version 1.12.1
  echo "dev-prefs" > "$STATE/prefs-store"
  rm -f "$STATE/quit.log"
  run_install --restore
  check "exit 0" rc_is 0
  check "release version back" is_version 1.11.3
  check "release contents back" old_app_intact
  check "CDHash identical to the original" test "$(cd_of "$APPS/Hidden Bar.app")" = "$OLD_CD"
  check "table shows the dev CDHash before" out_has "$NEW_CD"
  check "table shows the restored CDHash" out_has "$OLD_CD"
  check "CDHash line says equal" out_has "equals the $OLD_CD recorded at backup time"
  check "dev app kept, not deleted" test "$(cd_of "$(replaced_app)")" = "$NEW_CD"
  check "prefs imported back" test "$(cat "$STATE/prefs-store")" = "orig-prefs"
  check "dev prefs kept aside" grep -q dev-prefs "$(only_backup)"/prefs.replaced.*.plist
  check "app quit before the swap" grep -q quit "$STATE/quit.log"
  check "relaunched" test "$(cat "$STATE/running")" = "1"
  check "verdict OK" out_has "verdict: OK"
  run_install --restore "$(only_backup)"
  check "a second restore of the same run refuses" rc_is 1
  check "second restore leaves the release alone" old_app_intact
}

case_T17() { # restore_cdhash_mismatch_flagged
  fresh_env
  dev_app
  run_install --app "$DEV_APP"
  export STUB_INSTALLED_CDHASH="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  run_install --restore
  check "exit 4" rc_is 4
  check "names the mismatch" out_has "CDHASH-differs-from-backup"
  check "CDHash line says differs" out_has "DIFFERS from the $OLD_CD"
  unset STUB_INSTALLED_CDHASH
  fresh_env
  dev_app
  run_install --app "$DEV_APP"
  sed -i '' "s/^backed_up_cdhash=.*/backed_up_cdhash=1111111111111111111111111111111111111111/" "$(only_backup)/meta.txt"
  run_install --restore
  check "a backup that disagrees with meta.txt: exit 1" rc_is 1
  check "it says the backup was altered" out_has "recorded at backup time"
  check "dev build still installed, nothing moved" is_version 1.12.1
}

case_T18() { # restore_check_only_and_no_backup
  fresh_env
  dev_app
  run_install --app "$DEV_APP"
  before="$(apps_listing)"
  run_install --restore --check-only
  check "exit 0" rc_is 0
  check "install dir listing unchanged" test "$(apps_listing)" = "$before"
  check "dev build still installed" is_version 1.12.1
  check "verdict CHECK-ONLY" out_has "CHECK-ONLY OK"
  fresh_env
  run_install --restore
  check "no backup folder at all: exit 1" rc_is 1
  check "says no run folder" out_has "no backup run folder"
  run_install --restore "$ZIP"
  check "restore with a file instead of a folder: exit 1" rc_is 1
}

case_T19() { # host_dispatch_for_app_and_restore
  fresh_env
  dev_app
  run_install --host air --app "$DEV_APP"
  zip_arg="$(grep -x '.*Hidden-Bar-dev.zip' "$STATE/mini-run.args" | head -1)"
  check "mini-run got --host air" grep -qx -- "air" "$STATE/mini-run.args"
  check "the shipped zip exists" test -f "$zip_arg"
  check "remote gets it as an app zip" grep -qx -- "--app-zip" "$STATE/mini-run.args"
  check "remote path is ./name" grep -qx -- "./Hidden-Bar-dev.zip" "$STATE/mini-run.args"
  check "nothing touched here" old_app_intact
  fresh_env
  run_install --host air --restore /var/backup/20260101-000000
  check "restore: --run-local passed" grep -qx -- "--run-local" "$STATE/mini-run.args"
  check "restore: --restore passed" grep -qx -- "--restore" "$STATE/mini-run.args"
  check "restore: run dir passed" grep -qx -- "/var/backup/20260101-000000" "$STATE/mini-run.args"
  check "restore: nothing shipped" test -z "$(grep -x -- '--with' "$STATE/mini-run.args")"
  fresh_env "" rejected
  run_install --run-local --app-zip "$ZIP"
  check "the shipped form installs an unnotarized build" rc_is 0
  check "and is installed" is_version 1.12.0
  fresh_env "" rejected
  run_install --run-local "$ZIP"
  check "the same zip without --app-zip is refused" rc_is 1
}

cases="T1 T2 T3 T4 T5 T6 T7 T8 T9 T10 T11 T12 T13 T14 T15 T16 T17 T18 T19"
[ $# -eq 0 ] || cases="$*"
for c in $cases; do
  CURRENT="$c"
  echo "== $c"
  "case_$c"
done

echo
echo "passed checks: $pass  failed checks: $fail"
if [ "$fail" -ne 0 ]; then
  echo "FAILED:$failed_names"
  exit 1
fi
echo "ALL GREEN"
