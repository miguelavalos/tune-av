#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
DERIVED_DATA_PATH="${TUNEAV_IOS_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-ci}"
RESULT_BUNDLE_PATH="${TUNEAV_IOS_RESULT_BUNDLE_PATH:-$ROOT_DIR/.derived-data/ios-ci/TestResults/TuneAV.xcresult}"

device_id="$(xcrun simctl list devices available | awk '
  /iPhone 16 \(/ {
    if (match($0, /\([0-9A-F-]{36}\)/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  }
')"

if [[ -z "$device_id" ]]; then
  echo "No available iPhone 16 simulator found." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

cd "$IOS_DIR"
rm -rf "$RESULT_BUNDLE_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
xcodebuild test \
  -project TuneAV.xcodeproj \
  -scheme TuneAV \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -only-testing:TuneAVTests \
  CODE_SIGNING_ALLOWED=NO
