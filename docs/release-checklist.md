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

Realtime retirement, 2026-11-01: current source contains no Convex client and
no realtime-session request. Installed older builds that still call
`POST /v1/tune/workspace/realtime-sessions` receive `503 realtime_disabled` and
continue with their startup and manual sync paths. The realtime-free builds
exist since `1.0.9` (iOS `58`, macOS `66`, uploaded on 2026-11-01); keep that
compatibility reply while installed builds older than `1.0.9`, including the
App Store approved `1.0.7`, can still call the endpoint.

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
presentation differences. The macOS target builds universal (Apple Silicon and
Intel) archives; the archive gates require the arm64 slice to be present. App
Store Connect macOS builds are uploaded under the
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

3. To create and upload a signed universal (Apple Silicon and Intel) App Store
   Connect build, run:

   ```bash
   vp run macos:release:archive -- --skip-preflight
   vp run macos:release:upload -- --archive "<printed .xcarchive path>" --upload --skip-preflight
   ```

   The workflow verifies the archive bundle identifier (`com.avalsys.tuneav`
   for App Store Connect), stable Account AV keychain service
   (`com.avalsys.tuneav.account.v2`), Account AV keychain access group
   (the team-prefixed `<team id>.com.avalsys.tuneav` set in
   `apps/macos/Config/Release.xcconfig`) in both Info.plist and signed
   entitlements, signing class, team ID, and the `arm64` slice (the universal
   archive also carries `x86_64`) before upload.
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
   universal (Apple Silicon and Intel) platform expectations with
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

## Delivery checkpoints

Public-safe summary only: version and build, source commit, date and scope.
Archive identities, App Store Connect records, tester groups, machines and
upload evidence stay in the private release runbook.

- `1.0.7`, 2026-07-29: iOS/iPadOS `1.0.7 (56)` from public source `ba140ef`
  and macOS `1.0.7 (64)` from public source `d0d4993` were submitted to App
  Review and approved. Earlier `1.0.7` TestFlight candidates (iOS/iPadOS
  `46`-`54`, macOS `55`-`63`, 2026-07-10 to 2026-07-13) were uploaded for
  internal TestFlight testing only and were not submitted to App Review.
- `1.0.8`, 2026-08-01: iOS/iPadOS `1.0.8 (57)` and macOS `1.0.8 (65)` from
  public source `126d989`, with the bounded purchase/restore reconciliation.
  Available to the internal testers only, not submitted to App Review.
- `1.0.9`, 2026-11-01: iOS/iPadOS `1.0.9 (58)` and macOS `1.0.9 (66)` from
  public source `0055b37`, the first train without the Convex realtime layer
  and the first universal (`x86_64 arm64`) macOS archive.
  Available to the internal testers only, not submitted to App Review.
- `1.1.0`, 2026-11-04: iOS/iPadOS `1.1.0 (63)` and macOS `1.1.0 (68)` were
  archived from public source `bad896d` (#121) and uploaded to App Store
  Connect. Both are available to the internal testers only; neither was
  submitted to App Review.
- `1.1.1`, 2026-11-07: iOS/iPadOS `1.1.1 (64)` and macOS `1.1.1 (69)` were
  archived from public source `714bac4` (#131) and uploaded to App Store
  Connect, same scope: internal testers only, no App Review submission. The
  macOS deployment target is 15.0 again since #122, so the Mac app installs on
  macOS 15 and newer. The changes are listed in
  [CHANGELOG.md](../CHANGELOG.md) under `1.1.1 - 2026-11-07`.
- The latest App Store approved versions remain iOS/iPadOS `1.0.7 (56)` and
  macOS `1.0.7 (64)`.
