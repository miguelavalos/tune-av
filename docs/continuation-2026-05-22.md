# Tune AV Continuation

Date: 2026-05-22

This document captures the current handoff point after the Tune AV shared
foundation extraction and App Store readiness pass.

## Current State

- `apps-av` is clean on `main`; latest known merge is shared text-fit hardening.
- `tune-av` is clean on `main`; latest known merge adds checked-in App Store
  upload export options.
- Tune AV remains the source of truth for the first AV app.
- Shared Apple foundation used by Tune now covers app-neutral brand tokens,
  shell, launch/splash support, settings/account surfaces, Avi controls,
  paywall/limit surfaces, and localization text-fit hardening.
- Tune-specific radio, station, playback, discovery, music, recommendation,
  product, entitlement, limit, and copy logic remains in Tune AV.

## Verified On 2026-05-22

- `apps-av/apple`: `swift build` passed.
- Tune AV unit tests: 286 passed, 0 failed.
- Tune AV Home UI smoke: 1 passed, 0 failed.
- Tune AV Debug build/run on `iPhone 17 / iOS 26.5` launched successfully.
- `bun run ios:release:preflight` passed with `0 failure(s), 0 warning(s)`.
- `bun run ios:release:preflight -- --with-archive` passed:
  - unsigned Release archive succeeded;
  - strict archive privacy evidence found app, RevenueCat, and PhoneNumberKit
    privacy manifests;
  - archive app-size gate reported `24.82 MiB`.
- App Store upload export options are checked in at
  `apps/ios/Config/ExportOptionsUpload.plist`.

## Known Environment Note

During simulator launch, iOS showed an Apple ID verification prompt for the
simulator account. It was dismissible with `Ahora no` and did not indicate a Tune
AV crash. Clean simulator account state before taking App Store screenshots or
recording review evidence.

## Pending Before Upload

1. Confirm `CFBundleVersion` is fresh for the next upload. Current checked value
   is build `4` for version `1.0`.
2. Generate or confirm production local config:

   ```bash
   bun run ios:config:prod
   ```

3. Run final release preflight from a clean checkout:

   ```bash
   bun run ios:release:preflight -- --with-archive
   ```

4. Create a signed archive and upload with:

   ```bash
   cd apps/ios
   xcodebuild archive \
     -project TuneAV.xcodeproj \
     -scheme TuneAV \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath "$PWD/build/TuneAV.xcarchive"

   xcodebuild -exportArchive \
     -archivePath "$PWD/build/TuneAV.xcarchive" \
     -exportPath "$PWD/build/AppStore" \
     -exportOptionsPlist "$PWD/Config/ExportOptionsUpload.plist"
   ```

5. If upload fails, capture the exact signing/provisioning/App Store Connect
   error and fix only that blocker.

## Pending After Upload

- Confirm App Store Connect build processing.
- Assign internal TestFlight only after processing finishes.
- Run real-device TestFlight smoke:
  - first launch;
  - Guest playback;
  - sign-in;
  - Profile;
  - Tune AV Pro paywall;
  - restore;
  - account deletion entry;
  - full player;
  - background audio;
  - search;
  - favorites/recents;
  - last-played queue resume.
- Confirm RevenueCat offering/package mapping and webhooks.
- Confirm sandbox purchase/restore/reconciliation.
- Confirm App Privacy answers match the submitted build.
- Confirm third-party SDK privacy/signature evidence.
- Prepare App Review notes, especially the ATS media-stream compatibility note.
- Capture final screenshots from the exact submitted build.

## Recommended Next Step

Attempt the signed archive/export/upload using the checked-in export options. If
local signing credentials are unavailable, stop at the first concrete Xcode
error and resolve the provisioning or account issue before changing app code.
