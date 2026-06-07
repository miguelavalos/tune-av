# Tune AV iOS Current State

Date: 2026-05-31

This is the public source of truth for the current Tune AV iOS client. It
describes frontend behavior and local verification only. Release operations,
approval status, signing, service setup, service consoles, and private
evidence belong outside this repository.

## App Scope

Tune AV iOS is a SwiftUI radio app in `apps/ios/TuneAV`.

Current app shape:

- local-first playback, favorites, recents, discoveries, settings, and feedback;
- optional sign-in and premium UI surfaces when local configuration enables
  them;
- Guest, signed-in Free, and signed-in Pro presentation states;
- Home, Search, Avi, Library, Music, and Profile shell tabs;
- music-first station discovery with an explicit all-radio mode;
- contextual Avi surfaces in Home, player, music, limits, and Profile flows;
- portrait-only iPhone full player with fixed-size Avi feedback, larger artwork,
  stable title truncation, artwork/text zoom for full metadata, and no
  mini-player overlay while the full player is open;
- last-played queue restoration so resuming from Home can preserve Favorites or
  Recents next/previous behavior when that was the active context;
- premium paywall and restore-entry UI when configured;
- account deletion entry point and local data clearing from Profile;
- app-neutral shared Apple UI foundations for brand tokens, shell structure,
  launch/splash support, settings/account surfaces, Avi controls, paywall/limit
  surfaces, and text-fit hardening.

## Branding And First Run

Tune AV follows the shared Apps AV first-run sequence:

```text
native launch logo + icon -> product splash with Avi -> onboarding
```

The public repo can use Tune AV as an implementation reference for sequence and
runtime checks. New Apps AV products must still use product-specific icon, logo,
splash, onboarding, and Avi artwork approved in their own brand handoff.

## Access Presentation

The public fallback policy is:

| Mode | State | Daily Avi actions | Cloud sync |
| --- | --- | ---: | --- |
| Guest | local-only | 5 | no |
| Signed-in Free | account-connected | 15 | no |
| Signed-in Pro | account-connected Pro | unlimited in-app policy | yes, when configured |

Premium access is displayed by the client only after configured entitlement
state is available. The public repo does not document private entitlement
operations.

## Runtime Configuration

Tracked source ships with neutral public defaults. Private values can be
generated into `apps/ios/Config/Local.xcconfig`, which must stay untracked.

Public docs may mention configuration flow and local file names, but must not
document private hostnames, API keys, project IDs, service-console URLs, signing
material, release status, or generated config contents.

## Active iOS Docs

- [install.md](install.md): local simulator, guarded iOS device install, and
  macOS setup.
- [public-config-policy.md](public-config-policy.md): public/private config
  boundary.
- [ios-animation-and-assets.md](ios-animation-and-assets.md): playback-safe UI
  animation rules and Avi PNG frame-loop asset contract.
- [station-enrichment-contract.md](station-enrichment-contract.md): public iOS
  display expectations for enriched station UI.
- [release-checklist.md](release-checklist.md): public repository hygiene and
  client verification gates.

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

Latest local client verification known to the maintainers, run on 2026-05-22:

- shared Apple package build passed;
- `TuneAVTests`: 286 tests, 0 failures;
- `HomeUITests/testTogglingFavoriteKeepsHomeInteractive`: 1 UI test, 0
  failures;
- Tune AV Debug build/run launched successfully, with Home shell snapshot
  showing header, tabs, Avi entry, Home hero, and scrollable content.

Signed device installs should use:

```bash
bun run ios:install:dev
bun run ios:install:prod
```

Those commands regenerate local config, validate the resolved environment,
build, install, and launch the app.

## Open Public Work

- keep localization keys complete before adding visible SwiftUI copy;
- continue testing playback and artwork behavior on real devices;
- keep public docs focused on client behavior, local setup, and local
  verification;
- keep macOS documentation secondary until macOS client work is active again.
