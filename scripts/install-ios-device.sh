#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
device_udid=""
configuration="Debug"
development_team="${DEVELOPMENT_TEAM:-${AVALSYS_APPLE_DEVELOPMENT_TEAM:-}}"
launch_after_install=1

usage() {
  cat <<'USAGE'
Usage:
  scripts/install-ios-device.sh --env dev|prod [--device <UDID>] [--configuration Debug|Release] [--no-launch]

Regenerates Tune AV iOS Local.xcconfig for the selected environment, validates
the effective Xcode settings, builds, installs on a connected iPhone, and
launches the installed bundle.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --device)
      device_udid="${2:-}"
      shift 2
      ;;
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --development-team)
      development_team="${2:-}"
      shift 2
      ;;
    --no-launch)
      launch_after_install=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$env_name" != "dev" ] && [ "$env_name" != "prod" ]; then
  echo "--env must be dev or prod." >&2
  exit 2
fi

if [ -z "$device_udid" ]; then
  device_udid="$(xcrun xcdevice list | awk '
    /"simulator" : false/ { in_device=1; block=$0; next }
    in_device { block=block "\n" $0 }
    in_device && /}/ {
      if (block ~ /"platform" : "com.apple.platform.iphoneos"/ && block ~ /"available" : true/) {
        if (match(block, /"identifier" : "[^"]+"/)) {
          value=substr(block, RSTART, RLENGTH)
          gsub(/"identifier" : "|"/, "", value)
          print value
          exit
        }
      }
      in_device=0
      block=""
    }
  ')"
fi

if [ -z "$device_udid" ]; then
  echo "No connected available iPhone found. Pass --device <UDID>." >&2
  exit 1
fi

"$repo_root/scripts/generate-ios-local-xcconfig.sh" --env "$env_name"
"$repo_root/scripts/check-ios-runtime-config.sh" --env "$env_name" --configuration "$configuration" --device "$device_udid"

derived_data_path="$repo_root/.DerivedData-device-$env_name"

build_args=(
  -project "$repo_root/apps/ios/TuneAV.xcodeproj"
  -scheme TuneAV
  -configuration "$configuration"
  -destination "id=$device_udid"
  -derivedDataPath "$derived_data_path"
  CODE_SIGN_STYLE=Automatic
  -allowProvisioningUpdates
  build
)

if [ -n "$development_team" ]; then
  build_args=(DEVELOPMENT_TEAM="$development_team" "${build_args[@]}")
fi

xcodebuild "${build_args[@]}"

app_path="$derived_data_path/Build/Products/$configuration-iphoneos/TuneAV.app"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"

xcrun devicectl device install app --device "$device_udid" "$app_path"

if [ "$launch_after_install" -eq 1 ]; then
  xcrun devicectl device process launch --device "$device_udid" "$bundle_identifier"
fi

echo "Installed Tune AV $env_name on device $device_udid as $bundle_identifier."
