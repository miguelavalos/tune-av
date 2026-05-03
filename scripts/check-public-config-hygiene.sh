#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tracked_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z
  else
    find . \
      -path './node_modules' -prune -o \
      -path './.infisical' -prune -o \
      -path './.codex' -prune -o \
      -path './DerivedData' -prune -o \
      -path './build' -prune -o \
      -type f -print0
  fi
}

for forbidden_path in \
  ".infisical/bootstrap.env.example" \
  ".infisical/bootstrap.env" \
  ".env" \
  ".env.local" \
  ".env.example" \
  "apps/ios/Config/Local.xcconfig" \
  "apps/ios/Config/Local.xcconfig.example" \
  "apps/macos/AvtunesysMac/Config/Local.xcconfig" \
  "apps/macos/AvtunesysMac/Config/Local.xcconfig.example"
do
  if [ -e "$forbidden_path" ]; then
    printf 'Forbidden local config artifact in public repo workspace: %s\n' "$forbidden_path" >&2
    exit 1
  fi
done

content_pattern='pk_(live|test)_[A-Za-z0-9_]+|sk_(live|test)_[A-Za-z0-9_]+|real_publishable_key|CLERK_SECRET_KEY=|AVACCOUNT_SUBSCRIPTION_SYNC_TOKEN=|https://api\.av-account\.avalsys\.com|avaccount_api_base_url=.*127\.0\.0\.1:8788|346677S99H|miguel@|elisca'

if tracked_files \
  | grep -z -v '^scripts/check-public-config-hygiene\.sh$' \
  | grep -z -v '^\./scripts/check-public-config-hygiene\.sh$' \
  | xargs -0 rg -n --no-messages "$content_pattern"; then
  printf 'Forbidden config/secrets pattern found in tracked files.\n' >&2
  exit 1
fi

if tracked_files \
  | grep -z 'env\.schema$' \
  | xargs -0 rg -n --no-messages 'AVACCOUNT_SIGNED_IN_SMOKE_TOKEN'; then
  printf 'Forbidden persistent signed-in smoke token schema entry found. Use the private runtime prompt wrapper instead.\n' >&2
  exit 1
fi

printf 'Public config hygiene check passed.\n'
