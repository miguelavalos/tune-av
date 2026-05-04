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

forbidden_local_paths=(
  ".infisical/bootstrap.env.example" \
  ".infisical/bootstrap.env" \
  ".env" \
  ".env.local" \
  ".env.example" \
  "apps/ios/Config/Local.xcconfig" \
  "apps/ios/Config/Local.xcconfig.example" \
  "apps/macos/TuneAVMac/Config/Local.xcconfig" \
  "apps/macos/TuneAVMac/Config/Local.xcconfig.example"
)

for forbidden_path in "${forbidden_local_paths[@]}"; do
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    git ls-files --error-unmatch "$forbidden_path" >/dev/null 2>&1; then
    printf 'Forbidden local config artifact is tracked by git: %s\n' "$forbidden_path" >&2
    exit 1
  fi
done

if [ "${TUNEAV_STRICT_PUBLIC_HYGIENE:-}" = "1" ]; then
  for forbidden_path in "${forbidden_local_paths[@]}"; do
    if [ -e "$forbidden_path" ]; then
      printf 'Forbidden local config artifact in strict public hygiene mode: %s\n' "$forbidden_path" >&2
      exit 1
    fi
  done
fi

content_pattern='pk_(live|test)_[A-Za-z0-9_]+|sk_(live|test)_[A-Za-z0-9_]+|real_publishable_key|CLERK_SECRET_KEY=|ACCOUNTAV_SUBSCRIPTION_SYNC_TOKEN=|https://api\.av-account\.avalsys\.com|avaccount_api_base_url=.*127\.0\.0\.1:8788|AVALSYS_APPLE_DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|miguel@|elisca'

if tracked_files \
  | grep -z -v '^scripts/check-public-config-hygiene\.sh$' \
  | grep -z -v '^\./scripts/check-public-config-hygiene\.sh$' \
  | xargs -0 rg -n --no-messages "$content_pattern"; then
  printf 'Forbidden config/secrets pattern found in tracked files.\n' >&2
  exit 1
fi

if tracked_files \
  | grep -z 'env\.schema$' \
  | xargs -0 rg -n --no-messages 'ACCOUNTAV_SIGNED_IN_SMOKE_TOKEN'; then
  printf 'Forbidden persistent signed-in smoke token schema entry found. Use the private runtime prompt wrapper instead.\n' >&2
  exit 1
fi

printf 'Public config hygiene check passed.\n'
