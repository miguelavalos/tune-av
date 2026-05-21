#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT_PATH="$IOS_DIR/TuneAV.xcodeproj"
SCHEME="TuneAV"
DERIVED_DATA_PATH="${TUNEAV_IOS_UI_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-ui-smoke}"
RESULT_BUNDLE_DIR="${TUNEAV_IOS_UI_RESULT_BUNDLE_DIR:-$ROOT_DIR/.derived-data/ios-ui-smoke/TestResults}"

simulator_name="${TUNEAV_IOS_SIMULATOR_NAME:-iPhone 16}"
device_id="$(xcrun simctl list devices available | awk -v simulator_name="$simulator_name" '
  index($0, simulator_name " (") {
    if (match($0, /\([0-9A-F-]{36}\)/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  }
')"

if [[ -z "$device_id" ]]; then
  device_id="$(xcrun simctl list devices available | awk '
    /iPhone/ {
      if (match($0, /\([0-9A-F-]{36}\)/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ')"
fi

if [[ -z "$device_id" ]]; then
  echo "No available iPhone simulator found." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

TESTS=(
  "TuneAVUITests/HomeUITests"
  "TuneAVUITests/PlayerQueueUITests"
  "TuneAVUITests/SearchQueueUITests/testSeededSearchQueryOpensResults"
  "TuneAVUITests/ZHomeEmptyStateUITests"
  "TuneAVUITests/HomeRefreshUITests"
)

cd "$IOS_DIR"
xcodegen generate >/dev/null
rm -rf "$RESULT_BUNDLE_DIR"
mkdir -p "$RESULT_BUNDLE_DIR"

for test_id in "${TESTS[@]}"; do
  result_name="${test_id//\//-}"
  echo
  echo "==> Running $test_id"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE_DIR/$result_name.xcresult" \
    -only-testing:"$test_id" \
    test \
    CODE_SIGNING_ALLOWED=NO
done

echo
echo "All sequential UI tests passed."
