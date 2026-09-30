#!/bin/bash
# Builds the sandboxed App Store edition and packages it as a signed .pkg for App Store Connect.
#
# Without signing identities it only builds build/appstore/MonitorX.app (ad-hoc signed WITH the sandbox
# entitlement) so you can run it locally and see exactly what the App Store version can do.
#
# One-time setup (developer.apple.com / appstoreconnect.apple.com):
#   1. Register a Bundle ID (e.g. com.yourname.monitorx) and create an app record with that Bundle ID.
#   2. Create two certificates and install them in your keychain:
#        "Apple Distribution" (or "3rd Party Mac Developer Application")   -> APP_IDENTITY
#        "Mac Installer Distribution" (or "3rd Party Mac Developer Installer") -> INSTALLER_IDENTITY
#   3. Create a "Mac App Store Connect" provisioning profile for the Bundle ID and download it -> PROVISION_PROFILE
#
# Usage:
#   BUNDLE_ID=com.yourname.monitorx TEAM_ID=ABCDE12345 VERSION=1.0.0 BUILD_NUMBER=1 \
#   APP_IDENTITY="Apple Distribution: Your Name (ABCDE12345)" \
#   INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (ABCDE12345)" \
#   PROVISION_PROFILE=~/Downloads/MonitorX.provisionprofile \
#   Scripts/release_appstore.sh
#
# Upload the resulting dist/MonitorX-<version>-appstore.pkg with the Transporter app, or set
# ASC_API_KEY / ASC_API_ISSUER (App Store Connect API key) and UPLOAD=1 to validate + upload with altool.
# BUILD_NUMBER must be higher than any build you uploaded before for the same VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
BUNDLE_ID="${BUNDLE_ID:-com.monitorx.app}"
APP="build/appstore/MonitorX.app"
PKG="dist/MonitorX-$VERSION-appstore.pkg"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

step "Building App Store edition $VERSION ($BUILD_NUMBER), bundle id $BUNDLE_ID"
EDITION=appstore VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" BUNDLE_ID="$BUNDLE_ID" Scripts/build.sh

if [[ -z "${APP_IDENTITY:-}" ]]; then
  cat <<MSG

No APP_IDENTITY set: built a LOCAL TEST copy only (sandboxed, ad-hoc signed, not uploadable).
  open $APP
Set BUNDLE_ID, TEAM_ID, APP_IDENTITY, INSTALLER_IDENTITY and PROVISION_PROFILE to produce the signed .pkg.
MSG
  exit 0
fi

for v in TEAM_ID INSTALLER_IDENTITY PROVISION_PROFILE; do
  [[ -n "${!v:-}" ]] || { echo "error: $v is required for a signed App Store package" >&2; exit 1; }
done
[[ "$BUNDLE_ID" != "com.monitorx.app" ]] || { echo "error: set BUNDLE_ID to the one registered for your Apple Developer account" >&2; exit 1; }
[[ -f "$PROVISION_PROFILE" ]] || { echo "error: PROVISION_PROFILE not found: $PROVISION_PROFILE" >&2; exit 1; }

step "Embedding provisioning profile"
cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"

step "Signing with: $APP_IDENTITY"
ENT="$(mktemp -d)/entitlements.plist"
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>${TEAM_ID}.${BUNDLE_ID}</string>
  <key>com.apple.developer.team-identifier</key><string>${TEAM_ID}</string>
</dict>
</plist>
PLIST
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

step "Creating $PKG"
mkdir -p dist
rm -f "${PKG:?}"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"

if [[ "${UPLOAD:-0}" == "1" ]]; then
  : "${ASC_API_KEY:?ASC_API_KEY required for UPLOAD=1}" "${ASC_API_ISSUER:?ASC_API_ISSUER required for UPLOAD=1}"
  step "Validating with App Store Connect"
  xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER"
  step "Uploading"
  xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER"
else
  echo "Upload $PKG with the Transporter app (or re-run with UPLOAD=1 and an App Store Connect API key)."
fi

step "Done"
ls -lh "$PKG"
