#!/bin/bash
# Check runtime language switching using only Command Line Tools (no XCTest / Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
swiftc -swift-version 5 Sources/MonitorX/App/Localization.swift \
  "$BIN/MonitorX.build/DerivedSources/resource_bundle_accessor.swift" \
  Scripts/LanguageSwitchCheck.swift -o "$CHECK/check"
"$CHECK/check"

# Exercise the packaged .app resource layout as well as SwiftPM's resource bundle.
mkdir -p "$CHECK/Check.app/Contents/MacOS" "$CHECK/Check.app/Contents/Resources"
cp "$CHECK/check" "$CHECK/Check.app/Contents/MacOS/check"
cp -R Resources/Localization/*.lproj "$CHECK/Check.app/Contents/Resources/"
"$CHECK/Check.app/Contents/MacOS/check"
