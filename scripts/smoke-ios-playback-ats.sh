#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT_PATH="$IOS_DIR/TuneAV.xcodeproj"
SCHEME="TuneAV"
DERIVED_DATA_PATH="${TUNEAV_IOS_PLAYBACK_ATS_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-playback-ats-smoke}"
RESULT_BUNDLE_PATH="${TUNEAV_IOS_PLAYBACK_ATS_RESULT_BUNDLE_PATH:-$DERIVED_DATA_PATH/TestResults/PlaybackATS.xcresult}"
TEST_ID="${TUNEAV_IOS_PLAYBACK_ATS_TEST_ID:-TuneAVUITests/PlayerQueueUITests/testFavoriteQueueAdvancesFromLibraryContext}"

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
  echo "No available iPhone simulator found for playback ATS smoke." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

cd "$IOS_DIR"
xcodegen generate >/dev/null
rm -rf "$RESULT_BUNDLE_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

echo "==> Running playback ATS UI smoke on simulator $device_id"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -only-testing:"$TEST_ID" \
  test \
  CODE_SIGNING_ALLOWED=NO

built_info_plist="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/TuneAV.app/Info.plist"
if [ ! -f "$built_info_plist" ]; then
  echo "Built TuneAV.app Info.plist not found: $built_info_plist" >&2
  exit 1
fi

node - "$built_info_plist" <<'NODE'
const { execFileSync } = require("node:child_process");
const infoPath = process.argv[2];
const info = JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", infoPath], { encoding: "utf8" }));
const ats = info.NSAppTransportSecurity || {};

if (ats.NSAllowsArbitraryLoads === true) {
  console.error("FAIL built app enables NSAllowsArbitraryLoads.");
  process.exit(1);
}
if (ats.NSAllowsArbitraryLoadsForMedia !== true) {
  console.error("FAIL built app does not keep NSAllowsArbitraryLoadsForMedia enabled.");
  process.exit(1);
}

console.log("Built app ATS settings verified.");
NODE

echo "iOS playback ATS smoke passed."
