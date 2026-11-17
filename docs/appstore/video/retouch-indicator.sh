#!/bin/bash
# Turns the raw guest recordings into the constant-frame-rate files prep-footage.sh reads, and
# retouches the macOS screen-recording indicator out of the menu bar footage.
#
# Why: `screencapture -v` makes macOS draw a purple recording pill (plus a small dot beside the
# clock) into the menu bar, and the pill changes position when Hidden Bar expands or collapses.
# The pill is patched with sky copied from the empty area to its left, one patch per layout state;
# the dot is removed with delogo. The windows below are the state changes of the recording
# `rec1b.mov` (collapsed 0.5-4.9 s, expanded 4.9-9.8 s, always-hidden 9.8-13.6 s, collapsed after);
# a different recording needs its own windows (find the pill x per frame by scanning for the
# purple pill pixels in the strip). Raw files stay in docs/appstore/out/raw (not in git).
set -eu
cd "$(dirname "$0")/../out/raw"

# constant 30 fps, since screencapture writes a variable-rate file
ffmpeg -y -loglevel error -i rec1b.mov -vf fps=30 -fps_mode cfr -c:v libx264 -crf 12 -preset fast -pix_fmt yuv420p -an rec1b_cfr.mp4
ffmpeg -y -loglevel error -i rec2.mov  -vf fps=30 -fps_mode cfr -c:v libx264 -crf 14 -preset fast -pix_fmt yuv420p -an rec2_cfr.mp4

# p1..p3: sky patches for the pill at x=2130 (collapsed), 1938 (expanded), 1740 (always-hidden)
# p4, p5: wider patches for the frames where the pill slides between layouts
ffmpeg -y -loglevel error -i rec1b_cfr.mp4 -filter_complex "
[0:v]split=6[a][b1][b2][b3][b4][b5];
[b1]crop=104:60:1980:0[p1]; [b2]crop=104:60:1788:0[p2]; [b3]crop=104:60:1590:0[p3];
[b4]crop=300:60:1300:0[p4]; [b5]crop=290:60:1250:0[p5];
[a]delogo=x=2538:y=19:w=22:h=22[d];
[d][p1]overlay=2120:0:enable='between(t,0.4,4.99)+between(t,13.45,20)'[o1];
[o1][p2]overlay=1928:0:enable='between(t,4.75,9.9)'[o2];
[o2][p3]overlay=1730:0:enable='between(t,9.65,13.7)'[o3];
[o3][p4]overlay=1925:0:enable='between(t,4.78,5.05)'[o4];
[o4][p5]overlay=1725:0:enable='between(t,9.72,9.98)'" \
  -c:v libx264 -crf 12 -preset fast -pix_fmt yuv420p -an rec1b_clean.mp4
