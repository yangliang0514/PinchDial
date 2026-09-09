#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
# Reuse this certificate and its private key across rebuilds. Never fall back to
# ad-hoc signing: that makes the designated requirement depend on the code hash.
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-PinchDial Local Development}"
if ! SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"; then
    printf 'Error: Could not read code-signing identities. Unlock your login keychain and retry.\n' >&2
    exit 1
fi
if [ "$CODE_SIGN_IDENTITY" = "-" ] || ! printf '%s\n' "$SIGNING_IDENTITIES" | grep -F -- "\"$CODE_SIGN_IDENTITY\"" >/dev/null; then
    cat >&2 <<EOF
Error: Valid code-signing identity "$CODE_SIGN_IDENTITY" was not found.
PinchDial requires a persistent local certificate; ad-hoc signing is disabled.

One-time setup in Keychain Access:
  Certificate Assistant > Create a Certificate…
  Name: $CODE_SIGN_IDENTITY
  Identity Type: Self Signed Root
  Certificate Type: Code Signing
  Save in the login keychain and retain its private key.
  In the certificate's Trust section, set Code Signing to Always Trust.

See README.md, "One-time local signing setup", for the full steps.
Then run: bash scripts/build.sh
For another certificate name, set CODE_SIGN_IDENTITY when running the script.
EOF
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-module-cache"
BUILD_OPTIONS=(--disable-sandbox --scratch-path "$PROJECT_DIR/.build" --cache-path "$PROJECT_DIR/.build/cache" --config-path "$PROJECT_DIR/.build/configuration" --security-path "$PROJECT_DIR/.build/security")
swift build "${BUILD_OPTIONS[@]}" -c release
BIN_DIR="$(swift build "${BUILD_OPTIONS[@]}" -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/PinchDial.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/PinchDial" "$APP_DIR/Contents/MacOS/PinchDial"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Icons/AppIcon.icns" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/Resources/Icons/MenuBarIcon.png" "$PROJECT_DIR/Resources/Icons/MenuBarIcon@2x.png" "$APP_DIR/Contents/Resources/"
codesign --force --timestamp=none --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
codesign -dv --verbose=4 "$APP_DIR"
codesign -d -r- "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
