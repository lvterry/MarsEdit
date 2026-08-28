#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly SPARKLE_VERSION="2.9.6"
readonly ARCHIVE_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
readonly TOOLS_DIR="${PWD}/build/sparkle-tools/${SPARKLE_VERSION}"
readonly BIN_DIR="${TOOLS_DIR}/bin"
readonly ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

if [[ -x "${BIN_DIR}/generate_appcast" \
  && -x "${BIN_DIR}/generate_keys" \
  && -x "${BIN_DIR}/sign_update" ]]; then
  echo "$BIN_DIR"
  exit
fi

readonly TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

curl --fail --location --retry 3 --silent --show-error \
  "$ARCHIVE_URL" -o "${TEMP_DIR}/Sparkle.tar.xz"

readonly ACTUAL_SHA256=$(shasum -a 256 "${TEMP_DIR}/Sparkle.tar.xz" | awk '{print $1}')
if [[ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]]; then
  echo "Sparkle tool archive checksum mismatch" >&2
  exit 1
fi

rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"
tar -xJf "${TEMP_DIR}/Sparkle.tar.xz" -C "$TOOLS_DIR"

echo "$BIN_DIR"
