# Tune AV macOS Setup

Tune AV macOS is an active Mac App Store target. The product direction is one-to-one feature parity with Tune AV iOS, implemented with native macOS UI patterns.

## Requirements

- Xcode with macOS 14 SDK support or newer.
- `bun install` from the repository root.
- Private Infisical/Varlock bootstrap configured outside this public repository.
- Apple Developer App IDs:
  - development: `com.avalsys.tuneav.mac.dev`
  - production: `com.avalsys.tuneav.mac`

## Local Config

Generate local config from the repository root:

```bash
bun run macos:config
```

For production/App Store preparation:

```bash
bun run macos:config:production
bun run macos:preflight:production
```

The generated file is `apps/macos/Config/Local.xcconfig`. It is gitignored and must be regenerated locally instead of hand-maintained.

Account AV sign-in uses the shared `AccountAV` package and Clerk. The macOS bundle registers its bundle identifier as a URL scheme for the auth callback, so the matching Clerk redirect/callback configuration must exist for both development and production bundle IDs before signed manual QA.

## Build And Test

```bash
xcodebuild -project apps/macos/TuneAVMac.xcodeproj \
  -scheme TuneAVMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

## Mac App Store Posture

The macOS target is configured for Mac App Store distribution:

- App Sandbox is enabled.
- Hardened Runtime is enabled.
- The app has outbound network client entitlement for radio streams and Account AV calls.
- Broad ATS remains enabled for third-party radio stream compatibility and must be explained in App Review notes if still present at submission.
- Account deletion is native in the Profile account safety section and uses Account AV eligibility responses before allowing destructive actions.

Do not add StoreKit purchase UI until the subscription release is explicitly in scope. Until then, macOS should consume Account AV access state the same way iOS does.
