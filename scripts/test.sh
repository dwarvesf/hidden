#!/bin/bash
# scripts/test.sh : run both Hidden Bar test schemes fast.
#
#   scripts/test.sh                      full suite, both schemes in parallel
#   scripts/test.sh --changed [BASE]     only the test classes mapped from files changed vs BASE
#                                        (default origin/develop); full suite when the mapping is unsure
#   scripts/test.sh --no-parallel-testing   turn off -parallel-testing-enabled
#   scripts/test.sh --serial             run the two schemes one after the other
#   scripts/test.sh --dd DIR             derived-data root (default $HIDDEN_TEST_DD or ~/.cache/hidden-bar/dd)
#
# How it is fast:
#   - build-for-testing once per scheme, then test-without-building, into a
#     persistent derived-data dir that survives between runs (warm builds are
#     incremental).
#   - the two schemes run at the same time. Each gets its own derived-data
#     subdir (direct/, appstore/): two xcodebuilds on one dir lock each other.
#   - -parallel-testing-enabled YES.
#   - separate result bundles per scheme: <dd>/results/<timestamp>/<scheme>.xcresult.
#
# Exit code: 0 only when every selected scheme built, ran at least one test and
# had no failure. Prints a timing table at the end.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DD_ROOT="${HIDDEN_TEST_DD:-$HOME/.cache/hidden-bar/dd}"
CHANGED=0
BASE_REF="origin/develop"
PARALLEL_TESTING=YES
SERIAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) CHANGED=1; case "${2:-}" in ""|--*) ;; *) BASE_REF="$2"; shift ;; esac ;;
    --no-parallel-testing) PARALLEL_TESTING=NO ;;
    --serial) SERIAL=1 ;;
    --dd) shift; DD_ROOT="${1:?--dd needs a directory}" ;;
    -h|--help) sed -n 2,22p "$0"; exit 0 ;;
    *) echo "usage: scripts/test.sh [--changed [BASE]] [--no-parallel-testing] [--serial] [--dd DIR]" >&2; exit 2 ;;
  esac
  shift
done

now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }
elapsed() { perl -e 'printf "%.1f\n", $ARGV[1] - $ARGV[0]' "$1" "$2"; }

# ---- --changed: changed files -> -only-testing selectors -------------------

TEST_DIRS="HiddenBarTests HiddenTests"

classes_in() { # classes_in TESTFILE : XCTestCase subclasses declared in it
  grep -hE '^[[:space:]]*(final )?class [A-Za-z0-9_]+[[:space:]]*:[[:space:]]*XCTestCase' "$1" \
    | sed -E 's/^[[:space:]]*(final )?class ([A-Za-z0-9_]+).*/\2/'
}

