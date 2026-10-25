#!/bin/zsh
# Xcode Cloud runs this after it clones the repository. The repository carries no signing team and no version:
# the workflow supplies the team as the secret MAPP_DEVELOPMENT_TEAM, and the version is the tag that
# started the build. Nothing written here is committed.
set -euo pipefail
cd "${0:a:h}/.."

if [[ -n "${MAPP_DEVELOPMENT_TEAM:-}" ]]; then
  [[ "$MAPP_DEVELOPMENT_TEAM" =~ '^[A-Z0-9]{10}$' ]] || {
    print -u2 -- 'MAPP_DEVELOPMENT_TEAM is not a team identifier.'
    exit 1
  }
  print -- "DEVELOPMENT_TEAM = $MAPP_DEVELOPMENT_TEAM" > Config/Local.xcconfig
fi

if [[ -n "${CI_TAG:-}" ]]; then
  # A release is signed with the team; without it the archive would fail late or ship unsigned.
  [[ -n "${MAPP_DEVELOPMENT_TEAM:-}" ]] || {
    print -u2 -- 'MAPP_DEVELOPMENT_TEAM is not set, so the tag build cannot be signed.'
    exit 1
  }
  version="${CI_TAG#v}"
  [[ "$version" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || {
    print -u2 -- "The tag $CI_TAG is not a version such as 1.2.3."
    exit 1
  }
  # The version is a build setting of each target; it is set here, in this copy only.
  sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/" MAPP.xcodeproj/project.pbxproj
  # A project that no longer carries the setting would leave the build at 0.0.0.
  grep -q "MARKETING_VERSION = $version;" MAPP.xcodeproj/project.pbxproj || {
    print -u2 -- "MARKETING_VERSION was not set to $version."
    exit 1
  }
fi
