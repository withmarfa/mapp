#!/usr/bin/env bash
# Makes the disk image: Marfa.app beside a link to Applications, on APFS with lzfse compression as Sparkle recommends.
#
#   make-dmg.sh <Marfa.app> <output .dmg>
set -euo pipefail

app="${1:?app}" dmg="${2:?output disk image}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/Marfa"
# ditto keeps the app's signature, extended attributes and stapled ticket as they are.
ditto "$app" "$work/Marfa/Marfa.app"
ln -s /Applications "$work/Marfa/Applications"
rm -f "$dmg"
hdiutil create -volname Marfa -srcfolder "$work/Marfa" -fs APFS -format ULFO -ov "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
echo "Made $(basename "$dmg")."
