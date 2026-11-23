#!/usr/bin/env bash
# Archives the Release configuration with the version and build number the tag gives, and nothing written into a tracked
# file.
#
#   archive.sh signed|adhoc <version> <build> <archive path> <derived data path> [xcodebuild arguments...]
#
# `signed` signs with the Developer ID Application identity of the team in the keychain that SIGNING_KEYCHAIN names, under
# the hardened runtime with a secure timestamp. `adhoc` signs ad hoc, for a dry run. The export that follows signs
# again; this signature keeps the archive itself valid.
set -euo pipefail

mode="${1:?mode}" version="${2:?version}" build="${3:?build}" archive="${4:?archive path}" derived="${5:?derived data path}"
shift 5
cd "$(dirname "$0")/../.."

signing=()
case "$mode" in
  signed)
    : "${SIGNING_KEYCHAIN:?SIGNING_KEYCHAIN is not set}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
    signing=(
      CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
      "OTHER_CODE_SIGN_FLAGS=--keychain $SIGNING_KEYCHAIN --timestamp" ENABLE_HARDENED_RUNTIME=YES
    )
    ;;
  adhoc)
    signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=YES)
    ;;
  *)
    echo "usage: archive.sh signed|adhoc <version> <build> <archive path> <derived data path> [xcodebuild arguments...]" >&2
    exit 2
    ;;
esac

xcodebuild archive -quiet \
  -project MarfaMac.xcodeproj -scheme MarfaMac -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$archive" -derivedDataPath "$derived" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  "${signing[@]}" ${@+"$@"}
test -d "$archive/Products/Applications/Marfa.app"
