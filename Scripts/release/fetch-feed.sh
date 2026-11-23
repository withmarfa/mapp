#!/usr/bin/env bash
# Fetches the appcast as it is published. A 404 means there is no feed yet, so no file is written; any other answer
# that is not 200 stops the job, so a failed fetch is never taken for a new feed.
#
#   fetch-feed.sh <feed address> <output file>
set -euo pipefail

url="${1:?feed address}" out="${2:?output file}"
rm -f "$out"
status=$(curl -sS --retry 3 --retry-all-errors -o "$out" -w '%{http_code}' "$url?$(date +%s)")
case "$status" in
  200) echo "Fetched the published feed." ;;
  404)
    rm -f "$out"
    echo "There is no published feed yet, so this one starts it."
    ;;
  *)
    rm -f "$out"
    echo "::error::The published feed answered $status."
    exit 1
    ;;
esac
