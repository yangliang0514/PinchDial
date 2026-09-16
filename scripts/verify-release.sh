#!/bin/bash
set -euo pipefail
if [ "$#" -ne 1 ]; then
    printf 'Usage: bash scripts/verify-release.sh /path/to/PinchDial.dmg\n' >&2
    exit 1
fi
DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
hdiutil verify "$DMG_PATH"
VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pinchdial-verify-XXXXXX")
MOUNT_POINT="$VERIFY_DIR/mount"
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" = 1 ]; then
        if ! hdiutil detach "$MOUNT_POINT"; then
            printf 'Could not detach verification volume at %s; leaving it for manual cleanup.\n' "$MOUNT_POINT" >&2
            return
        fi
    fi
    rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT
mkdir "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT"
MOUNTED=1
APP_DIR="$MOUNT_POINT/PinchDial.app"
codesign --verify --strict --verbose=2 "$APP_DIR"
for architecture in arm64 x86_64; do
    lipo "$APP_DIR/Contents/MacOS/PinchDial" -verify_arch "$architecture"
done
plutil -lint "$APP_DIR/Contents/Info.plist"
test "$(readlink "$MOUNT_POINT/Applications")" = /Applications
test -s "$MOUNT_POINT/Install.txt"
test -s "$APP_DIR/Contents/Resources/AppIcon.icns"
test -s "$APP_DIR/Contents/Resources/MenuBarIcon.png"
test -s "$APP_DIR/Contents/Resources/MenuBarIcon@2x.png"
# Check a copied app, just as it would be copied out of the disk image to install.
ditto "$APP_DIR" "$VERIFY_DIR/PinchDial.app"
codesign --verify --strict "$VERIFY_DIR/PinchDial.app"
"$VERIFY_DIR/PinchDial.app/Contents/MacOS/PinchDial" --check-gesture-encoding
printf 'Verified universal app, signature, resources, installation copy, and gesture encoding.\n'
