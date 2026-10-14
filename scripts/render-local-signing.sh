#!/bin/zsh
# Writes the ignored Config/Local.xcconfig from Infisical. Run it through `infisical run --`.
set -euo pipefail
cd "${0:a:h}/.."

team="${APPLE_DEVELOPMENT_TEAM:-}"
[[ "$team" =~ '^[A-Z0-9]{10}$' ]] || {
  print -u2 -- 'APPLE_DEVELOPMENT_TEAM is missing or invalid; run this script through `infisical run --`.'
  exit 1
}

umask 077
temp=$(mktemp Config/Local.xcconfig.XXXXXX)
trap '/bin/rm -f "$temp"' EXIT
print -- "DEVELOPMENT_TEAM = $team" > "$temp"
mv "$temp" Config/Local.xcconfig
print -- 'Rendered Config/Local.xcconfig from Infisical.'
