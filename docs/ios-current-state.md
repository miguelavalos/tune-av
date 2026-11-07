# Tune AV iOS Current State

Date: 2026-11-07

This is the public source of truth for the current Tune AV Apple clients. It
describes frontend behavior and local verification only. Release operations,
approval status, signing, service setup, service consoles, and private evidence
belong outside this repository.

Current builds, 2026-11-07:

- The latest TestFlight builds are iOS/iPadOS `1.1.0 (63)` and macOS
  `1.1.0 (68)`, built from public commit `bad896d` (see the `1.1.0` entry in
  [CHANGELOG.md](../CHANGELOG.md)). Neither has been submitted to App Review.
- The latest App Store approved versions are iOS/iPadOS `1.0.7 (56)`, built
  from public commit `ba140ef`, and macOS `1.0.7 (64)`, built from public
  commit `d0d4993`. The owner submitted both on 2026-07-29 and confirmed their
  approval; a signed-in App Store Connect read listed both `1.0.7` platform
  versions as `Ready for Distribution`. They predate the realtime removal.
- Since `1.0.9` (iOS `58` and macOS `66`, uploaded to App Store Connect for
  TestFlight on 2026-11-01) the Apple clients contain no Convex realtime layer,
  and the macOS app builds universal (Apple Silicon and Intel) again; see the
  realtime retirement note below.

Earlier TestFlight candidates reached the internal `Tune AV Test` group and
were never submitted to App Review: iOS/iPadOS `1.0.8 (57)` and macOS
`1.0.8 (65)` (2026-08-01, public source `126d989` with the bounded
purchase/restore reconciliation repair in `b9b3cd8`; the `1.0.8` train was
required because Apple rejected reuse of the closed approved `1.0.7` train),
and iOS/iPadOS `1.0.7 (53)` and macOS `1.0.7 (62)` (2026-07-13, public source
`515bd93`).

The authoritative cloud-sync boundary is
[Tune AV Pro Sync Scope](pro-sync-scope.md). TestFlight builds `52` and `61`
still implement the superseded feedback-sync behavior and must not be promoted.
Current source implements the narrowed contract and has passed local iOS,
macOS, localization, and backend-focused verification.

Realtime retirement note, 2026-11-01: the Convex realtime layer was removed
from both Apple clients. Current source no longer links `ConvexMobile`, no
longer reads `TUNEAV_CONVEX_URL`, and never calls
`POST /v1/tune/workspace/realtime-sessions`. Pro cloud sync now refreshes on
app open, on foreground activation (throttled to once per minute), after a
successful sign-in, and on the manual `Sync now` action. Older installed builds
that still request a realtime session receive `503 realtime_disabled` from the
backend and keep working with their startup and manual sync paths; durable D1/API
library authority and playback/search behavior are unaffected.

## App Scope

Tune AV iOS is a SwiftUI radio app in `apps/ios/TuneAV`. Tune AV macOS is a
SwiftUI macOS app in `apps/macos` that shares product behavior where practical
and uses native macOS presentation differences.

Current app shape:

- local-first playback, recents, discovery history, playback state, and device
  settings;
- explicitly saved stations and explicitly saved songs restore with Pro cloud
  sync when configured;
- station and song feedback remains local to each device; a deliberate Pro
  action may upload once for server-side summaries and recommendations;
- optional sign-in and premium UI surfaces when local configuration enables
  them;
- Guest, signed-in Free, and signed-in Pro presentation states;
- iOS Home, Search, Avi, Library, Music, and Profile shell tabs;
- macOS Home, Radios, Music, Search, Account, and Settings shell navigation,
  with Avi exposed through contextual player surfaces and the native Avi menu
  instead of a standalone sidebar destination;
