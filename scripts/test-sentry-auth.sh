#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/sentry-auth.sh

expect_valid() {
  valid_sentry_token "$1" || {
    echo "expected valid token" >&2
    exit 1
  }
}

expect_invalid() {
  if valid_sentry_token "$1"; then
    echo "expected invalid token" >&2
    exit 1
  fi
}

expect_valid "sntrys_example"
expect_invalid ""
expect_invalid "org:ci token"
expect_invalid "Bearer sntrys_example"
expect_invalid "sntrys_example token"

echo "Sentry token checks passed"
