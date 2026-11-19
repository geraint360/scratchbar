#!/bin/zsh
# Rebuilds the app icon: draws the note layer (scripts/make-icon.swift) into
# Resources/AppIcon.icon (an Icon Composer project), then compiles it with
# Xcode's actool into Resources/Assets.car (macOS 26+) and Resources/AppIcon.icns
# (the fallback for macOS 14 and 15). Needs Xcode 26 or later.
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift scripts/make-icon.swift Resources/AppIcon.icon/Assets

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
xcrun actool Resources/AppIcon.icon \
    --compile "$TMP" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$TMP/partial.plist" \
    --app-icon AppIcon --include-all-app-icons \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --platform macosx
cp "$TMP/Assets.car" Resources/Assets.car
cp "$TMP/AppIcon.icns" Resources/AppIcon.icns

# README picture: the compiled icon at 256 px.
iconutil -c iconset Resources/AppIcon.icns -o "$TMP/set.iconset"
cp "$TMP/set.iconset/icon_128x128@2x.png" docs/images/icon.png
echo "Wrote Resources/Assets.car, Resources/AppIcon.icns and docs/images/icon.png"
