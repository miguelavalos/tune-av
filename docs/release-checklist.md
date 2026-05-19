# iOS Release Checklist

Use this checklist before creating a public GitHub release or App Store build
from the public Tune AV iOS repository.

## Repository Hygiene

1. Run `bun install`.
2. Run the public hygiene check:

   ```bash
   bun run config:hygiene
   ```

3. Confirm no generated config files are present:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - private bootstrap files
4. Confirm no signing files, provisioning profiles, private keys, exported certificates, or local build products are present.
5. Confirm public docs do not contain private email addresses, personal account names, Team IDs, local backend URLs, provider secrets, runbooks, or non-public operational/planning details.

## Build Verification

1. Confirm the local archive toolchain matches Apple's current upload gate. For
   App Store uploads created on or after 2026-04-28, build with Xcode 26 and
   the iOS 26 SDK or later.

2. For any signed local install, use the guarded preflight before building:

   ```bash
   bun run ios:check:prod
   ```

   Private validation details belong outside the public repository.

3. Generate the iOS Xcode project when `apps/ios/project.yml` changes:

   ```bash
   cd apps/ios && xcodegen generate
   ```

4. Run iOS unit tests:

   ```bash
   cd apps/ios
   xcodebuild test -project TuneAV.xcodeproj \
     -scheme TuneAV \
     -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
     -only-testing:TuneAVTests \
     CODE_SIGNING_ALLOWED=NO
   ```

   The simulator destination is an example. Replace it with an installed
   destination from `xcodebuild -showdestinations` when the local Xcode runtime
   set differs.

5. Run targeted UI tests when the release changes shell navigation, limits,
   playback queue, search, Profile, purchase/restore, account deletion, or
   discovery behavior.

## App Review Readiness

Before creating the archive for review:

1. Confirm the submitted build is iPhone-only and uses the intended orientation
   policy.
2. Confirm App Privacy answers match the submitted build, including purchases,
   optional account data, cloud sync, and listening analytics when enabled.
3. Confirm third-party SDK privacy manifests and signatures are present where
   Apple requires them, especially for subscription, account, analytics, or
   phone/auth dependencies.
4. Smoke-test Guest playback, sign-in, Profile, Tune AV Pro paywall, restore,
   account deletion, full player, background audio, search, favorites, recents,
   and last-played queue resume.
5. Recreate screenshots from the exact build attached to App Store Connect after
   any meaningful UI, localization, entitlement, or paywall change.

## App Transport Security

Tune AV declares `NSAllowsArbitraryLoads` because live radio catalogs can include
playable HTTP stream URLs that are not under AVALSYS control. Keep this exception
limited by app behavior:

- Account AV, Support AV, legal, and open-source URLs must resolve to HTTPS
  except localhost loopback during development.
- The in-app browser must reject remote HTTP pages; use HTTPS for web content.
- Remote HTTP should be treated as playback-only stream input for `AVPlayer`,
  not as a general networking policy.
- Before App Review, confirm review notes explain the radio-stream compatibility
  reason for ATS broad loading and that authenticated/backend traffic remains
  HTTPS-only.

## Public Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe only public workflows.
3. Create a version tag only after build, tests, and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.

## Private Operations

Store portal plans, provider setup, signing steps, production config, service
smoke tests, implementation plans, and review-response material belong outside
this public repository.

Before App Review, the private release owner must separately confirm App Store
Connect build processing, internal-only TestFlight assignment, live subscription
availability, RevenueCat mapping/webhooks, real-device TestFlight smoke, sandbox
purchase/restore/reconciliation, SDK privacy/signature evidence, App Privacy
answers, review notes, and submitted-build screenshots.
