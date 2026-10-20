#!/usr/bin/env bash
# Run the before/after Flutter capture passes before publishing this review.
set -euo pipefail
cd "$(dirname "$0")/../.."
review=build/review-results/vampire-refine-v2
for version in before after; do
  test -f "$review/$version/frames/0399.png"
  ffmpeg -hide_banner -loglevel error -nostdin -y \
    -framerate 20 -i "$review/$version/frames/%04d.png" -frames:v 400 \
    -c:v libx264 -threads 2 -preset fast -crf 18 -pix_fmt yuv420p \
    -movflags +faststart "$review/$version.mp4"
done
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -i "$review/before.mp4" -i "$review/after.mp4" \
  -filter_complex '[0:v][1:v]hstack=inputs=2[v]' -map '[v]' -an \
  -c:v libx264 -threads 2 -preset fast -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$review/comparison.mp4"
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -i "$review/before/idle-right.png" -i "$review/after/idle-right.png" \
  -filter_complex '[0:v][1:v]hstack=inputs=2[v]' -map '[v]' \
  -frames:v 1 "$review/idle-comparison.png"
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -i "$review/before/reach-left.png" -i "$review/after/reach-left.png" \
  -filter_complex '[0:v][1:v]hstack=inputs=2[v]' -map '[v]' \
  -frames:v 1 "$review/reach-comparison.png"
cp tool/capture/vampire_comparison.html "$review/index.html"
cp build/chapters-preview/characters/vampire_scene.png "$review/gameplay.png"
ffprobe -v error -show_entries stream=width,height,nb_frames,r_frame_rate \
  -show_entries format=duration -of json "$review/comparison.mp4"
