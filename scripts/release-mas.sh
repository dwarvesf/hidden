#!/bin/bash
# scripts/release-mas.sh : build, sign and export the Mac App Store pkg.
#
#   scripts/release-mas.sh [--out <dir>] [--dry-run]
#   scripts/release-mas.sh --help
#
# Archives the "Hidden Bar App Store" scheme (Release), exports an app-store-connect pkg with
# manual signing, and checks the pkg. Output under --out (default build/appstore-<version>/):
# the xcarchive, logs, export.plist and export/<app>.pkg. It never uploads or submits: that is
# scripts/asc-release.py (it prints the exact next command when the pkg is ready).
#
# --dry-run runs every preflight check (tools, clean tree, versions, env vars, signing
# identities, installed profile) and prints the plan; it builds nothing and reads no secret.
#
# Environment (full table: docs/RUNBOOK.md, "App Store release"):
#   HB_MAS_PROFILE           required. Name or UUID of the installed MAC_APP_STORE provisioning
#                            profile for the app (scripts/asc-release.py profile fetches one).
#   HB_ASC_KEY_ID, HB_ASC_ISSUER_ID, HB_ASC_KEY_FILE
#                            optional, all three or none: the App Store Connect API key. Without
#                            them the key is read from 1Password (see asc-release.py).
#   HB_TEAM_ID               default W777S7V8TN.
#   HB_MAS_INSTALLER_CERT    default "3rd Party Mac Developer Installer" (signs the pkg).
#
# Lessons this script encodes (App Store 1.13.1 run):
#   - Manual signing at export: the "Apple Distribution" identity plus the existing profile.
#     Automatic export needs cloud signing access the ASC API key does not have.
#   - Never umask 077. Apple rejects a package whose files only root can read (altool error
#     90255). The key lives in a mode 700 temp dir instead, and the archived app and the pkg
#     are checked for world-readability before anything is uploaded.
#
# Exit: 0 ok (or dry-run plan printed) | 1 build or export failed | 2 usage or preflight error.
#
# Test seam: RELEASE_MAS_SOURCE_ONLY=1 source scripts/release-mas.sh defines the functions and
# runs nothing (scripts/test-release-mas.sh). Bash 3.2 compatible (macOS /bin/bash).

case "$-" in *x*) echo "release-mas.sh: refusing to run with xtrace on (it would print secrets)" >&2; exit 2 ;; esac
case ":${SHELLOPTS:-}:" in *:xtrace:*) echo "release-mas.sh: refusing to run with SHELLOPTS=xtrace" >&2; exit 2 ;; esac

set -u -o pipefail
umask 022

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PBXPROJ="$ROOT/Hidden Bar.xcodeproj/project.pbxproj"
PROJECT="Hidden Bar.xcodeproj"
SCHEME="Hidden Bar App Store"
BUNDLE_ID="com.dwarvesv.minimalbar"
TEAM_ID="${HB_TEAM_ID:-W777S7V8TN}"
INSTALLER_CERT="${HB_MAS_INSTALLER_CERT:-3rd Party Mac Developer Installer}"
PROFILE_DIRS=("$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles")

WORK=""
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "release-mas.sh: $*" >&2; exit 2; }
# Hide anything that names the API key from build output.
filter() { grep -v -i -E 'apiKey|issuer|authenticationKey'; }

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

