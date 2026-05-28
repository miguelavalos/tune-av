# Tune AV iOS Current State

Date: 2026-05-28

This is the public source of truth for the current Tune AV iOS app. It describes
what exists in this repository without exposing private backend, signing, or
release operations.

## App Scope

Tune AV iOS is a SwiftUI radio app in `apps/ios/TuneAV`.

Current app shape:

- local-first playback, favorites, recents, discoveries, settings, and feedback;
- optional Account AV sign-in when local configuration enables it;
- Guest, signed-in Free, and signed-in Pro access states;
- Home, Search, Avi, Library, Music, and Profile shell tabs;
- music-first station discovery with an explicit all-radio mode;
- contextual Avi surfaces in Home, player, music, limits, and Profile/Pro flows;
- portrait-only iPhone full player with fixed-size Avi feedback, larger artwork,
  stable title truncation, artwork/text zoom for full metadata, and no mini-player
  overlay while the full player is open;
- last-played queue restoration so resuming from Home can preserve Favorites or
  Recents next/previous behavior when that was the active context;
- RevenueCat purchase/restore boundary for monthly Tune AV Pro when configured;
- Tune AV Pro paywall that shows sign-in first for Guest users and purchase or
  restore actions for signed-in users when configured;
- backend-backed access refresh, user summary, listening analytics, and cloud
  library sync only when the signed-in/configured runtime supports them;
- account deletion entry point and local data clearing from Profile.
- app-neutral shared Apple UI foundations from `apps-av/apple` are now used for
  brand tokens, shell structure, launch/splash support, settings/account
  surfaces, Avi controls, paywall/limit surfaces, and text-fit hardening.

## Access Model

The public fallback policy is:

| Mode | State | Daily Avi actions | Cloud sync |
| --- | --- | ---: | --- |
| Guest | local-only | 5 | no |
| Signed-in Free | account-connected | 15 | no |
| Signed-in Pro | account-connected Pro | unlimited in-app policy | yes, when backend config is available |

Premium access is not granted by the client alone. The app refreshes Account AV
access and waits for backend-owned entitlement reconciliation after purchase or
restore.

## Runtime Configuration

Tracked source ships with neutral public defaults. Private values are generated
into `apps/ios/Config/Local.xcconfig` and must stay untracked.

Important public contract names:

- `ACCOUNTAV_PUBLISHABLE_KEY`
- `ACCOUNTAV_API_BASE_URL`
- `ACCOUNTAV_MANAGEMENT_URL`
- `SUPPORTAV_BASE_URL`
- `TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS`
- `TUNEAV_REVENUECAT_PUBLIC_API_KEY`
- `TUNEAV_REVENUECAT_OFFERING_ID`
- `TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID`
- `TUNEAV_TERMS_URL`
- `TUNEAV_PRIVACY_URL`
- `TUNEAV_DELETE_ACCOUNT_URL`

Do not add private hostnames, API keys, project IDs, dashboard URLs, signing
material, or generated config to this repository.

## Active iOS Docs

- [install.md](install.md): local simulator, guarded iOS device install, and
  macOS setup.
- [public-config-policy.md](public-config-policy.md): public/private config
  boundary.
- [ios-animation-and-assets.md](ios-animation-and-assets.md): playback-safe
  UI animation rules and Avi PNG frame-loop asset contract.
- [station-enrichment-contract.md](station-enrichment-contract.md): public iOS
  display expectations for enriched stations.
- [release-checklist.md](release-checklist.md): public repository hygiene and
  iOS verification gates.

Backend automation, subscription dashboards, App Store Connect operations,
private release evidence, and production smoke details belong outside this
public repository.

## Verification

Public local checks:

```bash
bun run config:hygiene
bun run ios:tests
```

For simulator build-only checks:

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  build
```

The destination above is an example. Use `xcodebuild -showdestinations` or
Xcode's Devices window and replace the name/OS with an installed simulator when
the local Xcode image set differs.

Latest full local verification known to the maintainers, run on 2026-05-22:

- `apps-av/apple`: `swift build`, 0 failures.
- `TuneAVTests`: 286 tests, 0 failures on `iPhone 17 / iOS 26.5`.
- `HomeUITests/testTogglingFavoriteKeepsHomeInteractive`: 1 UI test, 0
  failures on `iPhone 17 / iOS 26.5`.
- Tune AV Debug build/run on `iPhone 17 / iOS 26.5`, with Home shell snapshot
  showing header, tabs, Avi entry, Home hero, and scrollable content.

Latest release readiness verification known to the maintainers:

- `bun run ios:release:preflight`: passed with `0 failure(s), 0 warning(s)`.
- `bun run ios:release:preflight -- --with-archive`: unsigned Release archive
  succeeded, strict archive privacy evidence passed with app, RevenueCat, and
  PhoneNumberKit privacy manifests, and app-size gate reported `24.82 MiB`.
- App Store upload export options are checked in at
  `apps/ios/Config/ExportOptionsUpload.plist`.
- Tune AV iOS `1.0` build `13` was uploaded to App Store Connect on 2026-05-28
  and attached to App Review after the subscription metadata/paywall update.
- The public app now keeps subscription price display on official StoreKit /
  RevenueCat localized product data; App Review evidence and private provider
  setup remain outside this repository.

The public repository does not contain private App Store Connect, signing,
RevenueCat dashboard, webhook, or App Review evidence.

Signed device installs should use:

```bash
bun run ios:install:dev
bun run ios:install:prod
```

Those commands regenerate local config, validate the resolved environment, build,
install, and launch the app.

## Open Public Work

- keep screenshots and public App Store copy aligned with the shipped iOS build;
- keep localization keys complete before adding visible SwiftUI copy;
- continue testing playback and artwork behavior on real devices;
- keep App Review evidence outside the public repository: signed upload, build
  processing, TestFlight assignment, third-party SDK manifests/signatures, App
  Privacy answers, subscription sandbox lifecycle, real-device smoke, review
  notes, and final screenshots;
- keep macOS documentation secondary until macOS is actively being released.