- music-first station discovery with an explicit all-radio mode;
- contextual Avi surfaces in Home, player, music, limits, and Profile flows;
- iPhone and iPad-compatible client presentation;
- portrait-only iPhone full player with fixed-size Avi feedback, larger artwork,
  stable title truncation, artwork/text zoom for full metadata, and no
  mini-player overlay while the full player is open;
- last-played queue restoration so resuming from Home can preserve Favorites or
  Recents next/previous behavior when that was the active context;
- local iOS Profile preferences for external web links: public web links open
  inside Tune AV by default and can be switched to the system browser;
- local iOS Profile preference for external public-info and lyrics search, using
  the shared Apps AV engine list with DuckDuckGo as the default;
- premium paywall and restore-entry UI when configured; the monthly price is
  visible to guests, a guest purchase signs in first and then continues, and
  the limit prompt always leads to the paywall;
- Avi lookups metered per day for every tier (Guest 5, Free 15, Pro
  unlimited) and a one-time contextual upgrade moment after the 10th song
  discovered in a session or on the 3rd distinct listening day;
- account deletion entry point and local data clearing from Profile;
- app-neutral shared Apple UI foundations for brand tokens, shell structure,
  launch/splash support, settings/account surfaces, Avi controls, paywall/limit
  surfaces, external link/search defaults, and text-fit hardening.
- macOS universal build target (Apple Silicon and Intel) now that the Convex
  Swift binary dependency is gone.

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
| Signed-in Free | account-connected | 15 | no cloud sync; feedback remains local |
| Signed-in Pro | account-connected Pro | unlimited in-app policy | explicitly saved stations and saved songs restore, when configured |

Recents, discovery history, playback state, and settings are local-only in the
current public client contract. Premium access is displayed by the client only
after configured entitlement state is available. The public repo does not
document private entitlement operations.

The current iOS external-link settings are local device preferences. Public-info
and lyrics searches use the selected shared Apps AV search engine. Web links use
the embedded Tune AV browser unless the user selects the system browser.

Saved songs use canonical track keys across iOS, macOS, and the account backend
and sync through active saved-song records. Feedback keys may still be
normalized for stable local storage and backend analytics, but feedback is not
downloaded or restored as user-visible cross-device state. Discovery history
remains local-only and can legitimately show different song totals per device.

## Calm Pro Sync Contract

The Apple clients use a calm-sync model to keep Cloudflare traffic bounded:

- perform one automatic full library sync at cold startup or after successful
  sign-in when Pro cloud sync is available;
- pull again when the app returns to the foreground (iOS scene activation,
  macOS app activation or system wake), throttled to at most one automatic
  pull per 60 seconds; there is no timer, polling loop, or push channel;
- send `If-None-Match` with the last known resource ETag on every repeated
  app-data GET and treat `304 Not Modified` as "library unchanged" without
  re-applying or re-pushing anything;
- keep manual `Sync now` as the explicit recovery path on iOS and macOS;
- serialize backend mutations within each app process so a burst of local
  changes cannot create parallel Cloudflare writes;
- attach the persisted operation UUID as `Idempotency-Key` to item-level
  library writes, and reuse it on every retry;
- retry only transient network failures and HTTP `408`, `425`, `429`, or `5xx`,
  respect numeric `Retry-After`, and stop after five total attempts; permanent
  failures remain persisted for a later manual/session recovery instead of
  looping;
- preserve the confirmed Pro capability while refreshing entitlement state for
  the same internal account user, avoiding a temporary Free state;
- when the internal account user changes, immediately remove the previous
  account's capabilities until the new user's backend access is resolved;
- after an item-level favorite or saved-discovery mutation succeeds, retain the
  response `updatedAt` and ETag as coverage for that resource so the next
  conditional pull is validated instead of re-downloaded;
- do not bootstrap, restore, poll, or subscribe to feedback as a sync resource;
- keep bootstrap and manual recovery on the conservative full-library path.

