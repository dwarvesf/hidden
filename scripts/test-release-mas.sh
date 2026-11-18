#!/bin/bash
# scripts/test-release-mas.sh : offline tests for scripts/release-mas.sh and scripts/asc-release.py.
#
#   bash scripts/test-release-mas.sh
#
# No network, no secrets, no Xcode build, no Apple, no 1Password: xcodebuild, security, pkgutil
# and op are PATH stubs, and release-mas.sh runs inside a throwaway git repo built under $TMPDIR
# (its ROOT follows its own path). Covers argument parsing, the env-var checks, the dry-run
# (builds nothing, reads no secret), the umask lesson (a root-only pkg is refused), and that no
# scratch path or secret-shaped value is hardcoded. scripts/test-asc-release.py covers the Python
# side (listing.json mapping, token, dry-run write guard) and runs at the end.
# One PASS/FAIL line per case; exit 0 only when no case failed.

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-mas-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
chmod 755 "$WORK"
PASSED=0; FAILED_N=0; FAILED_NAMES=""

result() { # name rc [reason]
  if [ "$2" = 0 ]; then echo "PASS $1"; PASSED=$((PASSED + 1))
  else echo "FAIL $1${3:+: $3}"; FAILED_N=$((FAILED_N + 1)); FAILED_NAMES="$FAILED_NAMES $1"; fi
}
t() { local name="$1"; shift; "$@" >"$WORK/case.log" 2>&1; result "$name" $? "$(tail -1 "$WORK/case.log")"; }

STUBS="$WORK/stubs"; mkdir -p "$STUBS"
stub() { cat > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
stub security <<'EOF'
#!/bin/bash
# find-identity lists both identities unless STUB_NO_IDENTITY is set
if [ "$1 $2" = "find-identity -v" ]; then
  [ -n "${STUB_NO_IDENTITY:-}" ] && { echo "     0 valid identities found"; exit 0; }
  echo '  1) AAAA "Apple Distribution: Test Co (W777S7V8TN)"'
  echo '  2) BBBB "3rd Party Mac Developer Installer: Test Co (W777S7V8TN)"'
  echo '     2 valid identities found'
  exit 0
fi
exit 1
EOF
stub xcodebuild <<'EOF'
#!/bin/bash
# records its arguments; creates an archive and an exported pkg the way Xcode would, with this process's umask
echo "$*" >> "$STUB_MARKS/xcodebuild.args"
[ -z "${STUB_XCODE_FAIL:-}" ] || { echo "stub xcodebuild failure"; exit 1; }
for a in "$@"; do case "$a" in -archivePath) next=arch ;; -exportPath) next=exp ;; *) case "${next:-}" in arch) mkdir -p "$a/Products/Applications/Hidden Bar.app/Contents"; : > "$a/Products/Applications/Hidden Bar.app/Contents/Info.plist"; [ -z "${STUB_PAYLOAD_MODE:-}" ] || chmod "$STUB_PAYLOAD_MODE" "$a/Products/Applications/Hidden Bar.app/Contents/Info.plist"; next= ;; exp) mkdir -p "$a"; : > "$a/Hidden Bar.pkg"; [ -z "${STUB_PKG_MODE:-}" ] || chmod "$STUB_PKG_MODE" "$a/Hidden Bar.pkg"; next= ;; esac ;; esac; done
echo "** ARCHIVE SUCCEEDED **"
EOF
stub pkgutil <<'EOF'
#!/bin/bash
exit "${STUB_PKGUTIL_RC:-0}"
EOF
stub op <<'EOF'
#!/bin/bash
echo "stub op called: $*" >> "$STUB_MARKS/op.calls"; exit 1
EOF
stub trash <<'EOF2'
#!/bin/bash
mkdir -p "$TMPDIR/trashed" && mv "$1" "$TMPDIR/trashed/" 2>/dev/null
EOF2
export PATH="$STUBS:$PATH"
for tool in security xcodebuild pkgutil op trash; do
  [ "$(command -v "$tool")" = "$STUBS/$tool" ] || { echo "FAIL stub-shadowing ($tool resolves to $(command -v "$tool"))"; exit 1; }
done

