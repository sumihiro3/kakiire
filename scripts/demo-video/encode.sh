#!/bin/bash
# 撮った動画から、SNS 用(1080p)・LP 用(720p)・README 用(GIF)を作る。
# 使い方: encode.sh <撮った.mp4> <ja|en> <出力フォルダ>
set -eu
IN="$1"; L="$2"; OUT="$3"
mkdir -p "$OUT"
# 頭は録画を始めてから操作が始まるまでの待ち、尻は止めるときの余り
END=$(echo "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN") - 0.4" | bc)

ffmpeg -hide_banner -loglevel error -ss 1.6 -to "$END" -i "$IN" -vf "scale=1920:1080:flags=lanczos" -r 60 \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart -an -y "$OUT/kakiire-demo-$L-1080p.mp4"
ffmpeg -hide_banner -loglevel error -i "$OUT/kakiire-demo-$L-1080p.mp4" -vf "scale=1280:720:flags=lanczos" -r 30 \
  -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an -y "$OUT/demo-$L.mp4"
ffmpeg -hide_banner -loglevel error -ss 21 -i "$OUT/demo-$L.mp4" -frames:v 1 -q:v 4 -y "$OUT/demo-poster-$L.jpg"
ffmpeg -hide_banner -loglevel error -i "$OUT/kakiire-demo-$L-1080p.mp4" \
  -vf "fps=12,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
  -y "$OUT/demo-$L.gif"
ls -la "$OUT"
