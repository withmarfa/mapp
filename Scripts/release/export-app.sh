#!/usr/bin/env bash
# Exports an archive as a Developer ID app: re-signed with the identity, with no provisioning profile (the app claims no
# entitlement that needs one).
#
#   export-app.sh <archive path> <export folder>
#
# Reads APPLE_TEAM_ID. The identity is in the keychain on the search list (signing-keychain.sh).
set -euo pipefail

archive="${1:?archive path}" export_dir="${2:?export folder}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"

options="$(mktemp -d)/ExportOptions.plist"
cat >"$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST
trap 'rm -rf "$(dirname "$options")"' EXIT

xcodebuild -exportArchive -quiet -archivePath "$archive" -exportPath "$export_dir" -exportOptionsPlist "$options"
test -d "$export_dir/Marfa.app"
