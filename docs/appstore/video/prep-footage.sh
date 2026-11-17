#!/bin/bash
# Cuts and crops the raw guest recordings (docs/appstore/out/raw, not in git) into the two
# clips the composition plays. The macOS recording indicator is retouched out of rec1b first
# (retouch-indicator.sh, run that first). Both clips are real footage of the Mac App Store build.
set -eu
cd "$(dirname "$0")/.."
RAW=out/raw
OUT=video/assets
mkdir -p "$OUT"
# A: menu bar, collapsed -> expanded -> always-hidden -> collapsed. Top-right 1160x246 of the 2880x1800 screen.
ffmpeg -y -loglevel error -ss 2.2 -t 14.0 -i "$RAW/rec1b_clean.mp4" \
  -vf "crop=1160:246:1720:0,scale=1600:340:flags=lanczos,fps=30" -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p -an "$OUT/clipA.mp4"
# B: settings window, General -> Appearance -> Advanced. Window-centred 2275x1280 crop, below the menu bar.
ffmpeg -y -loglevel error -ss 3.5 -t 6.1 -i "$RAW/rec2_cfr.mp4" \
  -vf "crop=2275:1280:302:100,scale=1494:840:flags=lanczos,fps=30" -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p -an "$OUT/clipB.mp4"
