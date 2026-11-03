#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
worktree="$(pwd)"
main_checkout="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"

if [ -z "$main_checkout" ] || [ ! -d "$main_checkout" ]; then
  echo "setup-worktree: cannot resolve the main checkout from git worktree list" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "setup-worktree: xcodegen is not installed (brew install xcodegen)" >&2
  exit 1
fi

# project.yml in apps/ios and apps/macos, and apps/web/package.json, resolve
# ../../../account-av and ../../../apps-av: siblings of the repository root.
# A worktree lacks them, so link the main checkout's siblings beside it.
for sibling in account-av apps-av; do
  if [ ! -d "$main_checkout/../$sibling" ]; then
    echo "setup-worktree: $sibling is missing at $main_checkout/../$sibling" >&2
    exit 1
  fi
  source="$(cd "$main_checkout/../$sibling" && pwd)"
  if [ "$worktree" = "$main_checkout" ]; then
    echo "setup-worktree: main checkout, $sibling is already beside it"
    continue
  fi
  target="$worktree/../$sibling"
  if [ -e "$target" ]; then
    continue
  fi
  ln -s "$source" "$target"
done

for app in ios macos; do
  if ! (cd "$worktree/apps/$app" && xcodegen generate --quiet); then
    echo "setup-worktree: xcodegen generate failed in apps/$app" >&2
    exit 1
  fi
done

echo "Worktree ready: siblings linked, Xcode projects generated in apps/ios and apps/macos"
