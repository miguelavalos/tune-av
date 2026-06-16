#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT_PATH="$IOS_DIR/TuneAV.xcodeproj"
SCHEME="TuneAV"
DERIVED_DATA_PATH="${TUNEAV_IOS_RELEASE_SIM_DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data/ios-release-simulator}"

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
xcodegen generate >/dev/null

echo "==> Building Tune AV Release for simulator $device_id"
echo "==> Forcing arm64 because ConvexMobile does not ship an x86_64 simulator slice."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO

echo
echo "iOS Release simulator build passed."
