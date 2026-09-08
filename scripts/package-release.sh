#!/bin/zsh
# SPDX-License-Identifier: BUSL-1.1
# Package an already verified app. Credentials are supplied externally, never stored here.
set -euo pipefail
cd "${0:A:h:h}"
: "${APP_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set the saved notarisation profile name}"
APP="${1:?Usage: package-release.sh VERIFIED_APP NEW_OUTPUT_DIRECTORY}"
APP="${APP:a}"
DEST="${2:?Choose a new output directory}"
DEST="${DEST:a}"
[[ ! -e "$DEST" ]] || { print -u2 'Output directory already exists'; exit 1; }
[[ -d "$APP" ]] || exit 1
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || exit 1
RELEASE_VERSION="$(plutil -extract StudioUpkeepReleaseVersion raw -o - "$APP/Contents/Info.plist" 2>/dev/null || print "$VERSION")"
[[ "$RELEASE_VERSION" == "$VERSION" || "$RELEASE_VERSION" =~ "^${VERSION//./\.}-(beta|rc)\.[0-9]+$" ]] || { print -u2 'Release version does not match app version'; exit 1; }
mkdir -p "$DEST"
STAGE="$(mktemp -d /tmp/mk-upkeep-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
export COPYFILE_DISABLE=1
ditto --norsrc --noextattr "$APP" "$STAGE/MK Studio Upkeep.app"
codesign --force --timestamp --options runtime --entitlements Resources/StudioUpkeep.entitlements \
  --sign "$APP_SIGNING_IDENTITY" "$STAGE/MK Studio Upkeep.app"
codesign --verify --deep --strict "$STAGE/MK Studio Upkeep.app"
python3 scripts/audit-artifact.py "$STAGE/MK Studio Upkeep.app"
# Submit the app separately so it carries its own ticket after copying out of the image.
ditto -c -k --keepParent "$STAGE/MK Studio Upkeep.app" "$DEST/notarisation-app.zip"
xcrun notarytool submit "$DEST/notarisation-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$DEST/app-notarisation.json"
python3 - "$DEST/app-notarisation.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['status']=='Accepted', 'App notarisation not accepted'
PY
xcrun stapler staple "$STAGE/MK Studio Upkeep.app"
xcrun stapler validate "$STAGE/MK Studio Upkeep.app"
spctl --assess --type execute --verbose=2 "$STAGE/MK Studio Upkeep.app"
cp docs/INSTALLATION.md "$STAGE/INSTALLATION.txt"
ln -s /Applications "$STAGE/Applications"
DMG="$DEST/MK-Studio-Upkeep-$RELEASE_VERSION-macOS.dmg"
hdiutil create -volname 'MK Studio Upkeep' -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --timestamp --sign "$APP_SIGNING_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$DEST/dmg-notarisation.json"
python3 - "$DEST/dmg-notarisation.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['status']=='Accepted', 'Disk image notarisation not accepted'
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$DEST" && shasum -a 256 "${DMG:t}" > SHA256SUMS.txt)
print 'Signed and stapled disk image created. Upload only the image and SHA256SUMS.txt; notarisation records remain local.'
