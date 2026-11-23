#!/usr/bin/env bash
# Holds the Developer ID identity in a temporary keychain for the length of a job.
#
#   signing-keychain.sh import   imports the identity, puts the keychain first on the search list, and appends
#                                SIGNING_KEYCHAIN=<path> to $GITHUB_ENV for the steps after
#   signing-keychain.sh remove   restores the search list and deletes the keychain
#
# `import` reads APPLE_DEVELOPER_ID_P12 and APPLE_DEVELOPER_ID_P12_PASSWORD. Both need RUNNER_TEMP.
set -euo pipefail

work="${RUNNER_TEMP:?RUNNER_TEMP is not set}/signing-keychain"
keychain="$work/signing.keychain-db"
saved="$work/search-list.txt"

case "${1:-}" in
  import)
    : "${APPLE_DEVELOPER_ID_P12:?APPLE_DEVELOPER_ID_P12 is not set}"
    : "${APPLE_DEVELOPER_ID_P12_PASSWORD:?APPLE_DEVELOPER_ID_P12_PASSWORD is not set}"
    mkdir -p "$work"
    chmod 700 "$work"
    # codesign finds an identity only in a keychain on the search list, so the list is kept to put back.
    security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g' >"$saved"
    (
      umask 077
      printf '%s' "$APPLE_DEVELOPER_ID_P12" | base64 --decode >"$work/identity.p12"
    )
    keychain_password=$(openssl rand -hex 24)
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 3600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$work/identity.p12" -k "$keychain" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
    rm -f "$work/identity.p12"
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
    existing=()
    while IFS= read -r line; do
      [ -n "$line" ] && existing+=("$line")
    done <"$saved"
    security list-keychains -d user -s "$keychain" ${existing[@]+"${existing[@]}"}
    if ! security find-identity -v -p codesigning "$keychain" | grep -q "Developer ID Application"; then
      echo "::error::The keychain holds no valid Developer ID Application identity:"
      security find-identity -p codesigning "$keychain" || true
      exit 1
    fi
    echo "SIGNING_KEYCHAIN=$keychain" >>"$GITHUB_ENV"
    echo "Imported the Developer ID Application identity into a temporary keychain."
    ;;
  remove)
    if [ -f "$saved" ]; then
      existing=()
      while IFS= read -r line; do
        [ -n "$line" ] && existing+=("$line")
      done <"$saved"
      security list-keychains -d user -s ${existing[@]+"${existing[@]}"} 2>/dev/null || true
    fi
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -rf "$work"
    ;;
  *)
    echo "usage: signing-keychain.sh import|remove" >&2
    exit 2
    ;;
esac
