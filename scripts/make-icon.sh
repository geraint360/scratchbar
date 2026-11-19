#!/bin/zsh
# Rebuilds Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."
TMP=$(mktemp -d)
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
swift scripts/make-icon.swift "$TMP/icon.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$TMP/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$TMP/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon.png" docs/images/icon.png
sips -z 256 256 docs/images/icon.png >/dev/null
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns and docs/images/icon.png"
