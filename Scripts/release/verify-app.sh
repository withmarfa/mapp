#!/usr/bin/env bash
# Holds an exported app to what a release promises, before anything leaves the runner. Only verifies; signs nothing.
#
#   verify-app.sh <Marfa.app> <version> <build> signed|adhoc
#
# `signed` also holds the app to the team in APPLE_TEAM_ID and to the feed address MARFA_MAC_DOWNLOADS_URL names.
set -euo pipefail

app="${1:?app}" version="${2:?version}" build="${3:?build}" mode="${4:?signed|adhoc}"
bundle_id="com.withmarfa.marfa"
plist="$app/Contents/Info.plist"
failures=()

fail() { failures+=("$1"); }

read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

expect() {
  local key="$1" want="$2" got
  got=$(read_key "$key")
  [ "$got" = "$want" ] || fail "$key is \"$got\", not \"$want\"."
}

expect CFBundleIdentifier "$bundle_id"
expect CFBundleShortVersionString "$version"
expect CFBundleVersion "$build"
expect SUVerifyUpdateBeforeExtraction "true"
expect SUEnableAutomaticChecks "true"
[ -n "$(read_key SUPublicEDKey)" ] || fail "SUPublicEDKey is empty."
feed=$(read_key SUFeedURL)
[ -n "$feed" ] || fail "SUFeedURL is empty."
if [ "$mode" = signed ]; then
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}" "${MARFA_MAC_DOWNLOADS_URL:?MARFA_MAC_DOWNLOADS_URL is not set}"
  [ "$feed" = "${MARFA_MAC_DOWNLOADS_URL}appcast.xml" ] || fail "SUFeedURL is not the release feed."
fi

# The signature is verified as it stands, never repaired; --deep here only widens the check to the nested code.
codesign --verify --strict --deep "$app" 2>&1 || fail "The code signature does not verify."
details=$(codesign -dvv "$app" 2>&1)
grep -q "flags=0x[0-9a-f]*(.*runtime.*)" <<<"$details" || fail "The hardened runtime is not on."
if [ "$mode" = signed ]; then
  grep -qx "TeamIdentifier=$APPLE_TEAM_ID" <<<"$details" || fail "The app is not signed by the release's team."
  grep -q "^Authority=Developer ID Application" <<<"$details" || fail "The app is not signed by a Developer ID Application identity."
  grep -q "^Timestamp=" <<<"$details" || fail "The signature has no secure timestamp."
fi

entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
grep -q "com.apple.security.get-task-allow" <<<"$entitlements" && fail "The app carries com.apple.security.get-task-allow."
grep -q "com.apple.security.app-sandbox" <<<"$entitlements" && fail "The app carries the App Sandbox entitlement."

if [ ${#failures[@]} -gt 0 ]; then
  for failure in "${failures[@]}"; do
    echo "::error::$failure"
  done
  exit 1
fi
echo "$(basename "$app") $version ($build) is as the release promises."