# A fixture repo: scripts copied in, a project file with one marketing and one build number,
# a fake HOME holding an installed profile named by UUID, a fake ASC key file.
UUID="11111111-2222-3333-4444-555555555555"
fixture() { # name : prints the fixture dir
  local d="$WORK/$1"
  mkdir -p "$d/scripts" "$d/Hidden Bar.xcodeproj" "$d/home/Library/MobileDevice/Provisioning Profiles" "$d.marks"
  cp "$ROOT/scripts/release-mas.sh" "$ROOT/scripts/asc-release.py" "$d/scripts/"
  printf 'MARKETING_VERSION = 1.13.1;\nCURRENT_PROJECT_VERSION = 22;\nMARKETING_VERSION = 1.13.1;\n' > "$d/Hidden Bar.xcodeproj/project.pbxproj"
  : > "$d/home/Library/MobileDevice/Provisioning Profiles/$UUID.provisionprofile"
  printf 'fake key\n' > "$d/AuthKey.p8"
  printf 'build/\n' > "$d/.gitignore"
  ( cd "$d" && git init -q --template= . && git add -A && git -c user.name=t -c user.email=t@example.test commit -q -m fixture )
  echo "$d"
}
mas() { # fixture-dir args... : runs the fixture's release-mas.sh with a clean, fully set environment
  local d="$1"; shift
  ( cd "$d" && env -i PATH="$PATH" HOME="$d/home" TMPDIR="$WORK" STUB_MARKS="$d.marks" \
      HB_MAS_PROFILE="${HB_MAS_PROFILE-$UUID}" ${ASC_ENV:-HB_ASC_KEY_ID=KEYID12345 HB_ASC_ISSUER_ID=issuer-uuid HB_ASC_KEY_FILE=$d/AuthKey.p8} \
      ${EXTRA_ENV:-} bash scripts/release-mas.sh "$@" )
}
rc_of() { local want="$1"; shift; "$@"; [ $? = "$want" ]; }
out_has() { local d="$1" needle="$2"; shift 2; local o; o="$(mas "$d" "$@" 2>&1)"; printf '%s' "$o" | grep -qF -- "$needle" || { echo "no '$needle' in: $(printf '%s' "$o" | tail -2)"; return 1; }; }

# ---- argument parsing ------------------------------------------------------------------------

D="$(fixture args)"
help_ok() { local o; o="$(bash "$ROOT/scripts/release-mas.sh" --help)"; [ $? = 0 ] && for v in HB_MAS_PROFILE HB_ASC_KEY_ID HB_ASC_ISSUER_ID HB_ASC_KEY_FILE HB_TEAM_ID --dry-run; do printf '%s' "$o" | grep -qF -- "$v" || { echo "help lacks $v"; return 1; }; done; }
t help-exits-0-and-documents-env help_ok
t unknown-argument-exits-2 rc_of 2 mas "$D" --frobnicate
t out-without-value-exits-2 rc_of 2 mas "$D" --out
xtrace_refused() { bash -x "$ROOT/scripts/release-mas.sh" --dry-run 2>&1 | grep -q 'refusing to run with xtrace'; }
t xtrace-refused xtrace_refused

# ---- env-var checks --------------------------------------------------------------------------