For one successful local item mutation, the steady-state cross-device request
budget is one mutation request from the authoring device and, on each other
device, one conditional GET per synced resource at its next open, foreground
activation, or manual sync. Missing or malformed mutation
timestamps remain conservative and do not suppress a read.

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
vp run config:hygiene
vp run ios:tests
vp run macos:tests
```

`vp run config:hygiene` is a public-source hygiene check and expects generated
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

The destination above is an example. `vp run ios:tests` uses the repository
helper that selects an available iPhone simulator and can be overridden with
`TUNEAV_IOS_SIMULATOR_NAME`.

Release-readiness preflights with generated production config present:

```bash
vp run ios:release:preflight
vp run ios:release:preflight -- --with-archive
vp run macos:release:preflight
vp run macos:release:preflight -- --with-archive
```

Historical local client verification under the superseded feedback-sync
contract, run on 2026-07-10:

- Convex client configuration checks passed with generated production config;
- iOS production runtime config, release privacy gate, archive privacy
  evidence, Sentry dSYM repair, and app-size gate passed;
- iOS unit tests: 349 tests, 0 failures;
- macOS production runtime config, platform security, and unsigned Release
  archive preflight passed;
- macOS unit tests: 51 tests, 0 failures;
- signed iOS runtime validation restored the same Pro account with one access
  resolution, one realtime-session creation, one Convex subscription, and one
  measured full library sync; the app then remained sync-silent for more than
  90 seconds;
- regression coverage confirms that refreshing the same account preserves Pro
  capabilities while backend resolution is pending, while switching accounts
  removes the previous account's Pro capabilities immediately;
- regression coverage confirms that the first Convex projection after
  bootstrap does not repeat covered Cloudflare library, feedback, or summary
  reads, while a genuinely newer resource still requests its focused refresh.

The feedback portions of this evidence describe older behavior and are not
requirements for the replacement build. The 2026-07-13 contract removes
feedback bootstrap, restore, and realtime refresh.

Latest replacement delivery checkpoint, 2026-07-13: iOS/iPadOS `1.0.7 (53)`
and macOS `1.0.7 (62)` were archived from public source commit `515bd93`, passed
the governed production and archive gates, and were accepted for processing by
App Store Connect. Both later became ready for internal testing. TestFlight
automatically installed macOS `62`; its TestFlight signature, bundle, team, Pro
session, and `Todo al día` state were verified. One bounded signed-in Pro cold
launch made one profile GET, one access GET, one favorites GET, one
saved-discoveries GET, and one realtime-session POST, all successful. It made
no feedback GET, summary request, retry, or mutation. One delayed idempotent
listening-session upload from playback before the clean launch was observed and
is analytics, not sync. Neither build was submitted to App Review. iOS `53`
installation and the remaining focused physical gate are open.

Latest focused feedback checkpoint, 2026-07-13: macOS TestFlight build `62`
sent exactly one successful Pro station-feedback save. The following bounded
quiet window contained no feedback read, summary, retry, realtime request, or
second write, and the projection outbox did not advance. The subsequent clear
attempt was rejected with `400` because the shared iOS/macOS request structs
omitted an optional `nil` feedback field instead of encoding the
backend-required JSON `null`. The client correctly made no retry, but the
backend row remained; it was removed with one exact production cleanup and
verified absent. The outbox remained at four historical feedback rows with
nothing newer than `2026-07-10T10:40:38.112Z`.

Current source now explicitly encodes JSON `null` for station and track clears
on both iOS and macOS. Exact payload regressions pass, as do the complete 363
iOS and 63 macOS unit tests and public configuration hygiene. This repair is
client-only: no Worker, Convex, production configuration, production data, or
App Review state changed. Builds `53` and `62` predate the fix and must not be
selected for review; later TestFlight candidates require a bounded save/clear
proof. Physical iOS proof remains deferred while the iPhone is unavailable.

Latest repaired-candidate delivery checkpoint, 2026-07-13: iOS/iPadOS
`1.0.7 (54)` and macOS `1.0.7 (63)` were archived from public source commit
`efc9515`, which contains the explicit-null repair. Production preflights
passed with zero failures and zero warnings; the iOS Release simulator build,
final archive, privacy, signing-team, architecture, and application/Sentry dSYM
checks passed. App Store Connect accepted iOS at 20:57 CEST and macOS at 21:02
CEST with `Upload succeeded` and `EXPORT SUCCEEDED`; both began processing.
The signed-in browser session expired before finished-processing and internal
group availability could be confirmed, so neither is yet recorded as ready to
install or test. Neither build was submitted to App Review. Once availability
is confirmed, the next gate is one bounded signed-in Pro save/clear trace on
the repaired build: exactly one successful save PUT and one successful clear
PUT, with no feedback GET, summary, retry, realtime request, second mutation,
or outbox/Queue/Convex fanout. Physical iOS proof remains separate.

Historical TestFlight delivery checkpoint, 2026-07-10:

- iPhone/iPad `1.0.7 (46)` and macOS `1.0.7 (55)` were archived from public
  commit `1f65bc0`, passed their final archive, privacy, signing, architecture,
  app-size, and Sentry dSYM checks, and were accepted for processing by App
  Store Connect;
- these builds contain the bounded realtime-session renewal supervisor. Their
  TestFlight processing and tester-group availability still require explicit
  confirmation in App Store Connect before installation or App Review use.

Latest post-approval source checkpoint, 2026-07-03:

- App Store approved baselines are iPhone/iPad `1.0.5 (44)` and macOS
  `1.0.5 (47)` per operator report; approval evidence remains private.
- iPhone/iPad `1.0.6 (45)` was uploaded to App Store Connect and submitted to
  App Review on 2026-07-03 per operator report; approval is pending. It filters
  expected unavailable promo-code responses out of Sentry capture.
- macOS `1.0.6 (49)` was uploaded to App Store Connect and submitted to App
  Review on 2026-07-03; approval is pending. Review submission id:
  `5e5d7cdb-7827-4472-ae9f-f737dd92fb24`. It includes the Music history
  list-source fix, macOS radio-library regression coverage, and contextual Avi
  navigation. The App Store Connect `1.0.5` pre-release train is closed after
  approval, so new macOS TestFlight uploads must use the next marketing version.
  The previous macOS `1.0.6 (48)` package was uploaded to App Store Connect on
  2026-07-03 before the contextual Avi navigation update.
- The approved maintenance build includes the Account/Tune AV Pro access
  loading-state fix.
- Public i18n parity and the targeted iOS/macOS Account loading checks passed
  before committing this source checkpoint.
- The current macOS source fixes the Music list-source regression: History uses
  the full local discovery history, Top/Afinadas uses tuned discoveries, and
  Songs/Artists use saved discoveries. The Radios screen was checked against
  the same risk and now has regression coverage for Saved, Recents, Afinadas,
  and Music station lists.
- The current macOS source keeps Avi as a contextual assistant surface: Home
  still exposes Avi Picks, the player exposes `More with Avi` as a popover, and
  the native macOS Avi menu provides current song/radio actions without adding
  a standalone Avi sidebar page.

Signed device installs should use:

```bash
vp run ios:install:dev
vp run ios:install:prod
```

Those commands regenerate local config, validate the resolved environment,
build, install, and launch the app.

## Open Public Work

- keep localization keys complete before adding visible SwiftUI copy;
- continue testing playback and artwork behavior on real devices;
- keep public docs focused on client behavior, local setup, and local
  verification.

Completed on 2026-11-01 with `1.0.9` (iOS `58`, macOS `66`): the first iOS and
macOS builds without the realtime layer, and the first universal (Apple Silicon
and Intel) macOS archive. The backend `503 realtime_disabled` compatibility
reply stays while installed builds older than `1.0.9` can still request a
realtime session.
