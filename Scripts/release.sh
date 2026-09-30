#!/bin/bash
# Builds, signs, notarizes and packages MonitorX into dist/MonitorX-<version>.dmg (+ .zip).
#
# Usage:
#   VERSION=1.0.0 SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary Scripts/release.sh
#
# One-time notarytool setup (stores credentials in the keychain):
#   xcrun notarytool store-credentials notary --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Without SIGN_IDENTITY the script makes an ad-hoc signed, NOT notarized package (fine for friends:
# they must run `xattr -cr /Applications/MonitorX.app` once). Without NOTARY_PROFILE it signs but skips notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP="build/MonitorX.app"
DIST="dist"
DMG="$DIST/MonitorX-$VERSION.dmg"
ZIP="$DIST/MonitorX-$VERSION.zip"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

step "Building $VERSION ($BUILD_NUMBER)"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" Scripts/build.sh

mkdir -p "$DIST"
rm -f "${DMG:?}" "${ZIP:?}"

if [[ -n "$SIGN_IDENTITY" ]]; then
  step "Signing with: $SIGN_IDENTITY (hardened runtime)"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP"
else
  step "No SIGN_IDENTITY set: keeping the ad-hoc signature (not distributable without a warning)"
fi

step "Creating $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MonitorX" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "${STAGE:?}"
[[ -n "$SIGN_IDENTITY" ]] && codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  step "Notarizing (this usually takes 1-5 minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  step "Stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP" || true
elif [[ -n "$SIGN_IDENTITY" ]]; then
  step "NOTARY_PROFILE not set: skipping notarization (users will still see a Gatekeeper warning)"
fi

step "Creating $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Done"
ls -lh "$DIST"
shasum -a 256 "$DMG" "$ZIP"
