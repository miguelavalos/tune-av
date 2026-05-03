# AV Tunesys iOS Installation

This guide is for local simulator runs and for installing `AV Tunesys` on a connected iOS device.

## Current signing setup

- Xcode project: `apps/ios/Avtunesys.xcodeproj`
- scheme: `Avtunesys`
- development team: use your own Apple Developer team when signing for device installs
- device bundle identifier: set `AVTUNESYS_BUNDLE_IDENTIFIER` in `apps/ios/Config/Local.xcconfig` to a development bundle identifier that belongs to your team

## Prerequisites

1. Xcode 26.4.1 or later installed
2. An Apple account available in `Xcode > Settings > Accounts`
3. Command line tools selected from that Xcode
4. `bun` 1.3.13 or later
5. Private Varlock/Infisical bootstrap available locally
6. `apps/ios/Config/Local.xcconfig` generated through Varlock

Generate the local config:

```bash
bun install
bun run ios:config
```

For production/App Store preparation:

```bash
bun run ios:config:production
```

`Local.xcconfig` is gitignored and should be regenerated locally instead of hand-maintained.
Do not copy production values, example secret files, or bootstrap examples into tracked files. See `docs/private-config-and-infisical.md`.

## Run on simulator

```bash
xcodebuild -project apps/ios/Avtunesys.xcodeproj \
  -scheme Avtunesys \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

You can also open `apps/ios/Avtunesys.xcodeproj` in Xcode and run `Avtunesys`.

## Install on a connected iOS device

Build for the device:

```bash
xcodebuild -project apps/ios/Avtunesys.xcodeproj \
  -scheme Avtunesys \
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
  ~/Library/Developer/Xcode/DerivedData/Avtunesys-*/Build/Products/Debug-iphoneos/Avtunesys.app
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
4. Open `AV Tunesys` again from the device home screen

## Known local-dev constraints

- Sign in with Apple is enabled in entitlements. Device provisioning must support that capability for the bundle identifier you use.
- If the build hangs in `Resolve Package Graph`, restart Xcode and retry from a clean terminal.
