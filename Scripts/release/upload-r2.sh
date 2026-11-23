#!/usr/bin/env bash
# Puts a file in the downloads bucket through R2's S3 API, signed with curl's own AWS Signature V4. Never Cloudflare's
# REST object endpoints, which a bucket-scoped token is refused.
#
#   upload-r2.sh <file> <object name> <content type> <cache control>
#
# The object lands at <bucket>/marfa-mac/<object name>. Reads R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_S3_ENDPOINT and
# R2_BUCKET. The credentials go to curl on standard input, never on its command line.
set -euo pipefail

file="${1:?file}" name="${2:?object name}" type="${3:?content type}" cache="${4:?cache control}"
: "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}" "${R2_S3_ENDPOINT:?}" "${R2_BUCKET:?}"

hash=$( (shasum -a 256 "$file" 2>/dev/null || sha256sum "$file") | cut -d' ' -f1)
curl --silent --show-error --fail-with-body --retry 3 --retry-all-errors \
  --aws-sigv4 "aws:amz:auto:s3" --config - \
  --header "x-amz-content-sha256: $hash" \
  --header "Content-Type: $type" \
  --header "Cache-Control: $cache" \
  --upload-file "$file" \
  "${R2_S3_ENDPOINT%/}/$R2_BUCKET/marfa-mac/$name" <<CONFIG
user = "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY"
CONFIG
echo "Uploaded $name."
