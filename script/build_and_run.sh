#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/apps/macos"
PROJECT="$PROJECT_DIR/TuneAVMac.xcodeproj"
SCHEME="TuneAVMac"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT_DIR/.derivedData/mac"
APP_NAME="Tune AV"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Tune AV.app"

VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" || true
fi

cd "$PROJECT_DIR"
xcodegen generate

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

/usr/bin/open -n "$APP_PATH"

if [[ "$VERIFY" == "1" ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
fi
