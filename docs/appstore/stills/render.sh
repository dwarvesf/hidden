#!/bin/bash
# Renders shot1..shot5.html to 2880x1800 RGB PNGs (no alpha) in img/store/ (committed).
# Needs the headless Chrome HyperFrames installs (`npx hyperframes browser ensure`) and ImageMagick.
set -eu
cd "$(dirname "$0")"
CHROME="${CHROME:-$(npx --yes hyperframes browser path | tail -1)}"
OUT=../../../img/store
TMP=../out/stills
mkdir -p "$OUT" "$TMP"
names=(tidy-menu-bar always-hidden settings arrow-styles open-source)
for i in 1 2 3 4 5; do
  name="${names[$((i - 1))]}"
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=2880,1800 --virtual-time-budget=3000 \
    --screenshot="$TMP/shot$i-rgba.png" "file://$PWD/shot$i.html" >/dev/null 2>&1
  magick "$TMP/shot$i-rgba.png" -background white -alpha remove -alpha off -strip \
    -define png:color-type=2 "$OUT/$i-$name.png"
done
command -v oxipng >/dev/null && oxipng -o 4 --strip safe -q "$OUT"/*.png
magick identify -format '%f %wx%h %[channels] %b\n' "$OUT"/*.png
