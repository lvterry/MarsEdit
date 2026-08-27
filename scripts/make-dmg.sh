#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

APP_NAME="Yanmo"
PROJECT_NAME="Yanmo"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PROJECT_NAME}/Info.plist")
BUILD_DIR="build"
DIST_DIR="dist"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

# Distribution signing: Developer ID + notarization so Gatekeeper
# passes on machines that never saw this Mac.
SIGN_IDENTITY="Developer ID Application"
NOTARY_PROFILE="yanmo-notary"

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  echo "notarytool keychain profile '${NOTARY_PROFILE}' not found" >&2
  echo "set it up once with:" >&2
  echo "  xcrun notarytool store-credentials ${NOTARY_PROFILE}" >&2
  echo "(uses an App Store Connect API key or app-specific password)" >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -target "$PROJECT_NAME" \
  -configuration Release \
  CONFIGURATION_BUILD_DIR="${PWD}/${BUILD_DIR}/Release" \
  build

APP_PATH="${BUILD_DIR}/Release/${APP_NAME}.app"

codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# Notarize the app itself so it launches offline, then staple the ticket on.
APP_ZIP="${BUILD_DIR}/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --wait --keychain-profile "${NOTARY_PROFILE}"
xcrun stapler staple "$APP_PATH"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

# Notarize the DMG too: downloaded DMGs are quarantined and assessed as well.
echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "${NOTARY_PROFILE}"
xcrun stapler staple "$DMG_PATH"

echo
echo "DMG written to: $DMG_PATH (signed and notarized)"
