#!/bin/bash
# Builds, signs, notarizes and packages MonitorX into dist/MonitorX-<version>.dmg (+ .zip).
#
# Usage:
#   VERSION=1.0.0 SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary Scripts/release.sh
#
# One-time notarytool setup (stores credentials in the keychain):
#   xcrun notarytool store-credentials notary --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Or notarize with an App Store Connect API key instead of a keychain profile (what CI does):
#   NOTARY_KEY_PATH=AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer uuid>
#
# When notarizing, the app is notarized and stapled first (so the copy inside the .dmg and the .zip carry their
# own ticket and pass Gatekeeper offline), then the .dmg is notarized and stapled. NOTARY_TIMEOUT (default 90m)
# caps each wait; Apple can take much longer than usual for a team's first submissions.
#
# Without SIGN_IDENTITY the script makes an ad-hoc signed, NOT notarized package (fine for friends:
# they must run `xattr -cr /Applications/MonitorX.app` once). Without notarization credentials it signs but skips
# notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-90m}"

NOTARY_AUTH=()
if [[ -n "$NOTARY_KEY_PATH" ]]; then
  NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID required}" --issuer "${NOTARY_ISSUER:?NOTARY_ISSUER required}")
elif [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi

APP="build/MonitorX.app"
DIST="dist"
DMG="$DIST/MonitorX-$VERSION.dmg"
ZIP="$DIST/MonitorX-$VERSION.zip"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

# Submits a file for notarization, waits, and fails (printing Apple's log) unless it was accepted.
notarize() {
  local file="$1" out status id
  out="$(xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --wait --timeout "$NOTARY_TIMEOUT" --output-format json)" || {
    echo "$out"
    echo "error: notarization of $file failed or did not finish within $NOTARY_TIMEOUT." >&2
    echo "       Apple keeps processing it; check with 'xcrun notarytool history' and re-run when it's accepted." >&2
    return 1
  }
  status="$(plutil -extract status raw - <<<"$out" 2>/dev/null || true)"
  id="$(plutil -extract id raw - <<<"$out" 2>/dev/null || true)"
  echo "notarization $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" || true
    echo "error: notarization of $file was not accepted ($status)" >&2
    return 1
  fi
}

NOTARIZE=0
if [[ -n "$SIGN_IDENTITY" && ${#NOTARY_AUTH[@]} -gt 0 ]]; then NOTARIZE=1; fi

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

if [[ $NOTARIZE == 1 ]]; then
  step "Notarizing the app (usually a few minutes)"
  APP_ZIP="$(mktemp -d)/MonitorX.zip"
  ditto -c -k --keepParent "$APP" "$APP_ZIP"
  notarize "$APP_ZIP"
  rm -f "$APP_ZIP"
  xcrun stapler staple "$APP"
elif [[ -n "$SIGN_IDENTITY" ]]; then
  step "No notarization credentials: skipping notarization (users will still see a Gatekeeper warning)"
fi

step "Creating $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MonitorX" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "${STAGE:?}"
if [[ -n "$SIGN_IDENTITY" ]]; then codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"; fi

if [[ $NOTARIZE == 1 ]]; then
  step "Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  step "Gatekeeper"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

step "Creating $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Done"
ls -lh "$DIST"
shasum -a 256 "$DMG" "$ZIP"
