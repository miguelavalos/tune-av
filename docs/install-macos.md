# Tune AV macOS Setup

Tune AV macOS is an active Mac App Store target. The product direction is one-to-one feature parity with Tune AV iOS, implemented with native macOS UI patterns.

## Requirements

- Xcode with macOS 14 SDK support or newer.
- `bun install` from the repository root.
- Optional `apps/macos/Config/Local.xcconfig` generated outside git if you need signing or account-platform values.

## Local Config

The generated file is `apps/macos/Config/Local.xcconfig`. It is gitignored and must be regenerated locally instead of hand-maintained.

Account AV sign-in uses the shared `AccountAV` package. The macOS bundle registers its bundle identifier as a URL scheme for the auth callback, so matching redirect/callback configuration must exist in the operator account platform before signed manual QA.

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
