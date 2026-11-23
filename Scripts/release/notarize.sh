#!/usr/bin/env bash
# Sends an app or a disk image to Apple's notary service, waits, staples the ticket and checks it.
#
#   notarize.sh <Marfa.app | Marfa-X.Y.Z.dmg>
#
# Reads APPLE_NOTARY_KEY, APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID. On a refusal it prints the notary log.
set -euo pipefail

target="${1:?app or disk image}"
: "${APPLE_NOTARY_KEY:?APPLE_NOTARY_KEY is not set}" "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is not set}"
: "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is not set}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(
  umask 077
  printf '%s\n' "$APPLE_NOTARY_KEY" >"$work/notary.p8"
)
notary=(--key "$work/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")

# The service takes a disk image as it is, and an app as a ZIP of it.
submission="$target"
if [ -d "$target" ]; then
  submission="$work/submission.zip"
  ditto -c -k --keepParent "$target" "$submission"
fi

xcrun notarytool submit "$submission" "${notary[@]}" --wait --timeout 30m --output-format json >"$work/result.json"
status=$(plutil -extract status raw -o - "$work/result.json")
id=$(plutil -extract id raw -o - "$work/result.json")
if [ "$status" != "Accepted" ]; then
  echo "::error::Apple did not notarize $(basename "$target"): $status (submission $id)."
  xcrun notarytool log "$id" "${notary[@]}" || true
  exit 1
fi

xcrun stapler staple "$target"
xcrun stapler validate "$target"
echo "$(basename "$target") is notarized and stapled (submission $id)."
