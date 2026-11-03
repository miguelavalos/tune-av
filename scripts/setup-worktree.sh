#!/bin/sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "setup-worktree: xcodegen is not installed (brew install xcodegen)" >&2
  exit 1
fi

for app in ios macos; do
  if ! (cd "$root/apps/$app" && xcodegen generate --quiet); then
    echo "setup-worktree: xcodegen generate failed in apps/$app" >&2
    exit 1
  fi
done

echo "Worktree ready: Xcode projects generated in apps/ios and apps/macos"
