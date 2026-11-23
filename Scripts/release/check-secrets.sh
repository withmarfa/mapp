#!/usr/bin/env bash
# Stops a tag run that lacks a value its job needs, or holds one of the wrong shape. Prints names, never values.
#
#   check-secrets.sh build|publish
#
# `build` is the job that signs and notarizes, `publish` the one that uploads. Each reads its values from the environment.
set -euo pipefail

job="${1:-}"
problems=()

require() {
  local name="$1" pattern="$2" what="$3"
  local value="${!name:-}"
  if [ -z "$value" ]; then
    problems+=("$name is not set.")
  elif ! [[ "$value" =~ $pattern ]]; then
    problems+=("$name is not $what.")
  fi
}

case "$job" in
  build)
    require APPLE_DEVELOPER_ID_P12 '^[A-Za-z0-9+/=]+$' 'base64'
    require APPLE_DEVELOPER_ID_P12_PASSWORD '.' 'a password'
    require APPLE_NOTARY_KEY '^-----BEGIN PRIVATE KEY-----' 'a PEM private key'
    require APPLE_NOTARY_KEY_ID '^[A-Z0-9]{10}$' 'an App Store Connect key identifier'
    require APPLE_NOTARY_ISSUER_ID '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' 'an issuer identifier'
    require APPLE_TEAM_ID '^[A-Z0-9]{10}$' 'a team identifier'
    require SPARKLE_ED_PRIVATE_KEY '^[A-Za-z0-9+/]{43}=$' 'the base64 of a 32-byte Ed25519 seed'
    require SPARKLE_ED_PUBLIC_KEY '^[A-Za-z0-9+/]{43}=$' 'the base64 of a 32-byte Ed25519 public key'
    require MARFA_MAC_DOWNLOADS_URL '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~-]+)*/$' 'an https folder address ending in a slash'
    require MARFA_MAC_POSTHOG_HOST '^https://[A-Za-z0-9.-]+$' 'an https host'
    require MARFA_MAC_POSTHOG_PROJECT_TOKEN '^phc_[A-Za-z0-9]+$' 'a project token'
    ;;
  publish)
    require R2_ACCESS_KEY_ID '^[A-Za-z0-9]+$' 'an access key identifier'
    require R2_SECRET_ACCESS_KEY '^[A-Za-z0-9]+$' 'a secret access key'
    require R2_S3_ENDPOINT '^https://[A-Za-z0-9.-]+$' 'an https host'
    require R2_BUCKET '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$' 'a bucket name'
    require MARFA_MAC_DOWNLOADS_URL '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~-]+)*/$' 'an https folder address ending in a slash'
    ;;
  *)
    echo "usage: check-secrets.sh build|publish" >&2
    exit 2
    ;;
esac

if [ ${#problems[@]} -gt 0 ]; then
  for problem in "${problems[@]}"; do
    echo "::error::$problem"
  done
  echo "::error::A tag run needs every value of the release environment, which is the only place that holds them."
  exit 1
fi
echo "Every value the $job job needs is set and shaped as expected."
