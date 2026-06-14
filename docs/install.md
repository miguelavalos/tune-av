# Tune AV Installation

This guide is for local simulator runs, connected iOS device installs, and the
macOS client target.

## iOS

### Local Setup

1. Install dependencies:

   ```bash
   bun install
   ```

2. Open `apps/ios/TuneAV.xcodeproj` in Xcode.
3. Select the `TuneAV` scheme.
4. Run on an installed iOS Simulator.

The tracked debug configuration uses neutral defaults. If a local build needs
machine-specific runtime values, generate `apps/ios/Config/Local.xcconfig`
outside git.

### Guarded Device Install

Use the guarded installer for connected iPhone testing:

```bash
bun run ios:install:dev
```

The installer regenerates local config, validates effective Xcode settings,
builds into an environment-specific DerivedData folder, installs the compiled
`.app` on the connected iPhone, and launches the resolved bundle identifier.

Use `-- --device <UDID>` when more than one physical iPhone is connected.

### Local Configuration

`Local.xcconfig` is generated output. Do not edit it by hand, do not commit it,
and regenerate it after switching local runtime profiles.

Before changing runtime configuration scripts, read
[public-config-policy.md](public-config-policy.md).

### Prerequisites

1. Xcode 26.4.1 or later installed.
2. Command line tools selected from that Xcode.
3. `bun` 1.3.13 or later.
4. An Apple account in Xcode if testing on a physical device.

Do not copy production values, example secret files, bootstrap examples, or
machine-specific config into tracked files.

### Run On Simulator

Build the simulator app:

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -derivedDataPath /tmp/TuneAV-sim \
  build
```

Install and launch the generated bundle:

```bash
xcrun simctl install booted /tmp/TuneAV-sim/Build/Products/Debug-iphonesimulator/TuneAV.app
xcrun simctl launch booted com.avalsys.tuneav
```

You can also run the `TuneAV` scheme directly from Xcode.

### Manual Install On A Connected iOS Device

Manual installation is only for debugging the installer itself. Prefer
`bun run ios:install:dev` for normal device work.

Build for the device:

```bash
xcodebuild -project apps/ios/TuneAV.xcodeproj \
  -scheme TuneAV \
  -configuration Debug \
  -destination 'id=<DEVICE_UDID>' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
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

### First Launch Trust Step

If iOS refuses to open the app after install, trust the developer profile once
on the phone:

1. Open `Settings > General > VPN & Device Management`.
2. Open the developer app entry that matches the Apple account used for signing.
3. Tap `Trust`.
4. Open `Tune AV` again from the device home screen.

### Known Local-Dev Constraints

- Device provisioning must support the capabilities enabled by the bundle
  identifier you use.
- Avoid unsigned compile-only builds for flows that depend on keychain or
  entitlement behavior.
- macOS signed/TestFlight auth builds must keep both a stable Account AV
  keychain service (`com.avalsys.tuneav.account.v2` for prod,
  `com.avalsys.tuneav.mac.dev.account.v2` for dev) and the matching keychain
  access group (`935PM55U6R.com.avalsys.tuneav` for prod,
  `935PM55U6R.com.avalsys.tuneav.mac.dev` for dev). Do not leave
  `ACCOUNTAV_KEYCHAIN_SERVICE` or `ACCOUNTAV_KEYCHAIN_ACCESS_GROUP` empty or
  inherited.
- Repeated macOS Keychain prompts in TestFlight/App Store builds mean the
  signed app should be treated as invalid until archive signing confirms the
  `keychain-access-groups` entitlement and the app Info.plist group match.
- Critical Tune AV macOS auth rule: do not reuse the legacy Account AV keychain
  service `com.avalsys.tuneav.account`. Clerk's macOS storage uses a
  data-protection primary keychain plus a legacy fallback when an access group
  is configured. If the service matches old login-keychain items, the fallback
  can trigger repeated system Keychain prompts before the user can sign in.
  Tune AV macOS prod must stay on `com.avalsys.tuneav.account.v2`; any future
  service migration must use a new service name and update the archive checker
  before uploading TestFlight.
- If the build hangs in `Resolve Package Graph`, restart Xcode and retry from a
  clean terminal.

## macOS

Tune AV macOS shares product behavior with the iOS client where practical and
uses native macOS UI patterns where the platforms differ. The current macOS
release target is Apple Silicon-only because the current Convex Swift binary
dependency does not provide an Intel macOS slice.

### Requirements

- Xcode with macOS 14 SDK support or newer.
- `bun install` from the repository root.
- Optional `apps/macos/Config/Local.xcconfig` generated outside git if you need
  local runtime values.

### Local Config

The generated file is `apps/macos/Config/Local.xcconfig`. It is gitignored and
must be regenerated locally instead of hand-maintained.

### Build And Test

```bash
xcodebuild -project apps/macos/TuneAVMac.xcodeproj \
  -scheme TuneAVMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

To build and launch the app locally:

```bash
./scripts/build-and-run-macos.sh --verify
```

For release-readiness checks with generated production config present:

```bash
bun run macos:release:preflight
bun run macos:release:preflight -- --with-archive
```

### Local QA

1. Keep generated local config untracked.
2. Build and launch the `TuneAVMac` scheme locally.
3. Validate navigation, playback, settings, local library, and visible error
   states.
4. Confirm no generated config, local archives, or build products are tracked.
