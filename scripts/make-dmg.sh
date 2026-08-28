#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly APP_NAME="Yanmo"
readonly PROJECT_NAME="Yanmo"
readonly NOTARY_PROFILE="yanmo-notary"
readonly BUILD_DIR="build"
readonly DIST_DIR="dist"
readonly ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
readonly EXPORT_DIR="${BUILD_DIR}/export"
readonly EXPORT_OPTIONS="scripts/ExportOptions.plist"
readonly SOURCE_PACKAGES="${BUILD_DIR}/SourcePackages"
readonly INFO_PLIST="${PROJECT_NAME}/Info.plist"

readonly VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
readonly DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "notary profile '${NOTARY_PROFILE}' not found" >&2
  echo "run: xcrun notarytool store-credentials ${NOTARY_PROFILE}" >&2
  exit 1
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodegen generate

echo "==> Archiving"
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  archive

echo "==> Exporting Developer ID app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

readonly APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Notarizing app"
readonly APP_ZIP="${BUILD_DIR}/${APP_NAME}.zip"
rm -f "$APP_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --wait --keychain-profile "$NOTARY_PROFILE"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"

readonly STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP_PATH" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs APFS \
  -ov \
  -format ULFO \
  "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "$NOTARY_PROFILE"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "DMG: $DMG_PATH"
