#!/bin/zsh
# Build, bundle and sign Scratchbar.app. Usage: scripts/make-app.sh [--install]
set -euo pipefail
cd "${0:A:h}/.."

SIGN_ID="${SIGN_ID:-Developer ID Application: Geraint Preston (3PGY863R8D)}"
APP=build/Scratchbar.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Scratchbar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "$APP/Contents/Resources/Assets.car"
cp "$BIN" "$APP/Contents/MacOS/Scratchbar"

# Notarisation needs a secure timestamp; everyday builds skip it (it needs the network).
TIMESTAMP=--timestamp=none
[[ -n "${RELEASE:-}" ]] && TIMESTAMP=--timestamp
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Scratchbar || true
    rm -rf /Applications/Scratchbar.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Scratchbar.app"
fi
