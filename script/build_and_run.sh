#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/macos/TuneAVMac"
PROJECT="$APP_DIR/TuneAVMac.xcodeproj"
SCHEME="TuneAVMac"
CONFIGURATION="Debug"
APP_NAME="Tune AV"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

VERIFY=false
STREAM_LOGS=false

for arg in "$@"; do
  case "$arg" in
    --verify)
      VERIFY=true
      ;;
    --logs|--telemetry)
      STREAM_LOGS=true
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "TuneAVMac" >/dev/null 2>&1 || true

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$APP_DIR" && xcodegen generate)
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  build

APP_PATH="$(find "$DERIVED_DATA" -path "*/Build/Products/$CONFIGURATION/$APP_NAME.app" -type d -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "Could not find built app bundle for $APP_NAME" >&2
  exit 1
fi

/usr/bin/open -n "$APP_PATH"

if [[ "$VERIFY" == true ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running"
fi

if [[ "$STREAM_LOGS" == true ]]; then
  /usr/bin/log stream --style compact --predicate "process == '$APP_NAME'"
fi
