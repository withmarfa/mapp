#!/bin/zsh
# Xcode Cloud runs this after it clones the repository. The repository carries no signing team, no report
# destination and no version. The workflow may supply the team as the secret MAPP_DEVELOPMENT_TEAM (Xcode Cloud
# signs with its own managed signing when it does not), and the destination, where the build sends its errors and
# timings, as the secrets MAPP_POSTHOG_HOST and MAPP_POSTHOG_PROJECT_TOKEN (the build sends nothing without both).
# The version is the tag that started the build. Nothing written here is committed.
set -euo pipefail
cd "${0:a:h}/.."

local_config=()

if [[ -n "${MAPP_DEVELOPMENT_TEAM:-}" ]]; then
  [[ "$MAPP_DEVELOPMENT_TEAM" =~ '^[A-Z0-9]{10}$' ]] || {
    print -u2 -- 'MAPP_DEVELOPMENT_TEAM is not a team identifier.'
    exit 1
  }
  local_config+=("DEVELOPMENT_TEAM = $MAPP_DEVELOPMENT_TEAM")
fi

if [[ -n "${MAPP_POSTHOG_HOST:-}" || -n "${MAPP_POSTHOG_PROJECT_TOKEN:-}" ]]; then
  [[ "${MAPP_POSTHOG_HOST:-}" =~ '^https://[A-Za-z0-9.-]+$' ]] || {
    print -u2 -- 'MAPP_POSTHOG_HOST is not an https host.'
    exit 1
  }
  [[ "${MAPP_POSTHOG_PROJECT_TOKEN:-}" =~ '^phc_[A-Za-z0-9]+$' ]] || {
    print -u2 -- 'MAPP_POSTHOG_PROJECT_TOKEN is not a project token.'
    exit 1
  }
  # An xcconfig reads // as a comment, so the scheme's slashes are written around an empty expansion.
  local_config+=("MARFA_POSTHOG_HOST = https:/\$()/${MAPP_POSTHOG_HOST#https://}")
  local_config+=("MARFA_POSTHOG_PROJECT_TOKEN = $MAPP_POSTHOG_PROJECT_TOKEN")
fi

if (( ${#local_config} )); then
  print -l -- "${local_config[@]}" > Config/Local.xcconfig
fi

if [[ -n "${CI_TAG:-}" ]]; then
  # A release candidate, such as v0.0.25-rc1, builds the version it is a candidate for.
  [[ "$CI_TAG" =~ '^v[0-9]+(\.[0-9]+){0,2}(-rc[0-9]+)?$' ]] || {
    print -u2 -- "The tag $CI_TAG is not a version such as v1.2.3 or a candidate such as v1.2.3-rc1."
    exit 1
  }
  version="${${CI_TAG#v}%%-rc*}"
  [[ "$version" =~ '^0+(\.0+){0,2}$' ]] && {
    print -u2 -- "The tag $CI_TAG would build version 0.0.0."
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
