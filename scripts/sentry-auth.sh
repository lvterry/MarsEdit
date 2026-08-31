#!/usr/bin/env bash

readonly SENTRY_TOKEN_PREFIX="sntrys_"

valid_sentry_token() {
  local token="${1:-}"

  [[ "$token" == "${SENTRY_TOKEN_PREFIX}"* ]] || return 1
  [[ "$token" != *[[:space:]]* ]]
}

read_sentry_token() {
  local service="$1"
  local account="$2"
  local token

  token=$(security find-generic-password -w -a "$account" -s "$service") || return 1
  if ! valid_sentry_token "$token"; then
    echo "invalid Sentry token in Keychain; expected raw sntrys_ token without spaces" >&2
    return 1
  fi

  printf '%s' "$token"
}
