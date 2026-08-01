# Tune AV Client Checklist

Use this checklist before publishing public repo changes or tagging a public
client source release. It is intentionally limited to repository hygiene,
frontend build/test checks, and local client validation.

Release operations, approval status, private service configuration, entitlement
evidence, and service smoke tests belong outside this public repository.

Tune AV follows the public
[Apps AV Apple Product App Patterns](https://github.com/miguelavalos/apps-av/blob/main/docs/apple-product-app-patterns.md)
guide for Account AV, shared Apple packages, app shell, settings, and
public-safe config hygiene.

The authoritative product boundary is
[Tune AV Pro Sync Scope](pro-sync-scope.md). TestFlight builds `52` and `61`
still implement the superseded feedback-sync contract and must not be promoted
to App Review as the final implementation of that decision.

Apple-client compatibility gate, 2026-07-29: currently distributed Tune AV
clients retain the production Convex endpoint that preceded the owner-account
transition. Do not retire that endpoint merely because a replacement TestFlight
build exists. First release current-endpoint builds on both Apple platforms,
verify the App Store-installed binaries, and complete an explicit adoption and
deprecation window. Core D1/API behavior does not make realtime endpoint
compatibility optional for supported Pro clients.

## Repository Hygiene

1. Run `pnpm install`.
2. Run the public hygiene check:

   ```bash
   vp run config:hygiene
   ```

3. Confirm no generated config files are present in tracked git state or left
   in the public-source workspace for commit:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - private bootstrap files
4. Confirm no signing files, provisioning profiles, private keys, exported
   certificates, or local build products are present.
5. Confirm public docs do not contain private email addresses, personal account
   names, local service URLs, service secrets, approval details, or non-public
   operations/planning details.

## iOS Build Verification

1. Generate the iOS Xcode project when `apps/ios/project.yml` changes:

   ```bash
   cd apps/ios && xcodegen generate
   ```

2. Run the public local checks:

   ```bash
   vp run config:hygiene
   vp run ios:tests
   ```

   `vp run config:hygiene` is for public-source cleanup and expects generated
   local config files to be absent. If you are validating a release with
   generated production config present, use the release-readiness checks in step
   7 instead.

3. Run the localization release audit:
   - compare every shipped `apps/ios/TuneAV/Resources/*.lproj/Localizable.strings` key set with `en.lproj`;
   - verify every `L10n.string(...)` reference in the submitted iOS target, macOS target, and shared Apple sources resolves;
   - scan Swift/SwiftUI for user-visible hardcoded `Text`, `Button`, `Label`, navigation title, alert, empty-state, accessibility, and paywall copy.

4. Run a simulator build:

   ```bash
   cd apps/ios
   xcodebuild build -project TuneAV.xcodeproj \
     -scheme TuneAV \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=<installed-iPhone-simulator>' \
     CODE_SIGNING_ALLOWED=NO
   ```

   The simulator destination is an example. `vp run ios:tests` selects an
   available iPhone simulator through `scripts/ios-ci-test.sh`; set
   `TUNEAV_IOS_SIMULATOR_NAME` when a specific simulator is required.

5. Run targeted UI tests when changes touch shell navigation, limits, playback
   queue, search, Profile, paywall presentation, account UI, deletion entry, or
   discovery behavior.

6. Smoke-test visible client flows:
   - first launch;
   - Home;
   - Search;
   - playback;
   - full player;
   - background audio behavior;
   - favorites and recents;
   - last-played queue resume;
   - Avi surfaces;
   - Profile/settings;
   - local data clearing.

7. For release-readiness checks with generated production config present, run:

   ```bash
   vp run ios:release:preflight
   vp run ios:release:preflight -- --with-archive
   ```

   The archive preflight validates release config hygiene, sensitive config
   hygiene, platform security, network privacy, strict archive privacy evidence,
   Sentry dSYM repair, and app-size budgets. The executable budget is a local
   regression guard and can be overridden with
   `TUNEAV_IOS_MAX_EXECUTABLE_SIZE_BYTES` when maintainers intentionally change
   the release budget.

   The generated production config must include both backend bases:
   `ACCOUNTAV_API_BASE_URL` for shared account/platform flows and
   `TUNEAV_API_BASE_URL` for `/v1/tune/*` product flows. Do not upload a new
   build if `TUNEAV_API_BASE_URL` is missing, inherited, local, development, or
   preview-shaped.

8. Use the reproducible archive/upload workflow for iOS App Store releases:

   ```sh
   vp run ios:release:archive -- --build <next-build>
   ```

   The workflow runs release gates, creates the final signed archive, repairs
   `Sentry.framework.dSYM`, and verifies the final `.xcarchive` before any
   upload is allowed. To upload the verified archive, rerun the command printed
   by the workflow with `--upload`.

   Before unattended upload from a new or recently reconfigured Mac, complete
   the private `docs/platform/apple-release-machine-setup.md` gate so the Apple
   Distribution private key can pass non-interactive `codesign`.

   For an existing Organizer archive, run:

   ```sh
   vp run ios:archive:check -- --archive "<path-to-TuneAV.xcarchive>"
   ```

   Do not submit an archive that fails the archive check.

9. Before attaching the uploaded build to App Store review, reconcile App Store
   metadata, privacy answers, legal links, subscription text, and release notes
   with [app-store-review.md](app-store-review.md).
10. After every TestFlight upload, open App Store Connect and confirm the build
    has completed Apple's processing/encoding step before expecting it to appear
    in TestFlight. An upload that is only delivered or still processing is not
    yet addable to TestFlight groups or App Review.

## iOS Network And ATS Behavior

Tune AV should not load arbitrary remote HTTP pages in iOS.

Client checks:

- iOS must not downgrade failed HTTPS playback URLs to HTTP.
- Remote web content opened by the in-app browser should use HTTPS.
- Localhost loopback is allowed only for local development.
- Visible UI should not expose internal diagnostics, raw service errors, or
  private configuration values.
- Expected account or configuration availability states such as `missingToken`
  and `missingBaseURL` should stay local and should not be captured as
  production diagnostics. HTTP failures and unexpected errors should remain
  reportable.

## macOS Client Checks

macOS shares the product behavior where practical and uses native macOS
presentation differences. The current macOS release target is Apple
Silicon-only because the current Convex Swift binary dependency does not provide
an Intel macOS slice. App Store Connect macOS builds are uploaded under the
existing Tune AV app record, so Release/prod archives must use the iOS app
bundle identifier `com.avalsys.tuneav`; Debug/local macOS builds may keep a
separate development bundle identifier.

1. Run:

   ```bash
   vp run macos:tests
   ```

2. For release-readiness checks with generated production config present, run:

   ```bash
   vp run macos:release:preflight
   vp run macos:release:preflight -- --with-archive
   ```

   The archive preflight validates release config hygiene, platform security,
   archive creation, and bundle identifier evidence.

   The generated production config must include both backend bases:
   `ACCOUNTAV_API_BASE_URL` for shared account/platform flows and
   `TUNEAV_API_BASE_URL` for `/v1/tune/*` product flows. Do not upload a new
   build if `TUNEAV_API_BASE_URL` is missing, inherited, local, development, or
   preview-shaped.

3. To create and upload a signed Apple Silicon-only App Store Connect build, run:

   ```bash
   vp run macos:release:archive -- --skip-preflight
   vp run macos:release:upload -- --archive "<printed .xcarchive path>" --upload --skip-preflight
   ```

   The workflow verifies the archive bundle identifier (`com.avalsys.tuneav`
   for App Store Connect), stable Account AV keychain service
   (`com.avalsys.tuneav.account.v2`), Account AV keychain access group
   (`935PM55U6R.com.avalsys.tuneav`) in both Info.plist and signed
   entitlements, signing class, team ID, and `arm64` architecture before upload.
   Treat any archive that uses the legacy service
   `com.avalsys.tuneav.account` as invalid, even if App Store Connect accepts
   the upload. That service can make Clerk's macOS legacy migration fallback
   read old login-keychain items and show repeated Keychain password prompts.

   After every macOS TestFlight upload, open App Store Connect and confirm the
   build has completed Apple's processing/encoding step before expecting it to
   appear in TestFlight. An upload that is only delivered or still processing is
   not yet addable to TestFlight groups or App Review.

4. If shared UI changes affect macOS, open `apps/macos/TuneAVMac.xcodeproj` and
   run the `TuneAVMac` scheme locally.

5. Confirm no generated macOS local config or build products are tracked.

6. Confirm macOS sync diagnostics follow the same production policy as iOS:
   missing token or missing base URL states are local availability states, while
   HTTP failures, access mismatches, and unexpected errors remain reportable.

7. Confirm Pro sync on iOS and macOS with the same account:

   - explicitly saved stations sync across devices;
   - saved songs sync only for actively saved song records, not local discovery
     history;
   - station and song feedback stays local to the authoring device and is not
     restored after a fresh install or on another device;
   - one deliberate Pro feedback action may create one backend mutation for
     summaries/recommendations, but creates no feedback snapshot GET, Convex
     invalidation, projection outbox/Queue event, or receiver-side request;
   - Guest and signed-in Free feedback create no backend request;
   - a cold startup or completed sign-in creates no more than one automatic
     full library sync, one realtime session, and one Convex subscription;
   - foreground transitions do not start another automatic full library sync;
   - repeated delivery of one persisted library operation uses the same
     `Idempotency-Key` and creates only one backend revision/invalidation;
   - automatic mutation retries are serialized, stop after five total attempts,
     honor `Retry-After`, and do not retry permanent `4xx` failures;
   - refreshing entitlement state for the same internal account does not
     temporarily downgrade Pro or recreate realtime sync;
   - changing to a different internal account removes the previous account's
     Pro capabilities before the new entitlement response is applied;
   - the first Convex projection after bootstrap does not repeat Cloudflare
     reads for covered favorites, saved discoveries, or account summary;
   - a projection newer than bootstrap coverage refreshes only its affected
     channel/resource, while a missing or invalid source timestamp takes the
     conservative refresh path;
   - after bootstrap completes, observe at least 90 seconds without repeated
     automatic sync or realtime-session creation.

   Feedback upload and listening analytics are not sync and must never be
   described or tested as restored cross-device state.

8. When macOS changes touch Music, Library/Radios, filtering, sync projection,
   or local history state, verify the list source for every mode before archive:
   Music History must use local discovery history even when tuned songs are
   empty; Music Top/Afinadas must use tuned discoveries; Songs/Artists must use
   saved discoveries; Radios Saved, Recents, Afinadas, and Music must each use
   their own station source. Keep focused unit coverage in
   `TuneAVMacSmokeTests` alongside the full `vp run macos:tests` gate.

   When macOS changes touch Avi navigation or player actions, keep Avi
   contextual: the sidebar should not expose a standalone Avi destination, the
   player `More with Avi` control should stay a popover anchored to the player,
   and the native Avi menu should act on the current song or radio context.

9. Before attaching the uploaded build to App Store review, reconcile App Store
   metadata, privacy answers, legal links, subscription text, release notes, and
   Apple Silicon-only platform expectations with
   [app-store-review.md](app-store-review.md).

10. Capture or upload App Store Connect macOS screenshots at an accepted size
   (`1280 x 800`, `1440 x 900`, `2560 x 1600`, or `2880 x 1800`). Local scripted
   screenshot capture on macOS may require Screen Recording permission for the
   terminal or automation host.

   For the first macOS release preview, keep the local App Store screenshot set
   in `docs/app-store/screenshots/macos/`:
   - `01-home.png`
   - `02-search.png`
   - `03-music.png`
   - `04-library.png`
   - `05-profile.png`

   The current preview assets are `1440 x 900` PNGs, flattened to an opaque
   light background, and mirror the accepted iOS first-release story adapted to
   the Mac UI: live radio home, search, music/saved songs, library, and account
   profile. The `docs/app-store/screenshots/` tree is intentionally gitignored
   because screenshots are large release assets; preserve the local files until
   they have been uploaded or intentionally regenerated.

   For the macOS App Store first release baseline `1.0.4 (45)`, the five
   preview v1 screenshots were uploaded to App Store Connect in order and the
   version was approved per 2026-07-02 operator report after validating the
   macOS TestFlight Pro purchase path with the production backend. The latest
   approved macOS maintenance baseline is `1.0.5 (47)` per 2026-07-03 operator
   report. iOS/iPadOS `1.0.6 (45)` was submitted to App Review on 2026-07-03
   per operator report and is pending approval. New macOS TestFlight uploads
   must use a higher marketing version. macOS `1.0.6 (49)` was uploaded to App
   Store Connect and submitted to App Review on 2026-07-03; approval is
   pending. Review submission id:
   `5e5d7cdb-7827-4472-ae9f-f737dd92fb24`. It carries the Music history
   list-source fix, radio-library regression coverage, and contextual macOS Avi
   navigation. The previous macOS `1.0.6 (48)` package was uploaded to App Store
   Connect on 2026-07-03 before the contextual Avi navigation update.

   Latest TestFlight checkpoint, 2026-07-11: iPhone/iPad `1.0.7 (47)` and macOS
   `1.0.7 (56)` from public commit `11fb5d9` completed processing and were
   installed from TestFlight per operator report. The installed macOS bundle
   was independently verified as build `56`; its Pro session survived the
   replacement, an explicit sync returned `Todo al día`, and production traces
   showed bounded reads with no mutation, retry loop, or ongoing polling.
   Physical cross-device propagation with iOS build `47` and one real realtime
   renewal boundary remain release QA gates. Neither build has been submitted
   to App Review by this checkpoint.

   A process-verified macOS build `56` cold launch later exposed two bounded
   efficiency issues: realtime/bootstrap ordering caused one duplicate
   library-read batch, and a persisted listening-analytics row used an end
   reason outside the backend enum, causing one terminal `400` per cold launch
   while that poison batch remained local. The analytics issue was repaired in
   source on 2026-07-13 for both Apple clients: lifecycle reasons now use the
   shared typed backend enum, legacy persisted values are normalized and saved
   canonically, and terminal `4xx` batches are removed from durable storage so
   they cannot be retried after relaunch. Focused iOS coverage proves one
   request and no second request after a simulated relaunch; focused macOS
   cloud-sync coverage proves legacy migration. This repair is not part of
   TestFlight builds `47`/`56`; a later build must still be installed and
   production-smoked. There is still no continuous polling or Convex outbox
   fanout. The duplicate bootstrap read was also repaired in source on
   2026-07-13: iOS now registers its initial library task before starting the
   realtime observer, while macOS schedules a per-user bootstrap barrier before
   opening realtime and makes an early historical projection await that pull.
   A projection received during the pre-bootstrap delay becomes the cursor
   baseline; later generations still trigger normal refreshes. Exact-count iOS
   coverage remains one favorites GET, one saved-discoveries GET, one feedback
   GET, and one summary GET. The macOS cloud-sync suite covers the matching-user
   barrier and later invalidation behavior. This second repair is likewise not
   in TestFlight builds `47`/`56` and still needs a later production smoke.

   TestFlight delivery checkpoint, 2026-07-13: iOS/iPadOS `1.0.7 (48)` and
   macOS `1.0.7 (57)` were archived from product source commit `21faf54`,
   verified with the production release gates, and accepted by App Store
   Connect for processing. The exact archives are
   `.derived-data/release-archives/TuneAV-1.0.7-48-2026-07-13-115655.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-57-2026-07-13-120023.xcarchive`.
   Both uploads ended with `Upload succeeded` and `EXPORT SUCCEEDED`; App Store
   Connect processing and tester availability initially required confirmation.
   The macOS TestFlight app subsequently showed build `57` published on
   2026-07-13 at 12:04 CEST with `Actualizar` available; iOS/iPadOS build `48`
   still requires independent processing/group confirmation. No Worker or
   Convex deployment was part of this delivery. These builds contain the
   terminal analytics-outbox repair and the bounded bootstrap/realtime
   coordination repair described above.

   macOS build `57` installed production smoke, 2026-07-13: the TestFlight
   bundle launched from a terminated process, restored Pro, and remained
   `Todo al día`. The filtered production trace contained exactly one account
   profile read, one access read, one read for each cloud-library resource, one
   realtime-session request, and one feedback read; all returned `200`. No
   listening-analytics request or terminal `400` appeared during launch or the
   delayed observation window, and the realtime projection aggregate remained
   healthy with no incomplete delivery or fanout. This validates both build
   `57` repairs for a cold launch.

   The same smoke found one separate bounded macOS inefficiency: entering the
   account screen refreshed the same internal user through a temporary local
   Free fallback before the confirmed Pro response arrived. That transition
   stopped and restarted realtime and scheduled another complete cloud
   bootstrap. The source repair completed on 2026-07-13 now mirrors iOS: an
   active or temporarily unavailable refresh preserves confirmed capabilities
   while the internal user is unchanged, while a different internal user still
   clears the previous capabilities before its access response is applied.
   The complete macOS test suite passed 57 tests, including regressions for
   same-user preservation, different-user clearing, and temporary provider
   unavailability. This repair is not in TestFlight build `57`; the next macOS
   build must prove that opening the account screen performs only its bounded
   account refresh and does not restart realtime or cloud-library sync. There
   is no periodic polling, analytics `400`, or Convex projection fanout in this
   residual.

   macOS TestFlight delivery checkpoint, 2026-07-13: `1.0.7 (58)` was archived
   with the same-user access-refresh repair from product source commit
   `6d8bc50`, after advancing only the macOS build number. The production
   release preflight and complete macOS suite passed with 57 of 57 tests. The
   exact arm64 archive is
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-58-2026-07-13-130559.xcarchive`;
   its bundle, team, Account AV keychain identifiers, privacy manifest, and
   repaired Sentry dSYM were verified. App Store Connect accepted the exact
   export for processing at 13:08 CEST, ending with `Upload succeeded` and
   `EXPORT SUCCEEDED`. App Store Connect subsequently showed the upload as
   finished, ready to test, and assigned to the internal `Tune AV Test` group.
   TestFlight automatic updates installed `/Applications/Tune AV.app` as build
   `58`; its installed signature is `TestFlight Beta Distribution` for the
   expected team. Its bounded production smoke then passed. A process-verified
   cold launch restored Pro and reached `Todo al día`; the build-58 trace
   contained exactly one account profile read, one access read, one favorites
   read, one saved-discoveries read, one realtime-session request, and one
   feedback read, all `200`. There was no listening-analytics request, terminal
   `400`, duplicate bootstrap, or error. The first account-screen entry
   coincided with one bounded sequence consistent with a delayed Convex
   invalidation (feedback, library, feedback), but created no new realtime
   session and did not repeat. After a quiet baseline, a controlled second
   account-screen entry produced exactly `GET /v1/me` and
   `GET /v1/me/access`, both `200`, with no Tune API traffic. This runtime-proves
   the same-user access-refresh repair. The production realtime projection
   aggregate remained healthy at 286 of 286 delivered, with zero pending,
   incomplete, dead-letter, stale, timed-out, or open-claim rows and one maximum
   enqueue/publish attempt. No Worker, Convex, Account API, Tune API, or
   production-data change was part of the smoke.

   Apple realtime-bootstrap read hardening, 2026-07-13: the build-58 smoke
   confirmed that the bounded `feedback -> library -> feedback` sequence could
   be caused by the initial Convex snapshot arriving after the cloud bootstrap.
   The Apple clients now establish a no-op baseline for a timestamp-less legacy
   initial projection only after both the library and feedback bootstrap have
   succeeded. Timestamped projections and any projection following a failed
   bootstrap retain the conservative refresh behavior. macOS additionally
   preserves the realtime cursor, covered generations, and active session when
   the same Pro user merely pauses and resumes the app; those values are still
   cleared for a different user or a full stop. iOS applies the matching cold
   launch baseline rule. The complete iOS suite passed 355 of 355 tests and the
   complete macOS suite passed 58 of 58 tests. This is client-only hardening:
   no Worker, Convex schema/function, Cloudflare configuration, or production
   data changed. TestFlight build `58` predates this repair, so a later Apple
   build must verify that the delayed initial projection and a same-user
   activation do not repeat covered Cloudflare reads.

   Apple realtime-bootstrap TestFlight delivery checkpoint, 2026-07-13:
   iOS/iPadOS `1.0.7 (49)` and macOS `1.0.7 (59)` were archived from public
   source commit `7cfddd5`, after advancing only their respective build
   numbers. The governed production configuration and both release preflights
   passed before archive creation. The source repair was already covered by
   the complete iOS suite (355 of 355 tests) and complete macOS suite (58 of 58
   tests). The exact archives are
   `.derived-data/release-archives/TuneAV-1.0.7-49-2026-07-13-143841.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-59-2026-07-13-143841.xcarchive`.
   Their version, build, bundle, team, architecture, privacy, Account AV
   keychain identifiers where applicable, and app/Sentry dSYMs were verified.
   App Store Connect accepted the exact iOS export at 14:42 CEST and the exact
   macOS export at 14:43 CEST; both commands ended with `Upload succeeded` and
   `EXPORT SUCCEEDED`. App Store Connect subsequently marked both uploads
   `Finalizado`, made builds `49` and `59` available for testing, and assigned
   them to the internal `Tune AV Test` group. No Worker, Convex, Account API,
   Tune API, Cloudflare configuration, production-data, or App Review change
   was part of this delivery. The iOS/iPadOS installation and bounded
   cross-device production smoke remain pending.

   macOS build-59 production smoke, 2026-07-13: TestFlight installed
   `/Applications/Tune AV.app` as `1.0.7 (59)` with the expected bundle, team,
   and `TestFlight Beta Distribution` signature. The signed-in Pro account
   showed `Todo al día`. A controlled account-screen entry produced exactly
   `GET /v1/me` and `GET /v1/me/access`, both `200`, while Tune API remained
   silent. A same-user background/foreground cycle produced no Account or Tune
   request. One process-verified cold launch then produced exactly one account
   profile read, one access read, one favorites read, one saved-discoveries
   read, one realtime-session request, and one feedback read, all `200`. The
   delayed observation window remained silent: there was no repeated
   `feedback -> library -> feedback` sequence, second realtime session,
   analytics request, polling, or error. The PII-free production projection
   aggregate remained `healthy` at 286 of 286 delivered, with zero incomplete,
   dead-letter, stale, timed-out, errored, or open-claim rows and maximum
   enqueue/publish attempts of one. The total was unchanged, so the smoke
   created no projection fanout. No backend or production-data change was made.

   iOS build-49 production smoke and account-read repair, 2026-07-13: the
   physical TestFlight app restored Pro, synchronized successfully, and every
   observed Account/Tune request returned `200`. Favorites, saved discoveries,
   realtime session, and feedback each used one request, the delayed window was
   quiet, and the PII-free projection aggregate remained healthy and unchanged
   at 286 of 286 delivered. The account bootstrap nevertheless issued four
   profile reads and two access reads. Source analysis mapped them exactly to
   overlapping `RootView`/`ProfileScreen` account refreshes plus two redundant
   profile-summary tasks. The iOS client now shares one in-flight account
   refresh, retains the resolved Account summary in `AccessController`, reuses
   a recent completed refresh on immediate profile entry, and removes direct
   profile-summary networking from `ProfileScreen`. The focused account suite
   passed 50 tests, the complete iOS unit suite passed 358 tests, and the Pro
   Profile UI smoke passed. This is client-only; no Worker, Convex, API,
   configuration, or production-data change was made. Build `49` predates the
   repair, so the next iOS TestFlight build must prove exactly one profile and
   one access read on cold launch before the cross-device mutation matrix.

   iOS account-bootstrap TestFlight delivery checkpoint, 2026-07-13: version
   `1.0.7 (50)` was produced from public source commit `4db8b0a`, with the build
   number advanced by commit `5cfd102`. The governed production release
   preflight passed with zero failures and zero warnings. The exact archive is
   `.derived-data/release-archives/TuneAV-1.0.7-50-2026-07-13-152650.xcarchive`;
   final verification passed for version/build, bundle, team, architecture,
   privacy, and matching app/Sentry dSYMs. App Store Connect accepted the exact
   export at 15:30 CEST, ending with `Upload succeeded` and
   `EXPORT SUCCEEDED`. Apple subsequently marked the upload `Finalizado`, made
   build `50` available for testing, and assigned it to the internal
   `Tune AV Test` group. No backend deployment, production-data mutation, or
   App Review submission was performed.

   iOS build-50 production request-budget proof, 2026-07-13: a physical
   TestFlight cold launch emitted exactly one `GET /v1/me`, one
   `GET /v1/me/access`, one favorites read, one saved-discoveries read, one
   realtime-session creation, one feedback read, and one
   `GET /v1/tune/me/summary?limit=12`; every response was `200`. The summary
   request is the intentional, cached Pro activity bootstrap and its regression
   requires exactly one read. A further 15-second observation window was fully
   quiet, with no retry, polling, repeated realtime session, or cloud-library
   refresh. The PII-free production projection aggregate remained `healthy`
   and unchanged at 286 of 286 delivered, with zero pending, incomplete,
   dead-letter, stale, timed-out, errored, or open-claim rows and maximum
   enqueue/publish attempts of one. This closes the iOS account-bootstrap
   overfetch gate: build `49` used four profile and two access reads, while
   build `50` uses one of each. No backend, configuration, production-data, or
   App Review change was made. The next gate is the deliberate same-account
   iOS/macOS cross-device mutation matrix.

   Cross-device saved-radio proof and macOS receiver request-budget repair,
   2026-07-13: adding one saved radio on physical iOS build `50` created exactly
   one source revision, one D1 outbox projection, and one Convex generation;
   macOS build `59`, launched from a terminated state, restored it. Deleting the
   same radio from iOS created exactly one additional projection, delivered in
   one enqueue and one publish attempt. macOS intentionally pauses Convex while
   inactive and applied the deletion after activation from the latest
   invalidation. The PII-free aggregate advanced only from 286 to 288 delivered
   events and remained healthy, with no retry or incomplete work.

   That receiver trace exposed a separate bounded macOS over-read: one
   `favorites` invalidation performed a full favorites plus saved-discoveries
   pull and then an unrelated feedback read. The client now scopes only a
   single consecutive library generation with a known resource to one exact
   resource GET. Generation gaps, unknown resources, bootstrap, manual sync,
   and concurrent follow-up retain the conservative full path; feedback is
   refreshed only when its own generation advances. Exact-request regressions
   cover both library resources and generation gaps. The complete iOS suite
   passes 360 of 360 tests and the complete macOS suite passes 63 of 63 tests.
   Public config hygiene also passes. This is client-only: no Worker, Convex,
   Account/Tune API, Cloudflare configuration, or production-data change was
   made. macOS TestFlight build `59` predates the repair, so a later build must
   prove that one saved-radio invalidation causes one matching Account API GET
   and no saved-discoveries or feedback read.

   iOS exact-resource receiver parity completed in source on 2026-07-13. The
   iOS App Data service now exposes the same scoped pull, and `LibraryStore`
   uses it only for a known resource on one consecutive generation. It merges
   the remote resource with the untouched local snapshot, updates only that
   resource's coverage, and performs no feedback or summary request. Unknown
   resources still execute the full two-resource refresh. Three exact-request
   regressions passed first, all 37 `LibraryStoreTests` passed next, and the
   complete iOS suite passed 363 tests with zero failures. This is iOS
   client-only; macOS and all backend/runtime configuration remain unchanged.
   Physical iOS build `50` predates this repair, so a later iOS TestFlight build
   must prove one saved-radio invalidation causes one matching resource GET and
   no unrelated library, feedback, or summary read.

   Exact-resource TestFlight delivery checkpoint, 2026-07-13: iOS/iPadOS
   `1.0.7 (51)` and macOS `1.0.7 (60)` were produced from public commit
   `564840e`, which contains the scoped receiver repairs and advances only the
   two Apple build numbers beyond those repairs. Both governed production
   preflights passed with zero failures and zero warnings. The verified archives
   are
   `.derived-data/release-archives/TuneAV-1.0.7-51-2026-07-13-163920.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-60-2026-07-13-164202.xcarchive`.
   Archive checks passed for the intended version/build, bundle, team,
   architecture, privacy manifests, stable macOS Account AV keychain identity,
   and matching app/Sentry dSYMs. Both uploads ended with `Upload succeeded`
   and `EXPORT SUCCEEDED`. App Store Connect then marked both uploads
   `Finalizado`, exposed builds `51` and `60` as `Lista para enviar`, and
   assigned them to the internal `Tune AV Test` group. Generated production
   config and 3.2 GB of task-owned macOS DerivedData were removed; public config
   hygiene passed after cleanup, while both verified archives remain retained
   as evidence. No backend, Cloudflare, Convex, production-data, or App Review
   change was made. TestFlight then installed macOS build `60` automatically
   in `/Applications`; its bundle has the expected `TestFlight Beta
   Distribution` signature and team. The existing account restored as Pro and
   the account screen reported cloud sync `Todo al día` at 16:50 CEST without a
   manual sync or data mutation. The next gate is a physical same-account
   receiver trace:
   one active saved-radio invalidation in each direction must perform exactly
   one favorites GET and no saved-discoveries, feedback, summary, retry, or
   extra realtime-session request.

   Author-device projection coverage repair, 2026-07-13: the physical
   iOS `1.0.7 (51)` add trace showed a successful favorites mutation followed
   by a redundant favorites GET from the same iPhone 171 ms after its D1
   projection was delivered; the Mac then performed the required receiver GET.
   The deletion receiver trace was otherwise exact: one delivered projection,
   one macOS favorites GET after activation, no Tune API request, and the radio
   removed locally. The shared App Data client already decoded the mutation
   response `updatedAt`, revision, and ETag but discarded the timestamp. It now
   returns a mutation receipt, and both Apple models advance only the matching
   resource coverage before consuming realtime. A matching own projection is
   therefore filtered without a GET, while a later projection with a newer
   source timestamp still produces one exact receiver GET. Invalid or absent
   timestamps remain conservative. The complete suites pass 364 iOS and 65
   macOS tests with zero failures. This is client-only; no Worker, API, Convex,
   Cloudflare configuration, or production state changed. Builds `51` and `60`
   predate the repair; later TestFlight builds must prove one mutation request,
   zero source-device GETs, and one exact receiver GET.

   Author-device coverage TestFlight delivery checkpoint, 2026-07-13:
   iOS/iPadOS `1.0.7 (52)` and macOS `1.0.7 (61)` were produced from public
   commit `ea07f95`, which includes the mutation-receipt coverage repair and
   advances only the Apple build numbers beyond it. The iOS production
   preflight passed with zero failures and zero warnings, the Release simulator
   build passed, and the macOS production preflight passed. The retained,
   verified archives are
   `.derived-data/release-archives/TuneAV-1.0.7-52-2026-07-13-173041.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-61-2026-07-13-173326.xcarchive`.
   Archive checks passed for version/build, bundle, team, architecture,
   privacy, stable macOS Account AV keychain identifiers, and matching
   application/Sentry dSYMs. App Store Connect accepted iOS at 17:33 CEST and
   macOS at 17:36 CEST; both release commands ended with `Upload succeeded`
   and `EXPORT SUCCEEDED`. Apple then marked both uploads `Finalizado`, exposed
   builds `52` and `61` as `Lista para enviar`, and assigned them to the
   internal `Tune AV Test` group. Generated production config and 6.5 GB of
   task-owned iOS/macOS DerivedData were removed; public config hygiene passed
   before delivery, while the 131 MB iOS and 123 MB macOS archives remain as
   evidence. No backend, Cloudflare, Convex, production-data, or App Review
   change was made. The next gate is to install both builds and repeat one
   isolated saved-radio mutation with exact source/receiver request counts:
   one mutation, zero author-device App Data GETs for its own projection, one
   receiver favorites GET, and no unrelated read, retry, or extra realtime
   session.

   iOS-to-macOS author-coverage proof, 2026-07-13: physical TestFlight iOS
   `1.0.7 (52)` issued exactly one successful favorites upsert. After its
   projection was delivered, the exact `TuneAV/52` client made zero App Data
   GETs, proving that the mutation receipt suppressed the former author-side
   reread. Activating physical TestFlight macOS `1.0.7 (61)` consumed the
   pending generation with exactly one favorites GET from the exact
   `Tune%20AV/61` client. There was no saved-discoveries GET, feedback GET,
   post-mutation summary, retry, polling, or additional realtime-session
   request. The one Tune summary in the trace completed 18 seconds before the
   mutation as part of the just-updated iPhone launch and is outside the
   mutation window. The PII-free production outbox advanced once from 290 to
   291 delivered projections; the new `library/favorites` event used one
   enqueue and one publish attempt and ended without error, pending work,
   timeout, dead letter, or open claim. No source, Worker, Convex,
   configuration, deployment, or App Review change was made. The reverse
   macOS-to-iOS saved-radio direction remains the next gate.

   macOS-to-iOS author-coverage proof, 2026-07-13: the initial radio add was
   completed before the live tails were ready, so only its single healthy
   delivered projection is claimed. With both tails active and iOS in the
   foreground, deleting the same radio from physical TestFlight macOS
   `1.0.7 (61)` produced exactly one successful favorites delete. The exact
   `Tune%20AV/61` author made zero App Data GETs after its own projection, and
   physical TestFlight iOS `1.0.7 (52)` made exactly one favorites GET from
   `TuneAV/52`. There was no saved-discoveries, feedback, summary, retry,
   polling, or additional realtime-session request, and the delayed window
   remained silent. The deletion advanced the healthy PII-free outbox once
   from 292 to 293 delivered events through one enqueue and one publish
   attempt, without error or incomplete work. Together with the prior
   iOS-to-macOS proof, this closes the saved-radio request budget in both
   directions. No code, Worker, Convex, configuration, deployment, or App
   Review change was made.

   Bidirectional saved-song proof, 2026-07-13: with live tails ready, physical
   iOS `1.0.7 (52)` made exactly one successful `savedDiscoveries` upsert and
   zero author-side App Data GETs. Activating physical macOS `1.0.7 (61)`
   consumed the projection with exactly one `savedDiscoveries` GET. The
   cleanup deletion then proved the reverse direction: one successful
   `savedDiscoveries` delete from macOS, zero author-side GETs, and exactly one
   receiver GET on iOS. Neither mutation produced a favorites or feedback GET,
   post-mutation summary, retry, polling, extra realtime session, or Tune API
   request, and both delayed windows were silent. The PII-free outbox advanced
   exactly twice from 293 to 295 delivered events; both projections used one
   enqueue and one publish attempt with no incomplete or error state. The test
   song was removed at the end. This closes saved-song propagation in both
   Apple directions without a source, Worker, Convex, configuration,
   deployment, or App Review change.

   Product-scope override, 2026-07-13: after reviewing the earlier explicit-save
   decision, current docs, backend request cost, and the inherited feedback-sync
   implementation, the approved forward contract was narrowed to saved stations
   and saved songs only. The feedback directions formerly listed as the next
   matrix gate are cancelled. Builds `52` and `61` are historical TestFlight
   evidence for saved-item sync, but are migration-pending because they still
   bootstrap/restore feedback. The next gate is a later client/backend build
   that removes feedback reads and realtime fanout, updates user-facing copy,
   and proves the focused feedback traffic budget without cross-device restore.

   Source migration completed, 2026-07-13: iOS and macOS no longer bootstrap,
   restore, or realtime-refresh feedback; feedback-only legacy projections are
   ignored; Guest and signed-in Free feedback cannot enter the upload path; and
   one deliberate Pro action retains only its D1 mutation with no projection
   outbox/Queue/Convex event. The five Apple locales now describe Cloud Sync as
   saved radios plus saved songs only. Local verification passed with iOS
   362/362 tests, macOS 62/62 tests, the localization parity audit, backend
   typecheck, Tune API duplicate-module sync, and focused backend architecture
   tests 26/26. This describes the source-verification checkpoint before the
   separately recorded production deployment and replacement delivery below.

   Feedback-migration production and replacement-delivery checkpoint,
   2026-07-13: the compatible Account AV and Tune AV Workers were deployed and
   signed-in Pro save/clear smokes passed through both production domains. The
   bounded feedback outbox stayed unchanged, proving the deliberate feedback
   mutation created no new outbox/Queue/Convex fanout; no historical feedback
   was bulk-deleted. Replacement iOS/iPadOS `1.0.7 (53)` and macOS `1.0.7 (62)`
   were then archived from public commit `515bd93`. Both governed production
   preflights and final archive checks passed, including privacy and matching
   Sentry dSYMs. The retained archives are
   `.derived-data/release-archives/TuneAV-1.0.7-53-2026-07-13-191207.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-62-2026-07-13-191554.xcarchive`.
   App Store Connect accepted iOS at 19:15 CEST and macOS at 19:18 CEST; both
   uploads ended with `Upload succeeded` and `EXPORT SUCCEEDED`. They were not
   submitted to App Review. Apple subsequently marked both uploads complete,
   made builds `53` and `62` ready to test, and assigned them to the internal
   `Tune AV Test` group.

   TestFlight automatically installed macOS build `62`. The installed app
   reported version `1.0.7 (62)`, bundle `com.avalsys.tuneav`, team
   `935PM55U6R`, a `TestFlight Beta Distribution` signature, and Gatekeeper
   acceptance. The existing signed-in Pro account survived the replacement;
   the UI showed the narrowed saved-radio/saved-song copy and `Todo al día`.
   A clean launch observed through short live production tails made exactly one
   `GET /v1/me`, one `GET /v1/me/access`, one favorites GET, one
   saved-discoveries GET, and one realtime-session POST, all `200`. It made no
   feedback GET, summary, retry, or mutation. A single delayed idempotent
   listening-session upload represented playback analytics from before the
   clean launch, not sync. The tails were stopped after the bounded quiet
   window; no historical observability query was used. iOS build `53`
   installation and the remaining focused physical gate remain open.

   Focused macOS build-62 feedback proof, 2026-07-13: one deliberate Pro
   `not_for_me` selection produced exactly one successful station-feedback PUT.
   No feedback GET, summary, retry, realtime request, second write, or outbox
   event followed during the bounded quiet window. Pressing the visible clear
   control removed the local selection but its single PUT returned `400`.
   Root cause is shared by iOS and macOS: synthesized `Encodable` omits the
   optional `feedback` key for `nil`, while the strict backend schema requires
   `"feedback": null`. The permanent `400` was not retried. The uniquely
   identified temporary D1 row was then removed with one exact constrained
   cleanup; a verification read returned zero rows for that station. The
   feedback projection outbox stayed at four rows with latest timestamp
   `2026-07-10T10:40:38.112Z`. Do not select builds `53`/`62` for App Review
   until explicit-null station and track clear encoding is fixed and covered on
   both Apple clients, then re-proved with bounded live tails.

   Apple feedback-clear source repair, 2026-07-13: both clients now use custom
   request encoding for station and track feedback, preserving normal string
   values and emitting a present `"feedback": null` for clears. The iOS
   regression exercises the real service request path and asserts both JSON
   bodies; the macOS regression asserts both request models. The complete iOS
   unit suite passed 363 of 363 tests, the complete macOS suite passed 63 of 63
   tests, and public configuration hygiene passed. This was a client-only
   source repair with no Worker, Convex, production configuration, production
   data, or App Review change. Builds `53`/`62` predate it and remain blocked
   from review until later TestFlight builds pass a bounded save/clear trace.

   Apple feedback-clear repaired-candidate delivery, 2026-07-13: public source
   commit `efc9515` advanced iOS/iPadOS to `1.0.7 (54)` and macOS to `1.0.7
   (63)` on top of explicit-null repair commit `51aa48a`. Both production
   preflights passed with zero failures and zero warnings, and the iOS Release
   simulator gate passed. Final archive checks passed for bundle, version,
   build, team, privacy, architecture, and matching application/Sentry dSYMs.
   The retained archives are
   `.derived-data/release-archives/TuneAV-1.0.7-54-2026-07-13-205426.xcarchive`
   and
   `.derived-data/macos-release-archives/TuneAVMac-1.0.7-63-2026-07-13-205902.xcarchive`.
   App Store Connect accepted iOS at 20:57 CEST and macOS at 21:02 CEST; both
   exact uploads ended with `Upload succeeded` and `EXPORT SUCCEEDED` and began
   processing. The App Store Connect browser session expired before completed
   processing or internal `Tune AV Test` assignment could be confirmed. Do not
   treat either build as installable, test-ready, or review-eligible until that
   confirmation exists. Neither was submitted to App Review and no backend,
   Convex, production configuration, or production data changed. After
   availability is confirmed, repeat the bounded Pro save/clear trace and keep
   physical iOS proof as an independent gate.

   Renewal observation completed, 2026-07-12: the same process-verified macOS
   build `56` instance remained alive and the Mac did not sleep during the
   expected window. Tune AV production Convex recorded one new realtime session
   at 20:56:08 CEST, inside the predicted 20:51-21:06 CEST window, with expiry
   advanced exactly 12 hours. The surviving Pro UI remained `Todo al día`, its
   library-sync activity stayed at 10:06, and the production projection outbox
   remained healthy at 286 of 286 delivered with no incomplete, errored,
   dead-letter, stale, timeout, or open-claim rows. This closes the real macOS
   renewal gate without a library bootstrap or Convex projection fanout. The
   physical same-account iOS build `47` <-> macOS build `56` propagation matrix
   remains the final cross-device QA gate. No product change or App Review
   submission was part of this observation.

## Convex Owner-Account Replacement Candidates

Subscription-reconciliation delivery checkpoint, 2026-08-01: iOS/iPadOS
`1.0.8 (57)` and macOS `1.0.8 (65)` were produced from public source
`126d989`, including bounded purchase/restore reconciliation from `b9b3cd8`.
Both governed archive and upload flows passed; App Store Connect accepted the
uploads and reported Apple processing. Processing completion and internal
tester-group availability remain unconfirmed, so neither build is yet treated
as TestFlight-ready. No App Review submission, purchase, backend deployment,
production-data mutation, or Infisical mutation was performed. The exact
retained archives are
`.derived-data/release-archives/TuneAV-1.0.8-57-2026-08-01-003627.xcarchive`
and
`.derived-data/macos-release-archives/TuneAVMac-1.0.8-65-2026-08-01-004014.xcarchive`.
Apple rejected the earlier iOS `1.0.7 (57)` attempt because that approved train
is closed; it was not accepted as a TestFlight build and its rejected archive
was removed.

Delivery checkpoint, 2026-07-29: iOS/iPadOS `1.0.7 (56)` and macOS `1.0.7
(64)` are the paired Apple candidates configured for the current production
Convex deployment. The iOS archive was built from public commit `ba140ef`,
passed production/archive gates, was accepted on physical iPhone and iPad, and
is `Ready to Submit` in the internal `Tune AV Test` group. The macOS archive was
built from public commit `d0d4993`; its complete 63-test suite and production,
archive, privacy, signing, arm64, keychain, and matching dSYM gates passed. The
owner accepted the exact archived Mac app locally. Its retained archive is
`.derived-data/macos-release-archives/TuneAVMac-1.0.7-64-2026-07-29-151414.xcarchive`.
The exact upload completed at 15:26 Europe/Madrid with `Upload succeeded` and
`EXPORT SUCCEEDED`; App Store Connect then listed build 64 as `Ready to Submit`
in `Tune AV Test`.

App Store preparation checkpoint later on 2026-07-29: the iOS `1.0.7` version
was created with build 56, manual release, and narrowed-contract release notes
in English (UK), German, Catalan, Spanish (Spain), and French (France). The
global age-rating questionnaire now records no social-media capability and
still calculates 4+. The owner submitted iOS and App Store Connect reports
`Pending Review`. The macOS `1.0.7` version was then prepared with build 64,
manual release, the inherited five screenshots, and the same five localized
release notes. The owner subsequently submitted macOS, and App Store Connect
also reported `Pending Review` at that checkpoint.

Approval checkpoint later on 2026-07-29: the owner confirmed Apple approval of
iOS/iPadOS `1.0.7 (56)` and macOS `1.0.7 (64)`. A signed-in App Store Connect
read independently listed both platform versions as `Ready for Distribution`.
No agent performed a post-approval manual-release action. The previously
distributed iOS `1.0.5` and macOS `1.0.6` clients use the pre-transition
realtime endpoint. Retain that legacy deployment until both replacements are
verified after App Store installation and complete an explicit
adoption/deprecation window.

## Pending Product API Transition Checks

These checks apply to the next Tune AV client release after the product API
split:

- Confirm search, station detail, saved radio feedback, song feedback,
  listening analytics, and realtime session creation use the Tune product
  backend.
- Confirm sign-in, profile, entitlement, subscription, account deletion, app
  linking, terms, privacy, and support flows still use the shared Account
  backend.
- Confirm signed-in Free and Pro flows still behave correctly if the Tune
  product backend is reachable but the shared Account backend is temporarily
  unavailable, and vice versa.
- Keep existing App Store compatibility in mind: older installed clients may
  still use the shared Account backend for Tune product routes until a newer
  build has been published and adopted.

## macOS Listening Analytics Privacy Gate

- `apps/macos/Supporting/PrivacyInfo.xcprivacy` must remain in the app target and
  in the final archive at `Contents/Resources/PrivacyInfo.xcprivacy`.
- Run `node scripts/check-macos-privacy-manifest.mjs` during development and
  `node scripts/check-macos-privacy-manifest.mjs --app <archive app path>` against
  the exact app bundle that will be uploaded.
- The public privacy policy and App Store Connect answers must disclose
  account-linked Product Interaction data used for App Functionality and
  Analytics. This confirmation was completed before enabling production
  uploads.
- Production macOS configuration must resolve
  `TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS=1`. Build the final archive, run the
  complete macOS release preflight, and smoke-test a Pro listening session
  before upload.

## Public Source Release

1. Confirm README, CONTRIBUTING, SUPPORT, SECURITY, and docs describe only public
   client workflows.
2. Confirm build/test/hygiene checks pass.
3. Create a version tag only after the repo is clean.
4. Attach only public artifacts. Do not attach local config, signing output,
   archives containing provisioning profiles, logs with account data, or private
   evidence.
