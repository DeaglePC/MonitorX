#!/bin/bash
# Builds MonitorX.app.
#
#   Scripts/build.sh                     direct-distribution edition  -> build/MonitorX.app
#   EDITION=appstore Scripts/build.sh    sandboxed App Store edition  -> build/appstore/MonitorX.app
#
# The App Store edition is compiled with -DAPPSTORE (process details, sensors and the helper-tool based
# hardware lookups are compiled out) and ad-hoc signed *with the sandbox entitlement* so it can be run and
# tested locally under the same restrictions the App Store enforces. Use Scripts/release_appstore.sh to ship it.
#
# Optional env: VERSION, BUILD_NUMBER, BUNDLE_ID.
set -euo pipefail
cd "$(dirname "$0")/.."

EDITION="${EDITION:-direct}"
BUNDLE_ID="${BUNDLE_ID:-com.monitorx.app}"
case "$EDITION" in
  direct)   APP="build/MonitorX.app";          SCRATCH=".build";          FLAGS=() ;;
  appstore) APP="build/appstore/MonitorX.app"; SCRATCH=".build-appstore"; FLAGS=(-Xswiftc -DAPPSTORE) ;;
  *) echo "Unknown EDITION '$EDITION' (use direct or appstore)" >&2; exit 1 ;;
esac

rm -rf "${APP:?}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

build() { swift build -c release --scratch-path "$SCRATCH" ${FLAGS[@]+"${FLAGS[@]}"} "$@"; }

# Universal binary (built per-arch then lipo'd, so it works with just the Command Line Tools);
# falls back to the native architecture if cross-compiling isn't possible.
if build --triple arm64-apple-macosx26.0 >/dev/null 2>&1 \
   && build --triple x86_64-apple-macosx26.0 >/dev/null 2>&1; then
  UNIVERSAL="$(dirname "$APP")/MonitorX.universal"
  lipo -create \
    "$(build --triple arm64-apple-macosx26.0 --show-bin-path)/MonitorX" \
    "$(build --triple x86_64-apple-macosx26.0 --show-bin-path)/MonitorX" \
    -output "$UNIVERSAL"
  BIN="$UNIVERSAL"
else
  build
  BIN="$(build --show-bin-path)/MonitorX"
fi
cp "$BIN" "$APP/Contents/MacOS/MonitorX"
cp -R Resources/BrandIcons "$APP/Contents/Resources/"
rm -f "$(dirname "$APP")/MonitorX.universal"

# Icon
ICONSET="$(mktemp -d)/AppIcon.iconset"
swiftc -O Scripts/make_icon.swift -o "$(dirname "$ICONSET")/make_icon" 2>/dev/null
"$(dirname "$ICONSET")/make_icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Localizations (Resources/Localization/<lang>.lproj -> Contents/Resources/<lang>.lproj)
LOCALIZATIONS=""
for LPROJ in Resources/Localization/*.lproj; do
  cp -R "$LPROJ" "$APP/Contents/Resources/"
  LOCALIZATIONS+="    <string>$(basename "$LPROJ" .lproj)</string>"$'\n'
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MonitorX</string>
  <key>CFBundleDisplayName</key><string>MonitorX</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>MonitorX</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
${LOCALIZATIONS}  </array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
PLIST

if [[ "$EDITION" == "appstore" ]]; then
  codesign --force --sign - --entitlements Resources/AppStore.entitlements "$APP" >/dev/null
else
  codesign --force --deep --sign - "$APP" >/dev/null
fi
echo "Built $APP [$EDITION] ($(lipo -archs "$APP/Contents/MacOS/MonitorX"))"
