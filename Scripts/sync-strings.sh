#!/bin/zsh
# Fills MarfaMac/Localizable.xcstrings from the strings a build found in the code, as building in Xcode does, without
# Xcode's window. Build the MarfaMac scheme with xcodebuild first (the project emits the strings), then pass the same
# derived data folder:
#
#   Scripts/sync-strings.sh <derived data folder>
set -euo pipefail

derived=${1:?Pass the derived data folder of a MarfaMac build.}
root=${0:A:h:h}
strings=("$derived"/Build/Intermediates.noindex/MarfaMac.build/*/MarfaMac.build/Objects-normal/*/*.stringsdata(N))
(( ${#strings} )) || { print -u2 "No .stringsdata under $derived: build the MarfaMac scheme into it first."; exit 1; }

args=()
for file in $strings; do args+=(--stringsdata "$file"); done
xcrun xcstringstool sync "$root/MarfaMac/Localizable.xcstrings" $args
print "Synced the String Catalog from ${#strings} files."
