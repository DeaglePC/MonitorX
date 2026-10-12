#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
SOURCES=()
while IFS= read -r source; do
  SOURCES+=("$source")
done < <(find Sources/MonitorX -name '*.swift' ! -name main.swift | sort)
swiftc -swift-version 5 "${SOURCES[@]}" \
  "$BIN/MonitorX.build/DerivedSources/resource_bundle_accessor.swift" \
  Scripts/TextSharingCheck.swift -o "$CHECK/check"
"$CHECK/check"