select_file() { # select_file TESTFILE : print "Target/Class" selectors for it
  local target=${1%%/*} c
  for c in $(classes_in "$1"); do echo "$target/$c"; done
}

# Source stem -> test files. Convention first (Foo.swift -> FooTests.swift in either
# test dir); the engine and notch files are named differently from their tests.
tests_for_source() { # tests_for_source STEM : print test file paths, nothing when unknown
  local stem=$1 d f found=0
  case "$stem" in
    MenuBarEngine|MenuBarEngineFactory|NativeVisibilityEngine|NativeVisibilityBridge|LegacyLengthEngine|AccessibilityMenuBarInventory|MenuBarLayout)
      echo HiddenBarTests/MenuBarEngineTests.swift
      echo HiddenTests/MenuBarLayoutResolverTests.swift
      echo HiddenTests/MenuBarExtraClassifierTests.swift
      return ;;
    NotchOverflowController)
      echo HiddenTests/NotchOverflowPreferencesTests.swift
      echo HiddenTests/NotchOverflowMenuBuilderTests.swift
      echo HiddenTests/NotchGeometryTests.swift
      return ;;
  esac
  for d in $TEST_DIRS; do
    f="$d/${stem}Tests.swift"
    [ -f "$f" ] && { echo "$f"; found=1; }
  done
  return 0
}

ONLY_ARGS=()
CHANGED_NOTE="full suite"
if [ "$CHANGED" = 1 ]; then
  unsure=""
  if ! git rev-parse --verify -q "$BASE_REF^{commit}" >/dev/null; then
    unsure="base ref $BASE_REF not found"
  else
    files=$( { git diff --name-only "$BASE_REF"...HEAD; git diff --name-only HEAD; git ls-files -o --exclude-standard; } | sort -u)
    selectors=""
    for f in $files; do
      case "$f" in
        HiddenBarTests/*.swift|HiddenTests/*.swift)
          [ -f "$f" ] && selectors="$selectors"$'\n'"$(select_file "$f")" ;;
        hidden/*.swift)
          stem=$(basename "$f" .swift)
          t=$(tests_for_source "$stem")
          if [ -z "$t" ]; then unsure="no test mapped for $f"; break; fi
          for tf in $t; do selectors="$selectors"$'\n'"$(select_file "$tf")"; done ;;
        *.md|docs/*|img/*|LICENSE|PRIVACY_POLICY.md|.gitignore) ;; # no code, no test impact
        *) unsure="$f can change any test (project, plist, script or unmapped source)"; break ;;
      esac
    done
    if [ -z "$unsure" ]; then
      selectors=$(echo "$selectors" | sed '/^$/d' | sort -u)
      if [ -z "$selectors" ]; then
        echo "--changed: only non-code files changed vs $BASE_REF; no tests to run"
        exit 0
      fi
      for s in $selectors; do ONLY_ARGS+=("-only-testing:$s"); done
      CHANGED_NOTE="--changed vs $BASE_REF: $(echo "$selectors" | tr '\n' ' ')"
    fi
  fi
  [ -n "$unsure" ] && { echo "--changed: $unsure; falling back to the full suite"; CHANGED_NOTE="full suite (fallback: $unsure)"; }
fi

# ---- one scheme: build-for-testing, then test-without-building -------------

TS=$(date +%Y%m%d-%H%M%S)
RUN="$DD_ROOT/results/$TS"
mkdir -p "$RUN" || exit 2

run_scheme() { # run_scheme KEY SCHEME CONFIG
  local key=$1 scheme=$2 config=$3 dd="$DD_ROOT/$1" t0 t1 t2 rc_b=0 rc_t=0 passed=0 failed=0
  mkdir -p "$dd"
  t0=$(now)
  xcodebuild build-for-testing -project "Hidden Bar.xcodeproj" -scheme "$scheme" -configuration "$config" \
    -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO > "$RUN/$key-build.log" 2>&1 || rc_b=$?
  t1=$(now)
  if [ "$rc_b" = 0 ]; then
    xcodebuild test-without-building -project "Hidden Bar.xcodeproj" -scheme "$scheme" -configuration "$config" \
      -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO \
      -parallel-testing-enabled "$PARALLEL_TESTING" \
      -resultBundlePath "$RUN/$key.xcresult" ${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"} > "$RUN/$key-test.log" 2>&1 || rc_t=$?
  fi
  t2=$(now)
  if [ -d "$RUN/$key.xcresult" ]; then
    read -r passed failed < <(xcrun xcresulttool get test-results summary --path "$RUN/$key.xcresult" --compact 2>/dev/null \
      | python3 -I -c 'import json,sys
d=json.load(sys.stdin); print(d.get("passedTests",0), d.get("failedTests",0))' 2>/dev/null || echo "0 0")
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$scheme" "$(elapsed "$t0" "$t1")" "$(elapsed "$t1" "$t2")" "${passed:-0}" "${failed:-0}" "$rc_b" "$rc_t" > "$RUN/$key.row"
}

W0=$(now)
if [ "$SERIAL" = 1 ]; then
  run_scheme direct "Hidden Bar" Debug-Direct
  run_scheme appstore "Hidden Bar App Store" Debug
else
  run_scheme direct "Hidden Bar" Debug-Direct &
  run_scheme appstore "Hidden Bar App Store" Debug &
  wait
fi
W1=$(now)

# ---- timing table -----------------------------------------------------------

status=0
echo
echo "selection: $CHANGED_NOTE   (parallel testing: $PARALLEL_TESTING, schemes: $([ "$SERIAL" = 1 ] && echo serial || echo parallel))"
printf '%-24s %8s %8s %8s %7s %7s  %s\n' scheme build_s test_s total_s passed failed result
for key in direct appstore; do
  IFS=$'\t' read -r scheme tb tt passed failed rcb rct < "$RUN/$key.row" || { echo "no result row for $key"; status=1; continue; }
  result=ok
  if [ "$rcb" != 0 ]; then result="BUILD FAILED ($key-build.log)"; status=1
  elif [ "$rct" != 0 ] || [ "$failed" != 0 ]; then result="TESTS FAILED ($key-test.log)"; status=1
  elif [ "$passed" = 0 ]; then result="NO TESTS RAN"; status=1; fi
  printf '%-24s %8s %8s %8s %7s %7s  %s\n' "$scheme" "$tb" "$tt" "$(perl -e 'printf "%.1f", $ARGV[0] + $ARGV[1]' "$tb" "$tt")" "$passed" "$failed" "$result"
done
printf '%-24s %26s\n' "wall clock" "$(elapsed "$W0" "$W1")"
echo "results: $RUN"
exit $status
