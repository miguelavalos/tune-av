# Tune AV iOS Current State

Date: 2026-07-29

This is the public source of truth for the current Tune AV Apple clients. It
describes frontend behavior and local verification only. Release operations,
approval status, signing, service setup, service consoles, and private evidence
belong outside this repository.

The authoritative cloud-sync boundary is
[Tune AV Pro Sync Scope](pro-sync-scope.md). TestFlight builds `52` and `61`
still implement the superseded feedback-sync behavior and must not be promoted.
Current source implements the narrowed contract and has passed local iOS,
macOS, localization, and backend-focused verification. Replacement candidates
iOS/iPadOS `1.0.7 (53)` and macOS `1.0.7 (62)` were accepted for TestFlight
processing on 2026-07-13. Both finished processing and joined the internal test
group; macOS `62` is installed and its cold-launch no-feedback-read gate passed.

The current iOS/iPadOS account-transition candidate is `1.0.7 (56)`, built from
public commit `ba140ef`. Its production configuration and signed Release build
passed the repository gates, and the same build was installed and accepted on a
physical iPhone and iPad. The verified archive was accepted by App Store
Connect on 2026-07-29, finished processing, and is available to the internal
`Tune AV Test` group. It was not submitted to App Review.

The matching macOS account-transition candidate is `1.0.7 (64)`, built from
public commit `d0d4993`. Its current production configuration, complete 63-test
suite, archive identity, privacy, signing, architecture, keychain, and dSYM
checks passed. The owner accepted the exact archived app locally. App Store
Connect accepted that archive on 2026-07-29, finished processing it, and lists
build 64 as `Ready to Submit` in the internal `Tune AV Test` group. It was not
submitted to App Review.

App Store compatibility note, 2026-07-29: the currently distributed iOS and
macOS clients were built before the Convex owner-account transition and retain
their previous production realtime endpoint. Keep that deployment available
while those clients remain supported. Removing it would not remove the durable
D1/API library authority or core playback/search behavior, but it can degrade
Pro realtime invalidation for installed clients. A replacement may be retired
only after new iOS and macOS builds using the current endpoint are released,
verified from the App Store, and given an explicit adoption/deprecation window.

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

The Apple clients use a calm-sync model to keep Cloudflare and Convex traffic
bounded:

- perform one automatic full library sync at cold startup or after successful
  sign-in when Pro cloud sync is available;
- keep foreground transitions passive instead of treating every activation as
  another full-sync trigger;
- keep manual `Sync now` as the explicit recovery path;
- serialize backend mutations within each app process so a burst of local
  changes cannot create parallel Cloudflare writes;
- attach the persisted operation UUID as `Idempotency-Key` to item-level
  library writes, and reuse it on every retry;
- retry only transient network failures and HTTP `408`, `425`, `429`, or `5xx`,
  respect numeric `Retry-After`, and stop after five total attempts; permanent
  failures remain persisted for a later manual/session recovery instead of
  looping;
- create one realtime session and one Convex subscription for the active Pro
  account, and reuse them while the account identity is unchanged;
- renew that realtime session before its server-provided expiry, with bounded
  jittered retries, while keeping the existing session and subscription when
  the app returns to the foreground outside the renewal window;
- pause renewal and Convex observation while inactive (and during macOS system
  sleep), and remove an expired session after the bounded retry budget is
  exhausted;
- preserve the confirmed Pro capability while refreshing entitlement state for
  the same internal account user, avoiding a temporary Free state that would
  tear down and recreate realtime sync;
- when the internal account user changes, immediately remove the previous
  account's capabilities until the new user's backend access is resolved.
- compare the first Convex projection with the exact per-resource timestamps
  returned by the Cloudflare bootstrap, so already-covered favorites or saved
  discoveries do not trigger duplicate reads;
- use the exact per-resource timestamp to suppress a projection already covered
  by bootstrap;
- after an item-level favorite or saved-discovery mutation succeeds, retain the
  response `updatedAt` as coverage for that resource so the matching projection
  does not make the authoring device read its own write;
- after a realtime baseline exists, scope a single consecutive library
  generation to its declared resource on both Apple clients, issuing one
  resource GET and no unrelated feedback or summary read;
- do not bootstrap, restore, poll, or subscribe to feedback as a sync resource;
  feedback writes must not create Convex invalidations or projection fanout;
- keep bootstrap, manual recovery, generation gaps, and unknown resources on
  the conservative full-library path.

Realtime invalidations may request a focused refresh, but must not create a
polling loop or an additional foreground-driven full sync.

For one successful local item mutation, the steady-state cross-device request
budget is one mutation request from the authoring device, zero follow-up App
Data GETs on that device for the matching covered projection, and one exact
resource GET on each active receiving device. Missing or malformed mutation
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

- release and verify replacement iOS/macOS builds that use the current
  production realtime endpoint before retiring compatibility for older Apple
  clients;
- keep localization keys complete before adding visible SwiftUI copy;
- continue testing playback and artwork behavior on real devices;
- keep public docs focused on client behavior, local setup, and local
  verification;
- keep macOS release documentation aligned with the Apple Silicon-only target
  until the Convex Swift dependency supports Intel macOS archives.