check_env() { # prints the problem and returns 1 when the environment cannot work
  local set_n=0 v
  [ -n "${HB_MAS_PROFILE:-}" ] || { echo "HB_MAS_PROFILE is not set (name or UUID of the MAC_APP_STORE profile)"; return 1; }
  case "$HB_MAS_PROFILE" in *[!A-Za-z0-9._\ -]*) echo "HB_MAS_PROFILE has characters outside A-Z a-z 0-9 . _ - and space"; return 1 ;; esac
  for v in HB_ASC_KEY_ID HB_ASC_ISSUER_ID HB_ASC_KEY_FILE; do
    [ -z "${!v:-}" ] || set_n=$((set_n + 1))
  done
  case "$set_n" in
    0) command -v op >/dev/null 2>&1 || { echo "no HB_ASC_KEY_ID/HB_ASC_ISSUER_ID/HB_ASC_KEY_FILE and no op CLI to read the key from 1Password"; return 1; } ;;
    3) [ -f "$HB_ASC_KEY_FILE" ] || { echo "HB_ASC_KEY_FILE is not a file"; return 1; } ;;
    *) echo "set all of HB_ASC_KEY_ID, HB_ASC_ISSUER_ID, HB_ASC_KEY_FILE, or none (then 1Password is used)"; return 1 ;;
  esac
  return 0
}

check_tools() { # prints the missing tools and returns 1
  local t missing=""
  for t in xcodebuild xcrun security pkgutil git python3 plutil stat; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  [ -z "$missing" ] || { echo "missing:$missing"; return 1; }
}

check_identities() { # "Apple Distribution" and the installer cert, both for the team
  local ids
  ids="$(security find-identity -v 2>/dev/null)"
  printf '%s\n' "$ids" | grep -q "\"Apple Distribution: .*($TEAM_ID)\"" || { echo "no Apple Distribution identity for $TEAM_ID"; return 1; }
  printf '%s\n' "$ids" | grep -qF "\"$INSTALLER_CERT: " || { echo "no '$INSTALLER_CERT' identity"; return 1; }
}

profile_installed() { # name-or-uuid : rc 0 when an installed profile has that Name or UUID
  local dir f name
  for dir in "${PROFILE_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.provisionprofile; do
      [ -f "$f" ] || continue
      [ "$(basename "$f" .provisionprofile)" = "$1" ] && return 0
      name="$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null)"
      [ "$name" = "$1" ] && return 0
    done
  done
  return 1
}

check_tree_clean() { # rc 1 and the dirty paths when dirty
  local s
  s="$(git -C "$ROOT" status --porcelain)" || { echo "git status failed"; return 1; }
  [ -z "$s" ] || { echo "$s"; return 1; }
}

write_export_plist() { # file : the manual-signing export options
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>$INSTALLER_CERT</string>
  <key>provisioningProfiles</key><dict><key>$BUNDLE_ID</key><string>$HB_MAS_PROFILE</string></dict>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF
}

