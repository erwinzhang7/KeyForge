#!/usr/bin/env bash
# Build KeyForge.app from the SwiftPM executable and wrap it with the
# proper Info.plist + entitlements for an LSUIElement menu bar agent.
#
# Usage: ./Scripts/make-app.sh [--release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="debug"
SWIFT_FLAGS=()
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
    SWIFT_FLAGS+=("-c" "release")
fi

echo "▶ Building KeyForge (${CONFIG})..."
swift build ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

BIN_PATH="$(swift build ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)/KeyForge"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "✗ Could not find built binary at $BIN_PATH"
    exit 1
fi

APP_DIR="$ROOT/build/KeyForge.app"
echo "▶ Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/KeyForge"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Sign with a STABLE code-signing identity so the macOS Accessibility (TCC)
# grant survives rebuilds. Ad-hoc (`-`) changes the binary's cdhash on every
# build, which silently invalidates the grant and forces a re-authorize.
#
# Resolution order:
#   1. $KEYFORGE_SIGN_ID if set
#   2. "KeyForge Dev" self-signed identity, if present in the keychain
#   3. "NotchApp Dev" self-signed identity, if present (shared dev cert)
#   4. ad-hoc fallback (works, but grant breaks on every rebuild)
# To create your own durable identity: Keychain Access > Certificate Assistant
# > Create a Certificate (Code Signing, Self Signed Root), then export its name
# via KEYFORGE_SIGN_ID.
SIGN_ID="${KEYFORGE_SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    for candidate in "KeyForge Dev" "NotchApp Dev"; do
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "$candidate"; then
            SIGN_ID="$candidate"
            break
        fi
    done
fi
SIGN_ID="${SIGN_ID:--}"

if [[ "$SIGN_ID" == "-" ]]; then
    echo "▶ Signing ad-hoc (no stable identity found; Accessibility grant will reset on rebuild)"
else
    echo "▶ Signing with stable identity: ${SIGN_ID}"
fi
codesign --force --options runtime --entitlements "$ROOT/Resources/KeyForge.entitlements" --sign "$SIGN_ID" "$APP_DIR" || true

echo "✓ Built $APP_DIR"
echo "  Run with: open '$APP_DIR'"
