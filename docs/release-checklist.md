# Tune AV Release Checklist

Use this checklist before creating a public GitHub release or Apple-platform
archive from the public Tune AV repository.

## Repository Hygiene

Current status on 2026-05-22: tracked repository hygiene is clean after the
shared foundation and App Store upload-preparation PRs. The only checked-in
release operation file is `apps/ios/Config/ExportOptionsUpload.plist`;
generated local config, archives, signed outputs, and evidence artifacts remain
ignored. If `apps/ios/Config/Local.xcconfig` exists from release checks, treat
it as generated local state and remove/regenerate it before public hygiene
checks or publishing public artifacts.

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
5. Confirm public docs do not contain private email addresses, personal account names, local backend URLs, provider secrets, runbooks, or non-public operational/planning details. The production Apple team ID is intentionally present only in checked-in Xcode/export configuration that must match the public app bundle.

## Build Verification

Latest local evidence, dated 2026-05-22:

- `apps-av/apple`: `swift build` passed.
- `TuneAVTests`: 286 tests passed on `iPhone 17 / iOS 26.5`.
- `HomeUITests/testTogglingFavoriteKeepsHomeInteractive`: passed on `iPhone 17
  / iOS 26.5`.
- `bun run ios:release:preflight`: passed.
- `bun run ios:release:preflight -- --with-archive`: unsigned Release archive
  succeeded; strict archive privacy evidence passed; app-size gate reported
  `24.82 MiB`.

1. Confirm the local archive toolchain matches Apple's current upload gate. For
   App Store uploads created on or after 2026-04-28, build with Xcode 26 and
   the iOS 26 SDK or later.

2. Generate the production iOS local config before release checks:

   ```bash
   bun run ios:config:prod
   ```

   `apps/ios/Config/Local.xcconfig` is generated output. It must remain
   ignored, mode `600`, and uncommitted.

3. Run the standard iOS release preflight:

   ```bash
   bun run ios:release:preflight
   ```

   This must pass with `0 failure(s), 0 warning(s)` in the release privacy gate.
   It verifies production runtime config hygiene, network privacy logging, legal
   URL reachability, App Privacy-relevant SDK inventory, and privacy manifests
   found from available build evidence.

   CI and archive preflight enforce the iOS app bundle size budget through
   `scripts/report-ios-app-size.sh`. The default maximum is 150 MiB for the
   full app, with additional section budgets for executable, `Assets.car`,
   `Frameworks`, and `PlugIns`. Override `TUNEAV_IOS_MAX_APP_SIZE_BYTES` or the
   matching `TUNEAV_IOS_MAX_*_SIZE_BYTES` variable only when a release owner
   accepts and documents the size increase.

   `bun run ios:ci` also runs the launch performance UI smoke through
   `scripts/smoke-ios-launch-performance.sh`. The default launch-ready budget is
   10,000 ms and can be tightened with `TUNEAV_IOS_MAX_LAUNCH_READY_MS` once CI
   has enough stable history for a lower threshold.

4. Generate the iOS Xcode project when `apps/ios/project.yml` changes:

   ```bash
   cd apps/ios && xcodegen generate
   ```

5. Run iOS unit tests:

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

6. Run targeted UI tests when the release changes shell navigation, limits,
   playback queue, search, Profile, purchase/restore, account deletion, or
   discovery behavior.

7. Before App Store submission, run the archive evidence preflight from a clean
   production config:

   ```bash
   bun run ios:release:preflight -- --with-archive
   ```

   If an archive was already created by Xcode Organizer or CI, validate that
   exact archive instead:

   ```bash
   bun run ios:release:preflight -- --archive /path/to/TuneAV.xcarchive
   ```

   The strict archive gate must use `--require-archive` internally and must list
   `PrivacyInfo.xcprivacy` files from the submitted `.xcarchive`, not only from
   generic DerivedData. It must also write an app-size report for the archived
   `TuneAV.app` and stay within the configured size budget.

