#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_path=""
expected_bundle_id="com.avalsys.tuneav"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-archive-signing.sh --archive <TuneAVMac.xcarchive>
    [--expected-bundle-id <bundle>]

Validates a signed Tune AV macOS archive and classifies it as:
- local QA ready with Apple Development signing; or
- distribution-ready candidate only if the archive uses a distribution identity.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --expected-bundle-id)
      expected_bundle_id="${2:-}"
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

if [ -z "$archive_path" ]; then
  echo "--archive is required." >&2
  exit 2
fi

case "$archive_path" in
  *.xcarchive) ;;
  *)
    echo "--archive must point to a .xcarchive bundle." >&2
    exit 2
    ;;
esac

archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
if [ ! -d "$archive_path" ]; then
  echo "Archive not found: $archive_path" >&2
  exit 1
fi

app_path="$archive_path/Products/Applications/Tune AV.app"
if [ ! -d "$app_path" ]; then
  echo "Archive app bundle missing: $app_path" >&2
  exit 1
fi

app_binary="$app_path/Contents/MacOS/Tune AV"
if [ ! -f "$app_binary" ]; then
  echo "Archive app binary missing: $app_binary" >&2
  exit 1
fi

plist_print() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

archive_name="$(plist_print "$archive_path/Info.plist" "Name")"
archive_bundle_id="$(plist_print "$archive_path/Info.plist" "ApplicationProperties:CFBundleIdentifier")"
archive_signing_identity="$(plist_print "$archive_path/Info.plist" "ApplicationProperties:SigningIdentity")"
archive_team_id="$(plist_print "$archive_path/Info.plist" "ApplicationProperties:Team")"
app_bundle_id="$(plist_print "$app_path/Contents/Info.plist" "CFBundleIdentifier")"
accountav_keychain_service="$(plist_print "$app_path/Contents/Info.plist" "ACCOUNTAV_KEYCHAIN_SERVICE")"
accountav_keychain_access_group="$(plist_print "$app_path/Contents/Info.plist" "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP")"

if [ -z "$archive_bundle_id" ]; then
  archive_bundle_id="$app_bundle_id"
fi

if [ "$archive_bundle_id" != "$expected_bundle_id" ]; then
  echo "FAIL archive bundle identifier must be $expected_bundle_id, got ${archive_bundle_id:-<missing>}." >&2
  exit 1
fi

expected_keychain_access_group="935PM55U6R.$expected_bundle_id"
expected_keychain_service="com.avalsys.tuneav.account.v2"
if [ "$accountav_keychain_service" != "$expected_keychain_service" ]; then
  echo "FAIL archive ACCOUNTAV_KEYCHAIN_SERVICE must be $expected_keychain_service, got ${accountav_keychain_service:-<missing>}." >&2
  exit 1
fi

if [ "$accountav_keychain_access_group" != "$expected_keychain_access_group" ]; then
  echo "FAIL archive ACCOUNTAV_KEYCHAIN_ACCESS_GROUP must be $expected_keychain_access_group, got ${accountav_keychain_access_group:-<missing>}." >&2
  exit 1
fi

app_archs="$(lipo -archs "$app_binary")"
if [ "$app_archs" != "arm64" ]; then
  echo "FAIL macOS archive must be Apple Silicon-only arm64, got: $app_archs" >&2
  exit 1
fi

codesign_output="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
spctl_output="$(spctl -a -vv "$app_path" 2>&1 || true)"
entitlements_file="$(mktemp)"
trap 'rm -f "$entitlements_file"' EXIT
codesign -d --entitlements :- "$app_path" > "$entitlements_file" 2>/dev/null || true
keychain_groups="$(/usr/libexec/PlistBuddy -c "Print :keychain-access-groups" "$entitlements_file" 2>/dev/null || true)"
if ! printf '%s\n' "$keychain_groups" | rg -q "$expected_keychain_access_group"; then
  echo "FAIL archive entitlements must include keychain access group $expected_keychain_access_group." >&2
  exit 1
fi

authority="$(printf '%s\n' "$codesign_output" | awk -F= '/^Authority=/{print $2; exit}')"
team_identifier="$(printf '%s\n' "$codesign_output" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
signature_kind="unknown"
classification="unknown"

case "$authority" in
  Apple\ Development:*)
    signature_kind="apple-development"
    classification="local-qa-ready"
    ;;
  Apple\ Distribution:*|3rd\ Party\ Mac\ Developer\ Application:*)
    signature_kind="app-store-distribution"
    classification="distribution-candidate"
    ;;
  Developer\ ID\ Application:*)
    signature_kind="developer-id"
    classification="distribution-candidate"
    ;;
  "")
    if printf '%s\n' "$codesign_output" | rg -q '^Signature=adhoc$'; then
      signature_kind="adhoc"
      classification="not-ready"
    fi
    ;;
esac

spctl_status="rejected"
if printf '%s\n' "$spctl_output" | rg -q ': accepted$'; then
  spctl_status="accepted"
fi

cat <<EOF
Tune AV macOS archive
  archive: $archive_path
  archive name: ${archive_name:-unknown}
  bundle id: $archive_bundle_id
  Account AV keychain service: $accountav_keychain_service
  Account AV keychain access group: $accountav_keychain_access_group
  architectures: $app_archs
  signing identity: ${archive_signing_identity:-unknown}
  authority: ${authority:-unknown}
  team identifier: ${team_identifier:-${archive_team_id:-unknown}}
  signature kind: $signature_kind
  spctl: $spctl_status
  classification: $classification
EOF

case "$classification" in
  local-qa-ready)
    echo "Result: this archive is suitable for serious local QA on your own Mac."
    echo "Result: it is not yet a distribution-ready artifact for other machines."
    ;;
  distribution-candidate)
    echo "Result: this archive uses a distribution identity."
    if [ "$spctl_status" = "accepted" ]; then
      echo "Result: policy validation currently accepts the app."
    else
      echo "Result: complete export and notarization/stapling before calling it ready."
    fi
    ;;
  *)
    echo "FAIL archive signing is not adequate for final QA or distribution." >&2
    exit 1
    ;;
esac
