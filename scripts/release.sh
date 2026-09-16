#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [ "$#" -ne 0 ]; then
    printf 'Usage: bash scripts/release.sh\n' >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
NOTES="$PROJECT_DIR/docs/releases/v$VERSION.md"
if [ ! -f "$NOTES" ]; then
    printf 'Error: Add release notes at %s before packaging.\n' "$NOTES" >&2
    exit 1
fi

bash scripts/test.sh
bash scripts/build.sh --universal
APP_DIR="$PROJECT_DIR/dist/release/PinchDial.app"
"$APP_DIR/Contents/MacOS/PinchDial" --check-gesture-encoding

STAGING_DIR=$(mktemp -d "$PROJECT_DIR/dist/.release-XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir "$STAGING_DIR/contents"
ditto "$APP_DIR" "$STAGING_DIR/contents/PinchDial.app"
ln -s /Applications "$STAGING_DIR/contents/Applications"
cp "$PROJECT_DIR/docs/Install.txt" "$STAGING_DIR/contents/Install.txt"

# Keep the asset name stable so GitHub's latest/download link survives updates.
hdiutil create -volname "PinchDial $VERSION" -srcfolder "$STAGING_DIR/contents" \
    -format UDZO -fs HFS+ "$STAGING_DIR/PinchDial.dmg"
bash scripts/verify-release.sh "$STAGING_DIR/PinchDial.dmg"
mv "$STAGING_DIR/PinchDial.dmg" "$PROJECT_DIR/dist/PinchDial.dmg"
(
    cd "$PROJECT_DIR/dist"
    shasum -a 256 PinchDial.dmg > PinchDial.dmg.sha256
)
cp "$NOTES" "$PROJECT_DIR/dist/ReleaseNotes.md"
printf '\nRelease %s ready:\n  %s\n  %s\n' "$VERSION" \
    "$PROJECT_DIR/dist/PinchDial.dmg" "$PROJECT_DIR/dist/PinchDial.dmg.sha256"
