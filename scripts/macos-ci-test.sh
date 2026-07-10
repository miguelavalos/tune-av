#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.derived-data/macos-ci"
RESULT_BUNDLE_PATH="$DERIVED_DATA_PATH/TestResults/TuneAVMac.xcresult"

rm -rf "$RESULT_BUNDLE_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

cd "$ROOT_DIR/apps/macos"

node "$ROOT_DIR/scripts/check-macos-privacy-manifest.mjs"

xcodebuild test \
  -project TuneAVMac.xcodeproj \
  -scheme TuneAVMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO
