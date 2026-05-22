#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT_PATH="$IOS_DIR/TuneAV.xcodeproj"
SCHEME="TuneAV"
DERIVED_DATA_PATH="${TUNEAV_IOS_LAUNCH_PERFORMANCE_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-launch-performance-smoke}"
RESULT_BUNDLE_PATH="${TUNEAV_IOS_LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH:-$DERIVED_DATA_PATH/TestResults/LaunchPerformance.xcresult}"
TEST_ID="${TUNEAV_IOS_LAUNCH_PERFORMANCE_TEST_ID:-TuneAVUITests/LaunchPerformanceUITests/testLaunchReachesHomeWithinBudget}"
MAX_LAUNCH_READY_MS="${TUNEAV_IOS_MAX_LAUNCH_READY_MS:-10000}"

device_id="${TUNEAV_IOS_SMOKE_DEVICE_ID:-}"
if [ -z "$device_id" ]; then
  device_id="$(xcrun simctl list devices available | awk '
    /Booted/ && /iPhone/ {
      if (match($0, /\([0-9A-F-]{36}\)/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ')"
fi

if [ -z "$device_id" ]; then
  device_id="$(xcrun simctl list devices available | awk '
    /iPhone 16 \(/ {
      if (match($0, /\([0-9A-F-]{36}\)/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ')"
fi

if [ -z "$device_id" ]; then
  echo "No available iPhone simulator found for launch performance smoke." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

cd "$IOS_DIR"
xcodegen generate >/dev/null
rm -rf "$RESULT_BUNDLE_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

echo "==> Running launch performance UI smoke on simulator $device_id"
echo "==> Launch ready budget: ${MAX_LAUNCH_READY_MS}ms"
TUNEAV_UI_TEST_MAX_LAUNCH_READY_MS="$MAX_LAUNCH_READY_MS" \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -only-testing:"$TEST_ID" \
  test \
  TUNEAV_UI_TEST_MAX_LAUNCH_READY_MS="$MAX_LAUNCH_READY_MS" \
  CODE_SIGNING_ALLOWED=NO

echo "iOS launch performance smoke passed."