mode_of() { stat -f %Lp "$1"; }
world_readable() { # path : rc 0 when others can read it (and, for a directory, enter it)
  local m
  m="$(mode_of "$1")" || return 1
  if [ -d "$1" ]; then [ $((8#$m & 5)) = 5 ]; else [ $((8#$m & 4)) = 4 ]; fi
}

check_payload() { # dir : rc 1 and the first offenders when a file or folder under it is not world-readable
  local bad
  bad="$(find "$1" \( -type d ! -perm -o=rx \) -o \( ! -type d ! -type l ! -perm -o=r \) 2>/dev/null | head -3)"
  [ -z "$bad" ] || { echo "not world-readable under $1 (first: $(echo $bad)): Apple rejects files only root can read with error 90255; a umask 077 build causes it"; return 1; }
}

check_pkg() { # export-dir : prints the pkg path; rc 1 with the reason when it is unusable
  local n pkg
  n="$(ls "$1"/*.pkg 2>/dev/null | grep -c .)"
  [ "$n" = 1 ] || { echo "expected exactly one pkg in $1, found $n"; return 1; }
  pkg="$(ls "$1"/*.pkg)"
  world_readable "$1" && world_readable "$pkg" || { echo "pkg or its folder is not world-readable (mode $(mode_of "$pkg")); a umask 077 build causes it (Apple error 90255)"; return 1; }
  pkgutil --check-signature "$pkg" >/dev/null 2>&1 || { echo "pkgutil --check-signature failed for $pkg"; return 1; }
  echo "$pkg"
}

key_wipe() {
  local f
  [ -n "$WORK" ] && [ -d "$WORK" ] || return 0
  for f in "$WORK"/* "$WORK"/.[!.]*; do [ -f "$f" ] && : > "$f"; done
  command -v trash >/dev/null 2>&1 && trash "$WORK" >/dev/null 2>&1
  return 0
}

fetch_key() { # sets AUTH; the key goes to a mode 700 dir via asc-release.py, never to the build dir
  local ids
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-mas.XXXXXX")" || die "mktemp failed"
  chmod 700 "$WORK"; trap key_wipe EXIT
  ids="$(python3 -I "$ROOT/scripts/asc-release.py" key-files "$WORK")" || die "could not read the App Store Connect key"
  KEY_ID="${ids%% *}"; ISSUER="${ids#* }"
  [ -n "$KEY_ID" ] && [ -n "$ISSUER" ] && [ -s "$WORK/AuthKey_$KEY_ID.p8" ] || die "key fetch gave no key id, issuer or key file"
  echo "ASC key: in a mode 700 temp dir, key file mode 600"
  AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$WORK/AuthKey_$KEY_ID.p8" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
}

stage_build() { # out-dir
  local out="$1" r
  mkdir -p "$out"; cd "$ROOT" || die "cannot cd to $ROOT"
  echo "HEAD $(git rev-parse HEAD)"
  xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -archivePath "$out/HiddenBar.xcarchive" -derivedDataPath "$out/dd" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic "${AUTH[@]}" > "$out/archive.log" 2>&1 \
    || { tail -30 "$out/archive.log" | filter; return 1; }
  tail -2 "$out/archive.log" | filter
  r="$(check_payload "$out/HiddenBar.xcarchive/Products")" || { echo "$r" >&2; return 1; }
  write_export_plist "$out/export.plist"
  xcodebuild -exportArchive -archivePath "$out/HiddenBar.xcarchive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/export.plist" "${AUTH[@]}" > "$out/export.log" 2>&1 \
    || { tail -30 "$out/export.log" | filter; return 1; }
  tail -2 "$out/export.log" | filter
  check_tree_clean >/dev/null || { echo "tree changed during build" >&2; git status --porcelain >&2; return 1; }
}

main() {
  local out_arg="" dry=0 r vb ver build out pkg
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) [ $# -ge 2 ] || { usage >&2; exit 2; }; out_arg="$2"; shift ;;
      --dry-run) dry=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "release-mas.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done

  r="$(check_tools)" || die "$r"
  r="$(check_env)" || die "$r"
  vb="$(read_versions "$PBXPROJ")" || die "$vb"
  ver="${vb% *}"; build="${vb#* }"
  r="$(check_tree_clean)" || die "dirty tree: $r"
  r="$(check_identities)" || die "$r"
  profile_installed "$HB_MAS_PROFILE" || die "no installed provisioning profile named or numbered '$HB_MAS_PROFILE' (scripts/asc-release.py profile fetches one)"
  out="${out_arg:-$ROOT/build/appstore-$ver}"
  [ -L "$out" ] && die "--out $out is a symlink"
  if [ -d "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then die "--out $out exists and is not empty; use a new dir"; fi

  echo "preflight ok: Hidden Bar $ver ($build), team $TEAM_ID, profile '$HB_MAS_PROFILE', out $out"
  if [ "$dry" = 1 ]; then
    echo "dry-run: would archive scheme '$SCHEME' (Release), export app-store-connect with manual signing, check the pkg"
    echo "dry-run: built nothing, read no secret"
    exit 0
  fi

  fetch_key
  stage_build "$out" || exit 1
  pkg="$(check_pkg "$out/export")" || { echo "release-mas.sh: $pkg" >&2; exit 1; }
  echo "pkg: $pkg"
  echo "next: python3 scripts/asc-release.py release $ver $build --pkg '$pkg' --copyright '<year> <holder>' --review-email <email> --dry-run"
}

if [ -z "${RELEASE_MAS_SOURCE_ONLY:-}" ]; then main "$@"; fi
