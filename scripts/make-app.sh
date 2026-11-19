#!/bin/zsh
# Build, bundle and sign Scratchbar.app. Usage: scripts/make-app.sh [--install]
set -euo pipefail
cd "${0:A:h}/.."

SIGN_ID="${SIGN_ID:-Developer ID Application: Geraint Preston (3PGY863R8D)}"
APP=build/Scratchbar.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Scratchbar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Scratchbar"

codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Scratchbar || true
    rm -rf /Applications/Scratchbar.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Scratchbar.app"
fi
