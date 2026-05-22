#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
DERIVED_DATA_PATH="${TUNEAV_IOS_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-ci}"
RESULT_BUNDLE_PATH="${TUNEAV_IOS_RESULT_BUNDLE_PATH:-$ROOT_DIR/.derived-data/ios-ci/TestResults/TuneAV.xcresult}"
SIZE_REPORT_PATH="${TUNEAV_IOS_SIZE_REPORT_PATH:-$ROOT_DIR/.derived-data/ios-ci/Reports/app-size.md}"
LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH="${TUNEAV_IOS_LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH:-$(dirname "$RESULT_BUNDLE_PATH")/LaunchPerformance.xcresult}"

rm -rf "$RESULT_BUNDLE_PATH" "$LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH"
rm -f "$SIZE_REPORT_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")" "$(dirname "$LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH")" "$(dirname "$SIZE_REPORT_PATH")"

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

cd "$IOS_DIR"
xcodebuild test \
  -project TuneAV.xcodeproj \
  -scheme TuneAV \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -only-testing:TuneAVTests \
  CODE_SIGNING_ALLOWED=NO

TUNEAV_IOS_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/TuneAV.app" \
TUNEAV_IOS_SIZE_REPORT_PATH="$SIZE_REPORT_PATH" \
  "$ROOT_DIR/scripts/report-ios-app-size.sh"

if [[ "${TUNEAV_IOS_SKIP_LAUNCH_PERF_SMOKE:-0}" != "1" ]]; then
  TUNEAV_IOS_SMOKE_DEVICE_ID="$device_id" \
  TUNEAV_IOS_LAUNCH_PERFORMANCE_DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
  TUNEAV_IOS_LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH="$LAUNCH_PERFORMANCE_RESULT_BUNDLE_PATH" \
  TUNEAV_IOS_MAX_LAUNCH_READY_MS="${TUNEAV_IOS_MAX_LAUNCH_READY_MS:-}" \
    "$ROOT_DIR/scripts/smoke-ios-launch-performance.sh"
fi
