#!/bin/zsh
# Build a signed, notarised and stapled Scratchbar-<version>.zip for GitHub Releases.
# Usage: scripts/release.sh            (builds build/Scratchbar-<version>.zip)
#        scripts/release.sh --publish  (also creates the GitHub release v<version>)
#
# One-time setup: save notarisation credentials in the keychain as "notary":
#   xcrun notarytool store-credentials notary --apple-id <you> --team-id 3PGY863R8D
# (it asks for an app-specific password from account.apple.com).
set -euo pipefail
cd "${0:A:h}/.."

PROFILE="${NOTARY_PROFILE:-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/Scratchbar.app
ZIP="build/Scratchbar-$VERSION.zip"

if [[ "${1:-}" == "--publish" ]] && git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "Tag v$VERSION already exists: bump CFBundleShortVersionString in Resources/Info.plist." >&2
    exit 1
fi

RELEASE=1 scripts/make-app.sh

echo "Notarising (this usually takes a minute or two)…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

# Re-zip so the download carries the stapled ticket (opens offline too).
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"

if [[ "${1:-}" == "--publish" ]]; then
    gh release create "v$VERSION" "$ZIP" --title "Scratchbar $VERSION" --generate-notes
fi
