#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name="prod"
configuration="Release"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-release-config-hygiene.sh [--env dev|prod] [--configuration Debug|Release]

Checks that iOS Local.xcconfig is present only as an ignored local artifact,
then validates the effective Xcode runtime config without printing secrets.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --configuration)
      configuration="${2:-}"
      shift 2
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

local_config="apps/ios/Config/Local.xcconfig"

cd "$repo_root"

if git ls-files --error-unmatch "$local_config" >/dev/null 2>&1; then
  echo "FAIL $local_config is tracked by git." >&2
  exit 1
fi

if [ ! -f "$local_config" ]; then
  echo "FAIL $local_config is missing. Generate it before release config checks." >&2
  exit 1
fi

ignored_status="$(git status --short --ignored "$local_config")"
if [ "$ignored_status" != "!! $local_config" ]; then
  echo "FAIL $local_config is not reported as an ignored local file." >&2
  printf '%s\n' "$ignored_status" >&2
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
  mode="$(stat -f '%Lp' "$local_config")"
else
  mode="$(stat -c '%a' "$local_config")"
fi

if [ "$mode" != "600" ]; then
  echo "FAIL $local_config permissions must be 600, got $mode." >&2
  exit 1
fi

"$repo_root/scripts/check-ios-runtime-config.sh" --env "$env_name" --configuration "$configuration"

echo "iOS release config hygiene check passed."
