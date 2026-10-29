#!/bin/bash
# Downscales Design/AppIcon.png into every macOS AppIcon size and the README preview.
# Needs only macOS: sips resamples the approved 1024 px master. Run from anywhere.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
master="$here/AppIcon.png"
iconset="$here/../Sources/NotchVoice/Assets.xcassets/AppIcon.appiconset"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -f "$master" ] || { echo "Missing icon master: $master" >&2; exit 1; }
dimensions="$(sips -g pixelWidth -g pixelHeight "$master" | awk '/^  pixel(Width|Height):/ {print $2}')"
[[ "$dimensions" == $'1024\n1024' ]] || {
  echo "Icon master must be 1024 x 1024: $master" >&2
  exit 1
}

mkdir -p "$iconset"
for size in 16 32 64 128 256 512; do
  sips -s format png -z "$size" "$size" "$master" --out "$work/icon_$size.png" >/dev/null
done
cp "$work/icon_16.png"   "$iconset/icon_16x16.png"
cp "$work/icon_32.png"   "$iconset/icon_16x16@2x.png"
cp "$work/icon_32.png"   "$iconset/icon_32x32.png"
cp "$work/icon_64.png"   "$iconset/icon_32x32@2x.png"
cp "$work/icon_128.png"  "$iconset/icon_128x128.png"
cp "$work/icon_256.png"  "$iconset/icon_128x128@2x.png"
cp "$work/icon_256.png"  "$iconset/icon_256x256.png"
cp "$work/icon_512.png"  "$iconset/icon_256x256@2x.png"
cp "$work/icon_512.png"  "$iconset/icon_512x512.png"
cp "$master"            "$iconset/icon_512x512@2x.png"
cp "$work/icon_512.png"  "$here/AppIcon-preview.png"
echo "Wrote $iconset and $here/AppIcon-preview.png"
