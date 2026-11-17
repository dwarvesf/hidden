#!/bin/bash
# Cuts and crops the raw guest recordings (docs/appstore/out/raw, not in git) into the clips the
# composition plays. Run retouch-indicator.sh first. Both recordings are real footage of the
# Mac App Store build; the composition only places them on the backdrop.
set -eu
cd "$(dirname "$0")/.."
RAW=out/raw
OUT=video/assets
mkdir -p "$OUT"
enc() { # enc <input> <start> <duration> <crop w:h:x:y> <scale w:h> <output>
  ffmpeg -y -loglevel error -ss "$2" -t "$3" -i "$1" \
    -vf "crop=$4,scale=$5:flags=lanczos,fps=30" -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p -an "$6"
}

# Menu bar beats from rec1b (2880x1800 screen). Each crop keeps the 1632:330 card aspect and
# ends just before the clock (x 2583 on screen) so no text is cut; icons read 2 to 4x the screen size.
enc "$RAW/rec1b_clean.mp4" 2.75 1.8  410:83:2150:0  1632:330 "$OUT/clipA1.mp4"   # collapsed, pointer arrives
enc "$RAW/rec1b_clean.mp4" 4.55 2.25 560:113:2000:0 1632:330 "$OUT/clipA2.mp4"   # click, icons shown
enc "$RAW/rec1b_clean.mp4" 9.5  2.3  760:154:1800:0 1632:330 "$OUT/clipA3.mp4"   # Option-click, always-hidden section
enc "$RAW/rec1b_clean.mp4" 13.3 1.7  410:83:2150:0  1632:330 "$OUT/clipA4.mp4"   # click, tucked away again

# Settings tabs from rec2: the window is cropped to its own bounds (1px inset) per tab, so the
# wallpaper never shows and the card carries the window's corner shape. General is the top part.
enc "$RAW/rec2_cfr.mp4" 2.9 1.5 1278:740:801:177 1440:834 "$OUT/clipB1.mp4"   # General
enc "$RAW/rec2_cfr.mp4" 5.0 2.4 1278:500:801:177 1600:626 "$OUT/clipB2.mp4"   # Appearance
enc "$RAW/rec2_cfr.mp4" 8.3 1.7 1278:418:801:177 1600:524 "$OUT/clipB3.mp4"   # Advanced
