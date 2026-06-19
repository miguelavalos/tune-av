# Tune AV iOS Current State

Date: 2026-06-19

This is the public source of truth for the current Tune AV Apple clients. It
describes frontend behavior and local verification only. Release operations,
approval status, signing, service setup, service consoles, and private evidence
belong outside this repository.

## App Scope

Tune AV iOS is a SwiftUI radio app in `apps/ios/TuneAV`. Tune AV macOS is a
SwiftUI macOS app in `apps/macos` that shares product behavior where practical
and uses native macOS presentation differences.

Current app shape:

- local-first playback, recents, discovery history, playback state, and device
  settings;
- saved stations, saved songs, station feedback, and song feedback restore with
  Pro cloud sync when configured;
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
- local iOS Profile preferences for external web links: public web links open
  inside Tune AV by default and can be switched to the system browser;
- local iOS Profile preference for external public-info and lyrics search, using
  the shared Apps AV engine list with Google as the default;
- premium paywall and restore-entry UI when configured;
- account deletion entry point and local data clearing from Profile;
- app-neutral shared Apple UI foundations for brand tokens, shell structure,
  launch/splash support, settings/account surfaces, Avi controls, paywall/limit
  surfaces, external link/search defaults, and text-fit hardening.
- macOS Apple Silicon release target while the current Convex Swift binary
  dependency does not provide an Intel macOS slice.

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
| Signed-in Free | account-connected | 15 | uploads station and song feedback for internal product data; no user-facing restore sync |
| Signed-in Pro | account-connected Pro | unlimited in-app policy | saved stations, saved songs, station feedback, and song feedback restore, when configured |

Recents, discovery history, playback state, and settings are local-only in the
current public client contract. Premium access is displayed by the client only
after configured entitlement state is available. The public repo does not
document private entitlement operations.

The current iOS external-link settings are local device preferences. Public-info
and lyrics searches use the selected shared Apps AV search engine. Web links use
the embedded Tune AV browser unless the user selects the system browser.

Saved songs and song feedback use canonical track keys across iOS, macOS, and
the account backend. Saved songs sync through active saved-song records. Song
feedback sync restores from backend feedback rows that include title/artist
metadata, so the tuned songs view can show remote feedback without requiring the
local discovery history item to exist on that device. Clients must normalize
remote records and migrate any URL-encoded local feedback keys on load so
historical local state does not mask synced feedback. Discovery history remains
local-only and can legitimately show different song totals per device.

## Runtime Configuration

Tracked source ships with neutral public defaults. Private values can be
generated into `apps/ios/Config/Local.xcconfig`, which must stay untracked.

Public docs may mention configuration flow and local file names, but must not
document private hostnames, API keys, project IDs, service-console URLs, signing
material, release status, or generated config contents.

## Diagnostics Policy

Expected account or runtime configuration availability states are handled as
local client states, not production errors. In particular, `missingToken` and
`missingBaseURL` from the Account API or macOS sync clients should not be sent
to production diagnostics because they can occur during logout, restore, or
configuration-unavailable windows.

HTTP request failures, entitlement mismatches, sync failures, and unexpected
runtime errors remain reportable diagnostics.

## Active Apple Client Docs

- [install.md](install.md): local simulator, guarded iOS device install, and
  macOS setup.
- [public-config-policy.md](public-config-policy.md): public/private config
  boundary.
- [ios-animation-and-assets.md](ios-animation-and-assets.md): playback-safe UI
  animation rules and Avi PNG frame-loop asset contract.
- [station-enrichment-contract.md](station-enrichment-contract.md): public iOS
  display expectations for enriched station UI.
- [release-checklist.md](release-checklist.md): public repository hygiene,
  iOS/macOS client verification gates, and archive preflights.

## Verification

Public local checks:

```bash
bun run config:hygiene
bun run ios:tests
bun run macos:tests
```

`bun run config:hygiene` is a public-source hygiene check and expects generated
local config files to be absent from the workspace. Release-readiness checks run
with generated local config present and use the platform-specific release config
hygiene scripts.

For simulator build-only checks:

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<installed-iPhone-simulator>' \
  build
```

The destination above is an example. `bun run ios:tests` uses the repository
helper that selects an available iPhone simulator and can be overridden with
`TUNEAV_IOS_SIMULATOR_NAME`.

Release-readiness preflights with generated production config present:

```bash
bun run ios:release:preflight
bun run ios:release:preflight -- --with-archive
bun run macos:release:preflight
bun run macos:release:preflight -- --with-archive
```

Latest local client verification known to the maintainers, run on 2026-06-14:

- Convex client configuration checks passed with generated production config;
- iOS production runtime config, release privacy gate, archive privacy
  evidence, Sentry dSYM repair, and app-size gate passed;
- iOS unit tests: 313 tests, 0 failures;
- macOS production runtime config, platform security, and unsigned Release
  archive preflight passed;
- macOS unit tests: 19 tests, 0 failures.

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
- keep macOS release documentation aligned with the Apple Silicon-only target
  until the Convex Swift dependency supports Intel macOS archives.
