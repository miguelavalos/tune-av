#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT_PATH="$IOS_DIR/TuneAV.xcodeproj"
SCHEME="TuneAV"
DESTINATION="platform=iOS Simulator,OS=18.5,name=iPhone 16"

TESTS=(
  "TuneAVUITests/HomeUITests"
  "TuneAVUITests/PlayerQueueUITests"
  "TuneAVUITests/SearchQueueUITests"
  "TuneAVUITests/ZHomeEmptyStateUITests"
  "TuneAVUITests/HomeRefreshUITests"
)

cd "$IOS_DIR"
xcodegen generate >/dev/null

for test_id in "${TESTS[@]}"; do
  echo
  echo "==> Running $test_id"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:"$test_id" \
    test \
    CODE_SIGNING_ALLOWED=NO
done

echo
echo "All sequential UI tests passed."