8. When the user asks for a TestFlight build, create the signed App Store
   archive in Xcode's Organizer archive directory, not only under the repository
   `build/` directory. Use a fresh build number for each upload and name the
   archive path with the build number so it is easy to identify locally:

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   archive_date="$(date +%Y-%m-%d)"
   archive_path="$HOME/Library/Developer/Xcode/Archives/$archive_date/TuneAV-v<BUILD_NUMBER>.xcarchive"
   mkdir -p "$(dirname "$archive_path")"

   xcodebuild archive \
     -project apps/ios/TuneAV.xcodeproj \
     -scheme TuneAV \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath "$archive_path"
   ```

   This location makes the archive visible in Xcode Organizer. If an archive is
   created elsewhere for a one-off reason, copy or recreate it under
   `~/Library/Developer/Xcode/Archives/<YYYY-MM-DD>/` before reporting the build
   as ready.

9. After the archive succeeds, ask the user before uploading. The question must
   be explicit and short:

   ```text
   Archive listo en Xcode Organizer. ¿Lo subes tú manualmente o lo subo yo ahora?
   ```

   Do not auto-upload unless the user clearly asks for automatic upload in that
   turn. If the user chooses manual upload, stop after validating the archive and
   give the archive path. If the user chooses automatic upload, upload with the
   checked-in export options:

   ```bash
   cd "$(git rev-parse --show-toplevel)"

   xcodebuild -exportArchive \
     -archivePath "$archive_path" \
     -exportPath "$PWD/build/AppStore-v<BUILD_NUMBER>" \
     -exportOptionsPlist "$PWD/apps/ios/Config/ExportOptionsUpload.plist" \
     -allowProvisioningUpdates
   ```

   The export options use App Store Connect upload destination, automatic
   signing, the production team ID, symbol upload, and no automatic version/build
   mutation.

10. For CI evidence, run the manual GitHub Actions workflow
   `iOS Archive Privacy Evidence`. Keep the uploaded
   `ios-archive-privacy-evidence` artifact with the release record.

## App Review Readiness

Before creating the archive for review:

1. Confirm the submitted build is iPhone-only and uses the intended orientation
   policy.
2. Confirm App Privacy answers match the submitted build, including purchases,
   optional account data, cloud sync, and listening analytics when enabled.
3. Confirm third-party SDK privacy manifests and signatures are present where
   Apple requires them, especially for subscription, account, analytics, or
   phone/auth dependencies.
4. Confirm the release privacy gate reports:
   - production bundle identifier `com.avalsys.tuneav`;
   - listening analytics uploads enabled for production;
   - reachable privacy, terms, delete-account, open-source, and support URLs;
   - RevenueCat, Clerk, PhoneNumberKit, and Nuke inventory status;
   - archive-level `PrivacyInfo.xcprivacy` evidence when submitting to App
     Store.
5. Smoke-test Guest playback, sign-in, Profile, Tune AV Pro paywall, restore,
   account deletion, full player, background audio, search, favorites, recents,
   and last-played queue resume.
6. Recreate screenshots from the exact build attached to App Store Connect after
   any meaningful UI, localization, entitlement, or paywall change.

## App Transport Security

Tune AV does not allow arbitrary remote HTTP loads in iOS. Stream compatibility
is controlled from the backend:

- Backend station search must upgrade HTTP stream URLs to verified HTTPS when
  the HTTPS equivalent is playable.
- HTTP-only streams must not be returned to iOS as playable stations.
- iOS must not retry failed HTTPS streams by downgrading to HTTP.
- Account AV, Support AV, legal, open-source, and stream URLs returned to iOS
  must resolve to HTTPS except localhost loopback during development.
- The in-app browser must reject remote HTTP pages; use HTTPS for web content.

Suggested App Review note:

```text
Tune AV plays public live radio streams from broadcaster-operated domains. The
Tune AV backend validates stream URLs before they are shown in the iOS app and
only returns HTTPS-playable streams to iOS. HTTP-only broadcaster streams are not
treated as playable in the App Store build. Account, subscription, support,
legal, backend API, and stream playback traffic in iOS remains HTTPS-only.
```

## Public Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe only public workflows.
3. Create a version tag only after build, tests, and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.

## Private Operations

Store portal plans, provider setup, signing steps, production config, service
smoke tests, implementation plans, and review-response material belong outside
this public repository.

## Local Keychain Debugging

When validating Tune AV macOS on a release owner's machine:

1. Never run global Keychain inspection such as `security dump-keychain`.
2. Never enumerate generic passwords broadly just to "see what exists".
3. Only operate on exact Tune AV / Clerk entries when cleanup is required.
4. If a Keychain prompt names the `security` CLI, treat it as a debugging-side
   effect, not as product evidence by itself.

For Tune AV macOS, the allowed targeted Clerk cleanup keys are:

- service `com.avalsys.tuneav.mac` or `com.avalsys.tuneav.mac.dev`
- accounts `cachedClient`, `cachedClientServerDate`, `cachedEnvironment`,
  `clerkDeviceToken`, `clerkDeviceTokenSynced`, `AttestKeyId`

Reason:

- broad Keychain inspection on a real Mac can trigger prompts for unrelated
  credentials such as GitHub, Raycast, browser data, scoped bookmarks, and
  other non-Tune AV secrets;
- that behavior is diagnostic noise and must not be confused with Tune AV's
  own runtime access pattern.

Before App Review, the private release owner must separately confirm App Store
Connect build processing, internal-only TestFlight assignment, live subscription
availability, RevenueCat mapping/webhooks, real-device TestFlight smoke, sandbox
purchase/restore/reconciliation, SDK privacy/signature evidence, App Privacy
answers, review notes, and submitted-build screenshots.

## macOS Distribution Preparation

Use this section when preparing Tune AV macOS for real distribution, even if the
current milestone is still local-only QA.

### Release Hygiene

1. Run `bun install`.
2. Run the public hygiene check:

   ```bash
   bun run config:hygiene
   ```

3. Confirm no generated config files are present in tracked git state:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
4. Confirm no exported certificates, provisioning profiles, notarization logs,
   stapled `.app` bundles, `.pkg` installers, or local archive artifacts are
   present in tracked files.

### Preflight

1. Regenerate or refresh `apps/macos/Config/Local.xcconfig` from private config.
2. Confirm the file stays ignored and local-only.
3. Restrict permissions:

   ```bash
   chmod 600 apps/macos/Config/Local.xcconfig
   ```

4. Run the macOS release preflight:

   ```bash
   bun run macos:release:preflight
   ```

5. Before the first real distribution attempt, run the archive-inclusive
   preflight:

   ```bash
   bun run macos:release:preflight -- --with-archive
   ```

   This archive is intentionally unsigned. Its purpose is to catch bundle,
   archive-layout, and release-config regressions before Organizer signing.

### Local Final Build For Your Own Mac

If the goal is only a final build for your own Mac:

1. Open `apps/macos/TuneAVMac.xcodeproj` in Xcode.
2. Use the `TuneAVMac` scheme with `Release`.
3. Use your Apple team with automatic signing.
4. Prefer `Apple Development` over `Sign to Run Locally`.
5. Archive in Xcode Organizer and validate that the app launches on your Mac.

That path is sufficient for serious local QA, but it is not the same thing as a
distribution build for other machines.

### Distribution Archive

When macOS distribution is actually in scope:

1. Create the signed archive in Xcode Organizer with the `TuneAVMac` scheme.
2. Confirm the archive bundle identifier is `com.avalsys.tuneav.mac`.
3. Confirm the archive is signed with a real Apple certificate, not ad-hoc
   signing and not `Sign to Run Locally`.
4. Export with the distribution identity required by the intended channel.
5. If the app is meant to run outside your own Mac or outside Organizer,
   notarize the exported artifact, staple the notarization ticket, and validate
   the final exported app from private release tooling, not from this public
   repository.
6. Only call the build distribution-ready after the exported app passes launch
   and policy validation on a clean machine or clean user context.
