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
   bun run config:hygiene
   bun run ios:tests
   ```

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
     -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
     CODE_SIGNING_ALLOWED=NO
   ```

   The simulator destination is an example. Replace it with an installed
   destination from `xcodebuild -showdestinations` when needed.

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
   bun run ios:release:preflight
   bun run ios:release:preflight -- --with-archive
   ```

   The archive preflight validates release config hygiene, sensitive config
   hygiene, platform security, network privacy, strict archive privacy evidence,
   Sentry dSYM repair, and app-size budgets. The executable budget is a local
   regression guard and can be overridden with
   `TUNEAV_IOS_MAX_EXECUTABLE_SIZE_BYTES` when maintainers intentionally change
   the release budget.

8. Use the reproducible archive/upload workflow for iOS App Store releases:

   ```sh
   bun run ios:release:archive -- --build <next-build>
   ```

   The workflow runs release gates, creates the final signed archive, repairs
   `Sentry.framework.dSYM`, and verifies the final `.xcarchive` before any
   upload is allowed. To upload the verified archive, rerun the command printed
   by the workflow with `--upload`.

   For an existing Organizer archive, run:

   ```sh
   bun run ios:archive:check -- --archive "<path-to-TuneAV.xcarchive>"
   ```

   Do not submit an archive that fails the archive check.

## iOS Network And ATS Behavior

Tune AV should not load arbitrary remote HTTP pages in iOS.

Client checks:

- iOS must not downgrade failed HTTPS playback URLs to HTTP.
- Remote web content opened by the in-app browser should use HTTPS.
- Localhost loopback is allowed only for local development.
- Visible UI should not expose internal diagnostics, raw service errors, or
  private configuration values.

## macOS Client Checks

macOS shares the product behavior where practical and uses native macOS
presentation differences. The current macOS release target is Apple
Silicon-only because the current Convex Swift binary dependency does not provide
an Intel macOS slice.

1. Run:

   ```bash
   bun run macos:tests
   ```

2. For release-readiness checks with generated production config present, run:

   ```bash
   bun run macos:release:preflight
   bun run macos:release:preflight -- --with-archive
   ```

   The archive preflight validates release config hygiene, platform security,
   archive creation, and bundle identifier evidence.

3. To create and upload a signed Apple Silicon-only App Store Connect build, run:

   ```bash
   bun run macos:release:archive -- --skip-preflight
   bun run macos:release:upload -- --archive "<printed .xcarchive path>" --upload --skip-preflight
   ```

   The workflow verifies the archive bundle identifier, signing class, team ID,
   and `arm64` architecture before upload.

4. If shared UI changes affect macOS, open `apps/macos/TuneAVMac.xcodeproj` and
   run the `TuneAVMac` scheme locally.

5. Confirm no generated macOS local config or build products are tracked.

## Public Source Release

1. Confirm README, CONTRIBUTING, SUPPORT, SECURITY, and docs describe only public
   client workflows.
2. Confirm build/test/hygiene checks pass.
3. Create a version tag only after the repo is clean.
4. Attach only public artifacts. Do not attach local config, signing output,
   archives containing provisioning profiles, logs with account data, or private
   evidence.
