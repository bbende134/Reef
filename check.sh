#!/bin/bash
#
# Runs Reef's model-layer assertions without Xcode.
# See Checks/main.swift for why this exists instead of `swift test`.
#
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --show-sdk-path)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -sdk "$SDK" -target arm64-apple-macos14.6 -swift-version 5 \
  Reef/Models/WindowLayout.swift \
  Reef/Models/AlignmentCommand.swift \
  Reef/Models/WindowFrameHistory.swift \
  Reef/Models/ScreenGeometry.swift \
  Reef/UI/CyclePanel/AlignmentKeyMap.swift \
  Checks/main.swift \
  -o "$OUT/checks"

"$OUT/checks"
