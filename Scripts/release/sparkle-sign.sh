#!/usr/bin/env bash
# Signs an update archive for Sparkle and prints what the appcast needs.
#
#   sparkle-sign.sh <sign_update> <Marfa-X.Y.Z.dmg>   prints `signature=<EdDSA signature>` and `length=<bytes>`
#
# Reads SPARKLE_ED_PRIVATE_KEY, the base64 of the key's 32-byte seed. It goes to sign_update through a file only the
# runner's user can read, which is removed afterwards.
set -euo pipefail

sign_update="${1:?path to sign_update}" file="${2:?file to sign}"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is not set}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(
  umask 077
  printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" >"$work/key"
)
signature=$("$sign_update" --ed-key-file "$work/key" -p "$file")
"$sign_update" --verify --ed-key-file "$work/key" "$file" "$signature" >/dev/null
echo "signature=$signature"
echo "length=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file")"
