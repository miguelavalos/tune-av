# Tune AV iOS Installation

This guide is for local simulator runs and for installing `Tune AV` on a connected iOS device.

## Current signing setup

- Xcode project: `apps/ios/TuneAV.xcodeproj`
- scheme: `TuneAV`
- development team: use your own Apple Developer team when signing for device installs
- device bundle identifier: set `TUNEAV_BUNDLE_IDENTIFIER` in `apps/ios/Config/Local.xcconfig` to a development bundle identifier that belongs to your team

## Prerequisites

1. Xcode 26.4.1 or later installed
2. An Apple account available in `Xcode > Settings > Accounts`
3. Command line tools selected from that Xcode
4. `bun` 1.3.13 or later
5. Optional `apps/ios/Config/Local.xcconfig` generated outside git if you need signing or account-platform values

`Local.xcconfig` is gitignored and should be regenerated locally instead of hand-maintained.
Do not copy production values, example secret files, or bootstrap examples into tracked files.

## Switching Dev And Production

Always regenerate the native config outside this repository after switching between development and release operator profiles. Do this before opening Xcode, running the simulator, archiving, or testing signed Account AV flows.

## Run on simulator

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  build
```

You can also open `apps/ios/TuneAV.xcodeproj` in Xcode and run `TuneAV`.

## Install on a connected iOS device

Build for the device:

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'id=<DEVICE_UDID>' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  PRODUCT_BUNDLE_IDENTIFIER=<YOUR_DEV_BUNDLE_ID> \
  CODE_SIGN_STYLE=Automatic \
  build
```

Install the generated app:

```bash
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  ~/Library/Developer/Xcode/DerivedData/TuneAV-*/Build/Products/Debug-iphoneos/TuneAV.app
```

Launch it:

```bash
xcrun devicectl device process launch \
  --device <DEVICE_UDID> \
  <YOUR_DEV_BUNDLE_ID> \
  --activate
```

## First launch trust step

If iOS refuses to open the app after install, trust the developer profile once on the phone:

1. Open `Settings > General > VPN & Device Management`
2. Open the developer app entry that matches the Apple account used for signing
3. Tap `Trust`
4. Open `Tune AV` again from the device home screen

## Known local-dev constraints

- Sign in with Apple is enabled in entitlements. Device provisioning must support that capability for the bundle identifier you use.
- Do not use unsigned compile-only builds to validate Google or Apple sign-in. Clerk native auth stores client and device tokens in Keychain, so auth smoke tests need a signed app with Keychain and Apple Sign In entitlements active.
- If the build hangs in `Resolve Package Graph`, restart Xcode and retry from a clean terminal.
