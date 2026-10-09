#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
swiftc -swift-version 5 Sources/MonitorX/App/Localization.swift Sources/MonitorX/Sampling/CodexUsage.swift \
  "$BIN/MonitorX.build/DerivedSources/resource_bundle_accessor.swift" Scripts/CodexUsageCheck.swift -o "$CHECK/check"
"$CHECK/check" "$@"
