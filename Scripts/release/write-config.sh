#!/usr/bin/env bash
# Writes Config/Local.xcconfig, the ignored file that carries what the repository does not: the team, where the build
# reports to, and where it looks for updates. Each value is checked for its shape first; none is printed.
#
#   write-config.sh [file]
#
# Reads MARFA_MAC_DOWNLOADS_URL and SPARKLE_ED_PUBLIC_KEY, which a build needs, and optionally APPLE_TEAM_ID,
# MARFA_MAC_POSTHOG_HOST and MARFA_MAC_POSTHOG_PROJECT_TOKEN (both of the last two, or neither).
set -euo pipefail

file="${1:-$(cd "$(dirname "$0")/../.." && pwd)/Config/Local.xcconfig}"
lines=()

fail() {
  echo "::error::$1" >&2
  exit 1
}

if [ -n "${APPLE_TEAM_ID:-}" ]; then
  [[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "APPLE_TEAM_ID is not a team identifier."
  lines+=("DEVELOPMENT_TEAM = $APPLE_TEAM_ID")
fi

if [ -n "${MARFA_MAC_POSTHOG_HOST:-}" ] || [ -n "${MARFA_MAC_POSTHOG_PROJECT_TOKEN:-}" ]; then
  [[ "${MARFA_MAC_POSTHOG_HOST:-}" =~ ^https://[A-Za-z0-9.-]+$ ]] || fail "MARFA_MAC_POSTHOG_HOST is not an https host."
  [[ "${MARFA_MAC_POSTHOG_PROJECT_TOKEN:-}" =~ ^phc_[A-Za-z0-9]+$ ]] || fail "MARFA_MAC_POSTHOG_PROJECT_TOKEN is not a project token."
  # An xcconfig reads // as a comment, so the scheme's slashes are written around an empty expansion.
  lines+=("MARFA_MAC_POSTHOG_HOST = https:/\$()/${MARFA_MAC_POSTHOG_HOST#https://}")
  lines+=("MARFA_MAC_POSTHOG_PROJECT_TOKEN = $MARFA_MAC_POSTHOG_PROJECT_TOKEN")
fi

[[ "${MARFA_MAC_DOWNLOADS_URL:-}" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~-]+)*/$ ]] \
  || fail "MARFA_MAC_DOWNLOADS_URL is not an https folder address ending in a slash."
[[ "${SPARKLE_ED_PUBLIC_KEY:-}" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
  || fail "SPARKLE_ED_PUBLIC_KEY is not the base64 of a 32-byte Ed25519 public key."
lines+=("MARFA_MAC_UPDATE_FEED_URL = https:/\$()/${MARFA_MAC_DOWNLOADS_URL#https://}appcast.xml")
lines+=("MARFA_MAC_UPDATE_PUBLIC_KEY = $SPARKLE_ED_PUBLIC_KEY")

(
  umask 077
  printf '%s\n' "${lines[@]}" >"$file"
)
echo "Wrote ${#lines[@]} settings to $(basename "$file")."
