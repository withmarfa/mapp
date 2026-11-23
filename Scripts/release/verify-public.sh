#!/usr/bin/env bash
# Fetches a published file from its public address and checks its length and SHA-256 against the local file.
#
#   verify-public.sh <public address> <local file>
set -euo pipefail

url="${1:?public address}" file="${2:?local file}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sha() { (shasum -a 256 "$1" 2>/dev/null || sha256sum "$1") | cut -d' ' -f1; }
# wc, not stat: GNU stat reads -f as "file system" and succeeds, so a fallback never runs on Linux.
size() { wc -c <"$1" | tr -d ' '; }

# A query keeps a cached copy of an earlier version from answering.
curl --silent --show-error --fail --location --retry 5 --retry-all-errors --retry-delay 3 \
  --output "$work/body" "$url?verify=$(sha "$file")"
if [ "$(size "$work/body")" != "$(size "$file")" ] || [ "$(sha "$work/body")" != "$(sha "$file")" ]; then
  echo "::error::$url does not serve the file that was uploaded: length $(size "$work/body") against $(size "$file")."
  exit 1
fi
echo "$url serves the uploaded file ($(size "$file") bytes)."
