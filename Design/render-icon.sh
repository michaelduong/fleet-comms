#!/bin/bash
# Downscales Design/AppIcon.png into every macOS AppIcon size and the README preview,
# and cuts the opaque iPhone icon and its Live Activity renditions from the same master.
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

# iPhone: crop the Mac rounded rim, flatten onto the icon's dark backdrop, scale to 1024 px.
phone="$here/../Sources/PhoneAssets/Assets.xcassets"
sips -s format png --cropToHeightWidth 824 824 --cropOffset 98 100 "$master" --out "$work/crop.png" >/dev/null
swift - "$work/crop.png" "$phone/AppIcon.appiconset/AppIcon.png" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: 0x14 / 255.0, green: 0x18 / 255.0, blue: 0x1E / 255.0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
ctx.interpolationQuality = .high
ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
SWIFT
for entry in 72:1 144:2 216:3; do
  px="${entry%%:*}"; scale="${entry##*:}"
  sips -s format png -z "$px" "$px" "$phone/AppIcon.appiconset/AppIcon.png" \
    --out "$phone/BrandIcon.imageset/BrandIcon@${scale}x.png" >/dev/null
done
echo "Wrote $iconset and $here/AppIcon-preview.png"
