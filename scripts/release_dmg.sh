#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AnnoTex"
VERSION="${VERSION:-0.1.0}"
PROJECT="AnnoTex.xcodeproj"
SCHEME="AnnoTex"
CONFIGURATION="Release"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-annotex-notarytool}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/AnnoTexReleaseDerivedData}"
BUILD_ROOT="${BUILD_ROOT:-/private/tmp/AnnoTexReleaseBuild}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
EXPORT_OPTIONS="$BUILD_ROOT/ExportOptions.plist"
STAGING_PATH="$BUILD_ROOT/dmg-staging"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-v$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

RUN_TESTS=1
RUN_NOTARIZATION=1
CLEAN=1

usage() {
    cat <<EOF
Usage: APPLE_TEAM_ID=<team-id> [NOTARY_PROFILE=annotex-notarytool] scripts/release_dmg.sh [options]

Builds a Developer ID signed DMG for AnnoTex v$VERSION.

Options:
  --skip-tests          Do not run AnnoTexTests before packaging.
  --skip-notarization   Create and sign the DMG, but do not submit or staple it. Not for publishing.
  --no-clean            Reuse the existing temporary release build directory.
  -h, --help            Show this help.

Environment:
  APPLE_TEAM_ID         Required Apple Developer Team ID.
  NOTARY_PROFILE        notarytool keychain profile. Default: annotex-notarytool.
  SIGNING_IDENTITY      Code signing identity search string. Default: Developer ID Application.
  VERSION               Release version. Default: 0.1.0.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests)
            RUN_TESTS=0
            ;;
        --skip-notarization)
            RUN_NOTARIZATION=0
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
require_command xcrun
require_command codesign
require_command security
require_command shasum

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "error: APPLE_TEAM_ID is required" >&2
    echo "Run 'xcrun notarytool store-credentials \"$NOTARY_PROFILE\" ...' before notarized releases." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" >/dev/null; then
    echo "error: no code signing identity matching '$SIGNING_IDENTITY' was found in Keychain" >&2
    echo "Install a Developer ID Application certificate, then rerun this script." >&2
    exit 1
fi

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

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingCertificate</key>
    <string>$SIGNING_IDENTITY</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
EOF

echo "==> Archiving $APP_NAME $VERSION"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    archive

echo "==> Exporting Developer ID app"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -quiet \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: exported app not found at $APP_PATH" >&2
    exit 1
fi

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Creating DMG"
rm -rf "$STAGING_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/$APP_NAME.app"
ln -s /Applications "$STAGING_PATH/Applications"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "$RUN_NOTARIZATION" -eq 1 ]]; then
    echo "==> Notarizing DMG with notarytool profile '$NOTARY_PROFILE'"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -vv --type open "$DMG_PATH"
else
    echo "==> Skipping notarization by request"
fi

echo "==> Writing checksum"
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Release artifact: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
