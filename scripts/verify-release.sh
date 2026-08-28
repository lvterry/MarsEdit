#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly APP_NAME="Yanmo"
readonly REPOSITORY="lvterry/Yanmo"
readonly SPARKLE_KEY_ACCOUNT="com.yanmo.app"
readonly SOURCE_INFO="Yanmo/Info.plist"

fail() {
  echo "$1" >&2
  exit 1
}

xml_value() {
  xmllint --xpath "string($1)" "$APPCAST_PATH"
}

if [[ $# -ne 6 ]]; then
  fail "usage: $0 <appcast> <dmg> <notes> <version> <build> <sparkle-bin>"
fi

readonly APPCAST_PATH="$1"
readonly DMG_PATH="$2"
readonly NOTES_PATH="$3"
readonly VERSION="$4"
readonly BUILD="$5"
readonly SPARKLE_BIN="$6"
readonly RELEASE_TAG="${YANMO_RELEASE_TAG:-v${VERSION}}"
readonly RELEASE_PREFIX="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}"
readonly EXPECTED_DMG_URL="${RELEASE_PREFIX}/$(basename "$DMG_PATH")"
readonly EXPECTED_NOTES_URL="${RELEASE_PREFIX}/$(basename "$NOTES_PATH")"

for path in "$APPCAST_PATH" "$DMG_PATH" "$NOTES_PATH"; do
  [[ -f "$path" ]] || fail "file not found: ${path}"
done
[[ -x "${SPARKLE_BIN}/sign_update" ]] || fail "sign_update not found"
[[ -x "${SPARKLE_BIN}/generate_keys" ]] || fail "generate_keys not found"

readonly TEMP_DIR=$(mktemp -d)
readonly MOUNT_DIR="${TEMP_DIR}/mount"
readonly TAMPERED_DMG="${TEMP_DIR}/tampered.dmg"
mkdir -p "$MOUNT_DIR"

cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

xmllint --noout "$APPCAST_PATH"

readonly ITEM_COUNT=$(xmllint --xpath 'count(//*[local-name()="item"])' "$APPCAST_PATH")
[[ "$ITEM_COUNT" == "1" ]] || fail "appcast must contain one item"

readonly FEED_BUILD=$(xml_value '(//*[local-name()="version"])[1]')
readonly FEED_VERSION=$(xml_value '(//*[local-name()="shortVersionString"])[1]')
readonly FEED_MINIMUM=$(xml_value '(//*[local-name()="minimumSystemVersion"])[1]')
readonly ENCLOSURE_URL=$(xml_value '(//*[local-name()="enclosure"])[1]/@url')
readonly ENCLOSURE_LENGTH=$(xml_value '(//*[local-name()="enclosure"])[1]/@length')
readonly ENCLOSURE_SIGNATURE=$(xml_value '(//*[local-name()="enclosure"])[1]/@*[local-name()="edSignature"]')
readonly NOTES_URL=$(xml_value '(//*[local-name()="releaseNotesLink"])[1]')
readonly DMG_LENGTH=$(stat -f%z "$DMG_PATH")

[[ "$FEED_BUILD" == "$BUILD" ]] || fail "appcast build mismatch: ${FEED_BUILD}"
[[ "$FEED_VERSION" == "$VERSION" ]] || fail "appcast version mismatch: ${FEED_VERSION}"
[[ "$ENCLOSURE_URL" == "$EXPECTED_DMG_URL" ]] || fail "mutable or wrong DMG URL: ${ENCLOSURE_URL}"
[[ "$NOTES_URL" == "$EXPECTED_NOTES_URL" ]] || fail "mutable or wrong notes URL: ${NOTES_URL}"
[[ "$ENCLOSURE_LENGTH" == "$DMG_LENGTH" ]] || fail "appcast file length mismatch"
[[ -n "$ENCLOSURE_SIGNATURE" ]] || fail "appcast has no EdDSA signature"

"${SPARKLE_BIN}/sign_update" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --verify "$DMG_PATH" "$ENCLOSURE_SIGNATURE" >/dev/null

cp "$DMG_PATH" "$TAMPERED_DMG"
printf 'tampered' >> "$TAMPERED_DMG"
if "${SPARKLE_BIN}/sign_update" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --verify "$TAMPERED_DMG" "$ENCLOSURE_SIGNATURE" >/dev/null 2>&1; then
  fail "EdDSA verification accepted a modified DMG"
fi

hdiutil attach "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_DIR" \
  -quiet

readonly APP_PATH="${MOUNT_DIR}/${APP_NAME}.app"
readonly APP_INFO="${APP_PATH}/Contents/Info.plist"
[[ -f "$APP_INFO" ]] || fail "packaged app not found"

readonly APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")
readonly APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO")
readonly APP_MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO")
readonly APP_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_INFO")
readonly SOURCE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$SOURCE_INFO")
readonly SIGNING_PUBLIC_KEY=$("${SPARKLE_BIN}/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p)

[[ "$APP_VERSION" == "$VERSION" ]] || fail "packaged version mismatch: ${APP_VERSION}"
[[ "$APP_BUILD" == "$BUILD" ]] || fail "packaged build mismatch: ${APP_BUILD}"
[[ "$APP_MINIMUM" == "$FEED_MINIMUM" ]] || fail "minimum system version mismatch"
[[ "$APP_PUBLIC_KEY" == "$SOURCE_PUBLIC_KEY" ]] || fail "packaged public key mismatch"
[[ "$APP_PUBLIC_KEY" == "$SIGNING_PUBLIC_KEY" ]] || fail "signing public key mismatch"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "Verified ${APP_NAME} ${VERSION} (${BUILD})"
