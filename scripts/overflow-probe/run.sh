#!/bin/bash
# scripts/overflow-probe/run.sh : build and run the menu bar overflow probe.
#
#   scripts/overflow-probe/run.sh [PROBE FLAGS]                run on this Mac
#   scripts/overflow-probe/run.sh --host ALIAS [PROBE FLAGS]   run on another Mac via mini-run
#   scripts/overflow-probe/run.sh --build-only                 compile and sign, do not run
#
# Probe flags (see README.md): --count N, --out FILE, --settle SECONDS,
# --notch-mode [--notch-width POINTS].
#
# The probe is compiled together with the app's own SystemOverflowIndicator.swift
# (and the two files it needs to build standalone), so it classifies exactly as
# Hidden Bar does. Bundle: $OVERFLOW_PROBE_BUILD (default ~/.cache/hidden-bar/overflow-probe).

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${OVERFLOW_PROBE_BUILD:-$HOME/.cache/hidden-bar/overflow-probe}"
APP_NAME="OverflowProbe.app"
APP="$BUILD/$APP_NAME"
BIN_NAME="overflow-probe"

HOST=""
BUILD_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST="${2:?--host needs an alias}"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        *) break ;;
    esac
done

SOURCES=(
    "$HERE/main.swift"
    "$ROOT/hidden/Features/SystemOverflow/SystemOverflowIndicator.swift"
    "$ROOT/hidden/Features/StatusBar/Layout/AccessibilityMenuBarInventory.swift"
    "$ROOT/hidden/Features/StatusBar/Layout/MenuBarLayout.swift"
)

for source in "${SOURCES[@]}"; do
    [ -f "$source" ] || { echo "overflow-probe: missing $source" >&2; exit 66; }
done

mkdir -p "$APP/Contents/MacOS"
swiftc -O -D HIDDENBAR_NATIVE_VISIBILITY -o "$APP/Contents/MacOS/$BIN_NAME" "${SOURCES[@]}"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>foundation.d.hiddenbar.overflow-probe</string>
    <key>CFBundleName</key><string>OverflowProbe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || { echo "overflow-probe: ad-hoc codesign failed" >&2; exit 70; }

if [ "$BUILD_ONLY" = 1 ]; then
    echo "$APP"
    exit 0
fi

if [ -z "$HOST" ]; then
    # Run the binary itself, not through `open`: Accessibility trust then rides the
    # terminal this runs in, so nothing has to be granted to the probe app.
    exec "$APP/Contents/MacOS/$BIN_NAME" "$@"
fi

# Remote: ship the bundle and launch it through `open -W -n` so it runs in that
# Mac's GUI session. The report goes to a file under ~/.cache, printed afterwards.
LAUNCH="$BUILD/remote-launch"
cat > "$LAUNCH" <<'EOF'
#!/bin/bash
OUT="$HOME/.cache/hidden-bar/overflow-probe/out.txt"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
open -W -n "./OverflowProbe.app" --args "$@" --out "$OUT"
if [ -s "$OUT" ]; then
    cat "$OUT"
else
    echo "overflow-probe: no report at $OUT (no GUI session, or the app was blocked)" >&2
    exit 1
fi
EOF
chmod +x "$LAUNCH"

cd "$BUILD"
exec mini-run --host "$HOST" --with "$APP_NAME" ./remote-launch "$@"
