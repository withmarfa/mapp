#!/usr/bin/env bash
# Signs a disk image with the Developer ID Application identity, with a secure timestamp.
#
#   sign-disk-image.sh <Marfa-X.Y.Z.dmg>
#
# Reads APPLE_TEAM_ID and SIGNING_KEYCHAIN (signing-keychain.sh).
set -euo pipefail

dmg="${1:?disk image}"
: "${SIGNING_KEYCHAIN:?SIGNING_KEYCHAIN is not set}" "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"

codesign --force --timestamp --keychain "$SIGNING_KEYCHAIN" --sign "Developer ID Application" "$dmg"
codesign --verify --strict "$dmg"
codesign -dv "$dmg" 2>&1 | grep -qx "TeamIdentifier=$APPLE_TEAM_ID" || {
  echo "::error::$(basename "$dmg") is not signed by the release's team."
  exit 1
}
echo "Signed $(basename "$dmg")."
