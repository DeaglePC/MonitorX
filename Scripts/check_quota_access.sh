#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN="$(swift build --show-bin-path)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
SOURCES=(Sources/MonitorX/App/Localization.swift Sources/MonitorX/App/Edition.swift
  Sources/MonitorX/Sampling/CodexUsage.swift Sources/MonitorX/Sampling/CodexOAuthUsage.swift
  Sources/MonitorX/Sampling/ClaudeOAuthUsage.swift Sources/MonitorX/Sampling/ClaudeUsage.swift Sources/MonitorX/Sampling/ClaudeCodeSetup.swift
  Sources/MonitorX/Sampling/QuotaSnapshotFile.swift
  "$BIN/MonitorX.build/DerivedSources/resource_bundle_accessor.swift" Scripts/QuotaAccessCheck.swift)
swiftc -swift-version 5 "${SOURCES[@]}" -o "$CHECK/direct"
"$CHECK/direct" "$@"
swiftc -swift-version 5 -DAPPSTORE "${SOURCES[@]}" -o "$CHECK/appstore"
"$CHECK/appstore"
