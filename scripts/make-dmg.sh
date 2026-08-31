#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/sentry-auth.sh

readonly APP_NAME="Yanmo"
readonly PROJECT_NAME="Yanmo"
readonly NOTARY_PROFILE="yanmo-notary"
readonly BUILD_DIR="build"
readonly DIST_DIR="dist"
readonly TEMP_ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
readonly EXPORT_DIR="${BUILD_DIR}/export"
readonly EXPORT_OPTIONS="scripts/ExportOptions.plist"
readonly SOURCE_PACKAGES="${BUILD_DIR}/SourcePackages"
readonly INFO_PLIST="${PROJECT_NAME}/Info.plist"
readonly SIGN_IDENTITY="Developer ID Application"
readonly SENTRY_ORG="yanmo-po"
readonly SENTRY_PROJECT="yanmo-macos"
readonly SENTRY_KEYCHAIN_SERVICE="com.yanmo.app.sentry"
readonly SENTRY_KEYCHAIN_ACCOUNT="org-ci"

readonly VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
readonly BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
readonly DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
readonly ARCHIVE_DATE=$(date +%F)
readonly ARCHIVE_DIR="${HOME}/Library/Developer/Xcode/Archives/${ARCHIVE_DATE}"
readonly ARCHIVE_NAME="${APP_NAME}-${VERSION}-build-${BUILD}"
readonly ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}.xcarchive"
readonly ARCHIVE_METADATA="${ARCHIVE_DIR}/${ARCHIVE_NAME}.txt"
readonly SENTRY_RELEASE="com.yanmo.app@${VERSION}+${BUILD}"

fail() {
  echo "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null || fail "required tool not found: $1"
}

binary_uuids() {
  dwarfdump --uuid "$1" | awk '{print $2}' | sort
}

for tool in dwarfdump security sentry-cli shasum; do
  require_tool "$tool"
done

SENTRY_AUTH_TOKEN=$(read_sentry_token \
  "$SENTRY_KEYCHAIN_SERVICE" \
  "$SENTRY_KEYCHAIN_ACCOUNT")
env \
  "SENTRY_AUTH_TOKEN=$SENTRY_AUTH_TOKEN" \
  "SENTRY_ORG=$SENTRY_ORG" \
  "SENTRY_PROJECT=$SENTRY_PROJECT" \
  sentry-cli releases list >/dev/null

[[ ! -e "$ARCHIVE_PATH" ]] || fail "archive already exists: ${ARCHIVE_PATH}"
[[ ! -e "$ARCHIVE_METADATA" ]] || fail "archive metadata already exists: ${ARCHIVE_METADATA}"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "notary profile '${NOTARY_PROFILE}' not found" >&2
  echo "run: xcrun notarytool store-credentials ${NOTARY_PROFILE}" >&2
  exit 1
fi

rm -rf "$TEMP_ARCHIVE_PATH" "$EXPORT_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodegen generate

echo "==> Archiving"
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$TEMP_ARCHIVE_PATH" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  archive

readonly ARCHIVED_APP="${TEMP_ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
readonly APP_BINARY="${ARCHIVED_APP}/Contents/MacOS/${APP_NAME}"
readonly APP_DSYM="${TEMP_ARCHIVE_PATH}/dSYMs/${APP_NAME}.app.dSYM"
readonly APP_UUIDS=$(binary_uuids "$APP_BINARY")
readonly DSYM_UUIDS=$(binary_uuids "$APP_DSYM")

[[ -n "$APP_UUIDS" ]] || fail "app binary has no UUID"
[[ "$APP_UUIDS" == "$DSYM_UUIDS" ]] || fail "app and dSYM UUIDs differ"

echo "==> Uploading Sentry symbols"
export SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT
if ! sentry-cli releases info "$SENTRY_RELEASE" >/dev/null 2>&1; then
  sentry-cli releases new "$SENTRY_RELEASE"
fi
sentry-cli debug-files upload "$APP_DSYM"
sentry-cli releases finalize "$SENTRY_RELEASE"
unset SENTRY_AUTH_TOKEN

echo "==> Exporting Developer ID app"
xcodebuild \
  -exportArchive \
  -archivePath "$TEMP_ARCHIVE_PATH" \
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

echo "==> Signing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "$NOTARY_PROFILE"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "==> Preserving release archive"
mkdir -p "$ARCHIVE_DIR"
mv "$TEMP_ARCHIVE_PATH" "$ARCHIVE_PATH"

readonly DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
{
  echo "version=${VERSION}"
  echo "build=${BUILD}"
  echo "release=${SENTRY_RELEASE}"
  echo "dsym_uuids=${DSYM_UUIDS//$'\n'/,}"
  echo "dmg_sha256=${DMG_SHA256}"
} > "$ARCHIVE_METADATA"

echo "DMG: $DMG_PATH"
echo "Archive: $ARCHIVE_PATH"
