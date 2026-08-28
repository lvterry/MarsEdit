#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly APP_NAME="Yanmo"
readonly INFO_PLIST="Yanmo/Info.plist"
readonly APPCAST_PATH="docs/appcast.xml"
readonly APPCAST_URL="https://lvterry.github.io/Yanmo/appcast.xml"
readonly REPOSITORY="lvterry/Yanmo"
readonly SPARKLE_KEY_ACCOUNT="com.yanmo.app"
readonly PAGES_BRANCH="main"
readonly PAGES_PATH="/docs"

fail() {
  echo "$1" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

history_values() {
  local key="$1"
  local commit

  while read -r commit; do
    git show "${commit}:${INFO_PLIST}" 2>/dev/null \
      | plutil -extract "$key" raw -o - - 2>/dev/null \
      || true
  done < <(git log --format=%H -- "$INFO_PLIST")
}

require_tool() {
  command -v "$1" >/dev/null || fail "required tool not found: $1"
}

ensure_pages() {
  local source

  if source=$(gh api "repos/${REPOSITORY}/pages" --jq '.source | "\(.branch):\(.path)"' 2>/dev/null); then
    [[ "$source" == "${PAGES_BRANCH}:${PAGES_PATH}" ]] \
      || fail "GitHub Pages must publish main:/docs; found ${source}"
    return
  fi

  gh api --method POST "repos/${REPOSITORY}/pages" \
    -f "source[branch]=${PAGES_BRANCH}" \
    -f "source[path]=${PAGES_PATH}" >/dev/null
}

wait_for_appcast() {
  local attempt
  local downloaded

  downloaded=$(mktemp)
  for attempt in {1..60}; do
    if curl --fail --location --silent \
      "${APPCAST_URL}?build=${NEW_BUILD}" -o "$downloaded" \
      && cmp -s "$APPCAST_PATH" "$downloaded"; then
      rm -f "$downloaded"
      return
    fi

    sleep 5
  done

  rm -f "$downloaded"
  fail "published appcast did not become available: ${APPCAST_URL}"
}

if [[ $# -ne 2 ]]; then
  fail "usage: $0 <version> <notes-file>"
fi

readonly VERSION="$1"
readonly NOTES_FILE="$2"
readonly TAG="v${VERSION}"
readonly RELEASE_PREFIX="https://github.com/${REPOSITORY}/releases/download/${TAG}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "version must contain two or three numeric components"

for tool in curl gh git plutil xcodebuild xcodegen xmllint; do
  require_tool "$tool"
done

[[ -f "$NOTES_FILE" ]] || fail "notes file not found: ${NOTES_FILE}"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is dirty"
[[ "$(git branch --show-current)" == "main" ]] || fail "release from main"

git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || fail "main must match origin/main"

git rev-parse "$TAG" >/dev/null 2>&1 && fail "tag already exists: ${TAG}"
git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1 \
  && fail "remote tag already exists: ${TAG}"
gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1 \
  && fail "GitHub release already exists: ${TAG}"

if history_values CFBundleShortVersionString | grep -Fx "$VERSION" >/dev/null; then
  fail "version was already used: ${VERSION}"
fi

readonly CURRENT_BUILD=$(plist_value CFBundleVersion)
readonly MAX_BUILD=$(history_values CFBundleVersion | sort -n | tail -1)

[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || fail "current build is not numeric"
[[ "$MAX_BUILD" =~ ^[0-9]+$ ]] || fail "repository has no numeric build"

readonly NEW_BUILD=$((CURRENT_BUILD + 1))

[[ "$CURRENT_BUILD" -ge "$MAX_BUILD" ]] \
  || fail "current build ${CURRENT_BUILD} is below repository maximum ${MAX_BUILD}"

readonly REMOTE_APPCAST=$(mktemp)
if curl --fail --location --silent --show-error "$APPCAST_URL" -o "$REMOTE_APPCAST"; then
  REMOTE_BUILD=$(xmllint --xpath \
    'string((//*[local-name()="version"])[1])' "$REMOTE_APPCAST")

  if [[ "$REMOTE_BUILD" =~ ^[0-9]+$ ]] && [[ "$NEW_BUILD" -le "$REMOTE_BUILD" ]]; then
    rm -f "$REMOTE_APPCAST"
    fail "build ${NEW_BUILD} is not newer than published build ${REMOTE_BUILD}"
  fi
fi
rm -f "$REMOTE_APPCAST"

readonly PLIST_BACKUP=$(mktemp)
cp "$INFO_PLIST" "$PLIST_BACKUP"
VERSION_COMMITTED=0

cleanup() {
  if [[ "$VERSION_COMMITTED" -eq 0 ]]; then
    cp "$PLIST_BACKUP" "$INFO_PLIST"
  fi

  rm -f "$PLIST_BACKUP"
}
trap cleanup EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$INFO_PLIST"

echo "==> Testing"
xcodegen generate
xcodebuild \
  -scheme Yanmo \
  -destination 'platform=macOS' \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  test

echo "==> Building packaged release"
./scripts/make-dmg.sh

readonly DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
[[ -f "$DMG_PATH" ]] || fail "expected DMG not found: ${DMG_PATH}"

readonly UPDATE_DIR=$(mktemp -d)
readonly NOTES_ASSET="${UPDATE_DIR}/${APP_NAME}-${VERSION}.md"
readonly GENERATED_APPCAST="${UPDATE_DIR}/appcast.xml"
trap 'cleanup; rm -rf "$UPDATE_DIR"' EXIT

cp "$DMG_PATH" "$UPDATE_DIR/"
cp "$NOTES_FILE" "$NOTES_ASSET"

readonly SPARKLE_BIN=$(./scripts/sparkle-tools.sh)
"${SPARKLE_BIN}/generate_appcast" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "${RELEASE_PREFIX}/" \
  --release-notes-url-prefix "${RELEASE_PREFIX}/" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$GENERATED_APPCAST" \
  "$UPDATE_DIR"

./scripts/verify-release.sh \
  "$GENERATED_APPCAST" \
  "$DMG_PATH" \
  "$NOTES_ASSET" \
  "$VERSION" \
  "$NEW_BUILD" \
  "$SPARKLE_BIN"

echo "==> Committing version"
git add "$INFO_PLIST"
git commit -m "Release ${TAG}"
VERSION_COMMITTED=1

git tag "$TAG"
git push origin main
git push origin "$TAG"

echo "==> Publishing GitHub assets"
gh release create "$TAG" "$DMG_PATH" "$NOTES_ASSET" \
  --repo "$REPOSITORY" \
  --title "${APP_NAME} ${VERSION}" \
  --notes-file "$NOTES_FILE" \
  --verify-tag

readonly DOWNLOADED_DMG=$(mktemp)
readonly DOWNLOADED_NOTES=$(mktemp)
trap 'cleanup; rm -rf "$UPDATE_DIR"; rm -f "$DOWNLOADED_DMG" "$DOWNLOADED_NOTES"' EXIT

curl --fail --location --retry 5 --retry-all-errors --retry-delay 2 --silent --show-error \
  "${RELEASE_PREFIX}/$(basename "$DMG_PATH")" -o "$DOWNLOADED_DMG"
curl --fail --location --retry 5 --retry-all-errors --retry-delay 2 --silent --show-error \
  "${RELEASE_PREFIX}/$(basename "$NOTES_ASSET")" -o "$DOWNLOADED_NOTES"
cmp -s "$DMG_PATH" "$DOWNLOADED_DMG" || fail "published DMG differs from local asset"
cmp -s "$NOTES_ASSET" "$DOWNLOADED_NOTES" || fail "published notes differ from local asset"

echo "==> Publishing appcast"
cp "$GENERATED_APPCAST" "$APPCAST_PATH"
git add "$APPCAST_PATH"
git commit -m "Publish appcast for ${TAG}"
git push origin main

ensure_pages
wait_for_appcast

echo "Released ${TAG}: https://github.com/${REPOSITORY}/releases/tag/${TAG}"