missing_profile() { local o; o="$(HB_MAS_PROFILE= mas "$D" --dry-run 2>&1)"; local rc=$?; [ $rc = 2 ] && printf '%s' "$o" | grep -q 'HB_MAS_PROFILE is not set'; }
t missing-profile-env-exits-2 missing_profile
bad_profile_chars() { local o; o="$(HB_MAS_PROFILE='x</string><key>y' mas "$D" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'characters outside'; }
t profile-with-xml-chars-refused bad_profile_chars
partial_asc() { local o; o="$(ASC_ENV='HB_ASC_KEY_ID=x' mas "$D" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'all of HB_ASC_KEY_ID'; }
t partial-asc-env-exits-2 partial_asc
missing_key_file() { local o; o="$(ASC_ENV="HB_ASC_KEY_ID=x HB_ASC_ISSUER_ID=y HB_ASC_KEY_FILE=$D/nope.p8" mas "$D" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'HB_ASC_KEY_FILE is not a file'; }
t missing-key-file-exits-2 missing_key_file
profile_not_installed() { local o; o="$(HB_MAS_PROFILE=no-such-profile mas "$D" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'no installed provisioning profile'; }
t profile-not-installed-exits-2 profile_not_installed
no_identity() { local o; o="$(EXTRA_ENV=STUB_NO_IDENTITY=1 mas "$D" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'no Apple Distribution identity'; }
t missing-signing-identity-exits-2 no_identity
dirty_tree() { local d; d="$(fixture dirty)"; : > "$d/stray.txt"; local o; o="$(mas "$d" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'dirty tree'; }
t dirty-tree-exits-2 dirty_tree
disagreeing_versions() { local d; d="$(fixture skew)"; printf 'MARKETING_VERSION = 1.13.1;\nMARKETING_VERSION = 1.13.2;\nCURRENT_PROJECT_VERSION = 22;\n' > "$d/Hidden Bar.xcodeproj/project.pbxproj"; ( cd "$d" && git add -A && git -c user.name=t -c user.email=t@example.test commit -q -m skew ); local o; o="$(mas "$d" --dry-run 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'versions disagree'; }
t disagreeing-versions-exit-2 disagreeing_versions
nonempty_out() { local d; d="$(fixture out)"; mkdir "$d.o"; : > "$d.o/x"; local o; o="$(mas "$d" --dry-run --out "$d.o" 2>&1)"; [ $? = 2 ] && printf '%s' "$o" | grep -q 'not empty'; }
t nonempty-out-exits-2 nonempty_out

# ---- dry-run ---------------------------------------------------------------------------------

dry_run() {
  local d o rc; d="$(fixture dry)"
  o="$(mas "$d" --dry-run 2>&1)"; rc=$?
  [ $rc = 0 ] && printf '%s' "$o" | grep -q 'preflight ok: Hidden Bar 1.13.1 (22)' && printf '%s' "$o" | grep -q 'built nothing, read no secret' &&
  [ ! -e "$d.marks/xcodebuild.args" ] && [ ! -e "$d.marks/op.calls" ] && [ ! -e "$d/build" ] || { echo "rc $rc: $(printf '%s' "$o" | tail -2)"; return 1; }
}
t dry-run-builds-nothing-and-reads-no-secret dry_run
dry_run_op_fallback() { # no HB_ASC_* and an op CLI on PATH: preflight passes, op is still never called
  local d o rc; d="$(fixture dryop)"
  o="$(ASC_ENV=HB_UNRELATED=1 mas "$d" --dry-run 2>&1)"; rc=$?
  [ $rc = 0 ] && [ ! -e "$d.marks/op.calls" ] || { echo "rc $rc: $(printf '%s' "$o" | tail -2)"; return 1; }
}
t dry-run-with-1password-path-never-calls-op dry_run_op_fallback

# ---- a real run through the stubs ------------------------------------------------------------

real_run() {
  local d o rc plist; d="$(fixture real)"
  o="$(mas "$d" 2>&1)"; rc=$?
  plist="$d/build/appstore-1.13.1/export.plist"
  [ $rc = 0 ] || { echo "rc $rc: $(printf '%s' "$o" | tail -3)"; return 1; }
  printf '%s' "$o" | grep -q '^pkg: .*Hidden Bar.pkg$' && printf '%s' "$o" | grep -q '^next: python3 scripts/asc-release.py release 1.13.1 22 ' || { echo "no pkg/next line"; return 1; }
  grep -q '<key>method</key><string>app-store-connect</string>' "$plist" && grep -q '<key>signingStyle</key><string>manual</string>' "$plist" &&
  grep -q '<key>signingCertificate</key><string>Apple Distribution</string>' "$plist" &&
  grep -q "<key>com.dwarvesv.minimalbar</key><string>$UUID</string>" "$plist" &&
  grep -q '<key>teamID</key><string>W777S7V8TN</string>' "$plist" || { echo "export.plist wrong"; return 1; }
  grep -q 'archive .*-scheme Hidden Bar App Store -configuration Release' "$d.marks/xcodebuild.args" &&
  grep -q -- '-exportArchive' "$d.marks/xcodebuild.args" && grep -q -- '-authenticationKeyID KEYID12345' "$d.marks/xcodebuild.args" || { echo "xcodebuild args wrong"; return 1; }
  [ -z "$(find "$d/build" -name '*.p8' -o -name 'AuthKey*')" ] || { echo "key file left in the build dir"; return 1; }
  printf '%s' "$o" | grep -qi 'authenticationKey\|issuer-uuid' && { echo "key flags leaked into output"; return 1; }
  [ "$(stat -f %Lp "$d/build/appstore-1.13.1/export/Hidden Bar.pkg" | cut -c3)" -ge 4 ] || { echo "pkg not world-readable"; return 1; }
  return 0
}
t real-run-exports-with-manual-signing-and-no-key-left real_run
root_only_pkg() { # negative control for the umask lesson: a root-only pkg stops the run with the 90255 explanation
  local d o rc; d="$(fixture rootonly)"
  o="$(EXTRA_ENV=STUB_PKG_MODE=600 mas "$d" 2>&1)"; rc=$?
  [ $rc = 1 ] && printf '%s' "$o" | grep -q '90255'
}
t root-only-pkg-refused-with-90255 root_only_pkg
root_only_payload() { # the file Apple actually rejects: an app file only root can read, caught before export
  local d o rc; d="$(fixture rootpayload)"
  o="$(EXTRA_ENV=STUB_PAYLOAD_MODE=600 mas "$d" 2>&1)"; rc=$?
  [ $rc = 1 ] && printf '%s' "$o" | grep -q '90255' && printf '%s' "$o" | grep -q 'Info.plist' && ! grep -q -- '-exportArchive' "$d.marks/xcodebuild.args"
}
t root-only-app-file-refused-before-export root_only_payload
xcode_failure() { local d o rc; d="$(fixture xfail)"; o="$(EXTRA_ENV=STUB_XCODE_FAIL=1 mas "$d" 2>&1)"; rc=$?; [ $rc = 1 ] && printf '%s' "$o" | grep -q 'stub xcodebuild failure'; }
t build-failure-exits-1 xcode_failure
bad_signature() { local d o rc; d="$(fixture badsig)"; o="$(EXTRA_ENV=STUB_PKGUTIL_RC=1 mas "$d" 2>&1)"; rc=$?; [ $rc = 1 ] && printf '%s' "$o" | grep -q 'check-signature failed'; }
t unsigned-pkg-exits-1 bad_signature

# ---- the scripts hold no scratch path, secret or umask 077 -----------------------------------

code_of() { grep -v '^[[:space:]]*#' "$1"; }
no_umask_077() { ! code_of "$ROOT/scripts/release-mas.sh" | grep -qE '^[[:space:]]*umask[[:space:]]+0?77' && ! code_of "$ROOT/scripts/asc-release.py" | grep -q 'os.umask' && code_of "$ROOT/scripts/release-mas.sh" | grep -q '^umask 022$'; }
t no-umask-077-in-the-scripts no_umask_077
no_scratch_paths() { ! grep -nE '/private/tmp|scratchpad|/Users/|/home/|ops-toolkit' "$ROOT/scripts/release-mas.sh" "$ROOT/scripts/asc-release.py"; }
t no-scratch-or-home-paths-hardcoded no_scratch_paths
no_secret_shapes() { ! grep -nE '[A-Za-z0-9+/=]{64,}|AuthKey_[A-Z0-9]{10}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|op://|eyJ[A-Za-z0-9_-]{10}' "$ROOT/scripts/release-mas.sh" "$ROOT/scripts/asc-release.py"; }
t no-secret-shaped-values-hardcoded no_secret_shapes
lessons_present() {
  grep -q 'signingStyle</key><string>manual' "$ROOT/scripts/release-mas.sh" && grep -q 'Apple Distribution' "$ROOT/scripts/release-mas.sh" &&
  grep -q 'RELEASE_TYPE = "AFTER_APPROVAL"' "$ROOT/scripts/asc-release.py" && grep -q '"usesNonExemptEncryption": False' "$ROOT/scripts/asc-release.py"
}
t lessons-encoded-manual-signing-export-compliance-release-type lessons_present

# ---- the Python side -------------------------------------------------------------------------

python_side() { python3 -I -B "$ROOT/scripts/test-asc-release.py" > "$WORK/py.log" 2>&1; local rc=$?; grep -E '^(PASS|FAIL)' "$WORK/py.log" | sed 's/^/py: /'; tail -1 "$WORK/py.log" | grep -q 'test-asc-release: [0-9]* passed, 0 failed' && return $rc; return 1; }
if python_side; then result python-side-all-cases 0; else result python-side-all-cases 1 "see $WORK/py.log"; fi

echo
echo "test-release-mas: $PASSED passed, $FAILED_N failed${FAILED_NAMES:+ (failed:$FAILED_NAMES)}"
[ "$FAILED_N" = 0 ]
