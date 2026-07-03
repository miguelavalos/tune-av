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

   - saved stations and station feedback sync across devices;
   - saved songs sync only for actively saved song records, not local discovery
     history;
   - song feedback sync restores from backend feedback rows with title/artist
     metadata, even when the song is not present in local discovery history;
   - song feedback sync survives tracks with spaces or punctuation in their
     canonical `trackKey`;
   - old URL-encoded local song feedback keys are migrated on launch and do not
     produce duplicate or invisible feedback states.

   Signed-in Free accounts can upload station and song feedback for product data
   and recommendations, but only Pro accounts should restore feedback across
   devices as a user-facing sync feature.

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
   must use a higher marketing version;
   the checked-in next macOS candidate is `1.0.6 (49)` with the Music history
   list-source fix, radio-library regression coverage, and contextual macOS Avi
   navigation. The previous macOS `1.0.6 (48)` package was uploaded to App
   Store Connect on 2026-07-03 before the contextual Avi navigation update.

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

## Public Source Release

1. Confirm README, CONTRIBUTING, SUPPORT, SECURITY, and docs describe only public
   client workflows.
2. Confirm build/test/hygiene checks pass.
3. Create a version tag only after the repo is clean.
4. Attach only public artifacts. Do not attach local config, signing output,
   archives containing provisioning profiles, logs with account data, or private
   evidence.
