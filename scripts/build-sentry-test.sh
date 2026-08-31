#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly APP_NAME="Yanmo"
readonly INFO_PLIST="${APP_NAME}/Info.plist"
readonly TEST_VERSION="0.10.0"
readonly DEFAULT_TEST_BUILD="8.1"
readonly SENTRY_ENVIRONMENT="staging"
readonly TEST_BUILD="${1:-$DEFAULT_TEST_BUILD}"
readonly INFO_BACKUP=$(mktemp)

fail() {
  echo "$1" >&2
  exit 1
}

restore_info() {
  cp "$INFO_BACKUP" "$INFO_PLIST"
  rm -f "$INFO_BACKUP"
}

cp "$INFO_PLIST" "$INFO_BACKUP"
trap restore_info EXIT

[[ $# -le 1 ]] || fail "usage: $0 [8.<positive integer>]"
[[ "$TEST_BUILD" =~ ^8\.[1-9][0-9]*$ ]] || \
  fail "test build must match 8.<positive integer>"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString ${TEST_VERSION}" \
  -c "Set :CFBundleVersion ${TEST_BUILD}" \
  "$INFO_PLIST"

if ! /usr/libexec/PlistBuddy \
  -c "Set :SentryEnvironment ${SENTRY_ENVIRONMENT}" \
  "$INFO_PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy \
    -c "Add :SentryEnvironment string ${SENTRY_ENVIRONMENT}" \
    "$INFO_PLIST"
fi

./scripts/make-dmg.sh

echo "Staging DMG: dist/${APP_NAME}-${TEST_VERSION}.dmg"
