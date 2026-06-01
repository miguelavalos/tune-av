# Tune AV Client Checklist

Use this checklist before publishing public repo changes or tagging a public
client source release. It is intentionally limited to repository hygiene,
frontend build/test checks, and local client validation.

Release operations, approval status, private service configuration, entitlement
evidence, and service smoke tests belong outside this public repository.

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

## iOS Network And ATS Behavior

Tune AV should not load arbitrary remote HTTP pages in iOS.

Client checks:

- iOS must not downgrade failed HTTPS playback URLs to HTTP.
- Remote web content opened by the in-app browser should use HTTPS.
- Localhost loopback is allowed only for local development.
- Visible UI should not expose internal diagnostics, raw service errors, or
  private configuration values.

## macOS Client Checks

macOS is secondary in the current public repo, but keep it from regressing when
touching shared Apple code.

1. Run:

   ```bash
   bun run macos:tests
   ```

2. If shared UI changes affect macOS, open `apps/macos/TuneAVMac.xcodeproj` and
   run the `TuneAVMac` scheme locally.

3. Confirm no generated macOS local config or build products are tracked.

## Public Source Release

1. Confirm README, CONTRIBUTING, SUPPORT, SECURITY, and docs describe only public
   client workflows.
2. Confirm build/test/hygiene checks pass.
3. Create a version tag only after the repo is clean.
4. Attach only public artifacts. Do not attach local config, signing output,
   archives containing provisioning profiles, logs with account data, or private
   evidence.
