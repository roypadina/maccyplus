#!/bin/bash
# encode.sh <frames-dir> <demo.gif> [demo.mp4] [demo-still.webp] [poster-frame-index]
# Frames are %04d.png, 30 fps, 1280x800 (what Demo.run writes). GIF: 880 px wide, 15 fps, palettegen/paletteuse
# (error-diffusion dither keeps the gradients smooth, diff rectangles keep static areas cheap). MP4: 1280x800 h264 crf 24.
# Poster: one frame as WebP (default: 62 % into the clip).
set -euo pipefail
FR="$1"; GIF="$2"; MP4="${3:-}"; WEBP="${4:-}"; POSTER="${5:-}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
N=$(ls "$FR"/*.png | wc -l | tr -d ' ')
mkdir -p "$(dirname "$GIF")"

ffmpeg -y -v error -framerate 30 -i "$FR/%04d.png" \
  -vf "fps=15,scale=880:-1:flags=lanczos,palettegen=max_colors=256:stats_mode=full" "$TMP/pal.png"
ffmpeg -y -v error -framerate 30 -i "$FR/%04d.png" -i "$TMP/pal.png" \
  -lavfi "fps=15,scale=880:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle" -loop 0 "$GIF"

if [ -n "$MP4" ]; then
  mkdir -p "$(dirname "$MP4")"
  ffmpeg -y -v error -framerate 30 -i "$FR/%04d.png" -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p \
    -x264-params aq-mode=3 -movflags +faststart "$MP4"
fi
if [ -n "$WEBP" ]; then
  mkdir -p "$(dirname "$WEBP")"
  P="${POSTER:-$(( N * 62 / 100 ))}"
  cwebp -quiet -q 86 "$(printf "%s/%04d.png" "$FR" "$P")" -o "$WEBP"
fi
ls -l "$GIF" ${MP4:+"$MP4"} ${WEBP:+"$WEBP"} | awk '{print $5, $9}'
