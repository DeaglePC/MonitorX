#!/bin/bash
# Production SwiftUI quota cards with clearly labeled in-memory demo data.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SOURCES=()
while IFS= read -r source; do
  SOURCES+=("$source")
done < <(rg --files Sources/MonitorX -g '*.swift' | rg -v '/main.swift$' | sort)
swiftc -swift-version 5 "${SOURCES[@]}" \
  "$BIN/MonitorX.build/DerivedSources/resource_bundle_accessor.swift" \
  Scripts/UsageScreenshots.swift -o "$WORK/render"
"$WORK/render"
