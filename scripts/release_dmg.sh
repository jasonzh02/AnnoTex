#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AnnoTex"
VERSION="${VERSION:-0.1.0}"
PROJECT="AnnoTex.xcodeproj"
SCHEME="AnnoTex"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/AnnoTexTesterReleaseDerivedData}"
BUILD_ROOT="${BUILD_ROOT:-/private/tmp/AnnoTexTesterReleaseBuild}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS_PATH="$BUILD_ROOT/products"
STAGING_PATH="$BUILD_ROOT/dmg-staging"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-v$VERSION-not-notarized.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

RUN_TESTS=1
AD_HOC_SIGN=1
CLEAN=1

usage() {
    cat <<EOF
Usage: scripts/release_dmg.sh [options]

Builds a non-notarized tester DMG for AnnoTex v$VERSION.

Options:
  --skip-tests          Do not run AnnoTexTests before packaging.
  --no-ad-hoc-sign      Leave the app unsigned instead of applying an ad-hoc local signature.
  --no-clean            Reuse the existing temporary release build directory.
  -h, --help            Show this help.

Environment:
  VERSION               Release version. Default: 0.1.0.

This artifact is not Developer ID signed or notarized. Use it only for trusted
testers who understand macOS Gatekeeper warnings.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests)
            RUN_TESTS=0
            ;;
        --no-ad-hoc-sign)
            AD_HOC_SIGN=0
            ;;
        --no-clean)
            CLEAN=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command '$1' was not found" >&2
        exit 1
    fi
}

require_command xcodebuild
require_command hdiutil
require_command ditto
require_command codesign
require_command shasum

cd "$ROOT_DIR"

if [[ "$CLEAN" -eq 1 ]]; then
    rm -rf "$BUILD_ROOT" "$DIST_DIR"
fi
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

if [[ "$RUN_TESTS" -eq 1 ]]; then
    echo "==> Running AnnoTexTests"
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild -quiet \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath /private/tmp/AnnoTexReleaseTestDerivedData \
        CODE_SIGNING_ALLOWED=NO \
        test -only-testing:AnnoTexTests
fi

echo "==> Building unsigned Release app"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CONFIGURATION_BUILD_DIR="$PRODUCTS_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$PRODUCTS_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

echo "==> Creating DMG staging directory"
rm -rf "$STAGING_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/$APP_NAME.app"
ln -s /Applications "$STAGING_PATH/Applications"

if [[ "$AD_HOC_SIGN" -eq 1 ]]; then
    echo "==> Applying ad-hoc local signature"
    codesign --force --deep --sign - --timestamp=none \
        --entitlements "$ROOT_DIR/AnnoTex/AnnoTex.entitlements" \
        "$STAGING_PATH/$APP_NAME.app"
    codesign --verify --deep --strict --verbose=2 "$STAGING_PATH/$APP_NAME.app"
else
    echo "==> Leaving app unsigned by request"
fi

echo "==> Creating DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Writing checksum"
(
    cd "$DIST_DIR"
    LC_ALL=C LANG=C shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Release artifact: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
echo "Warning: this DMG is not Developer ID signed or notarized."
echo "Trusted testers may need to right-click Open or approve the app in Privacy & Security."
