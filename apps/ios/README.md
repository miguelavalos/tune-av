# Tune AV iOS

SwiftUI iOS app for Tune AV.

## Local Config

1. From the repo root, run `bun install`.
2. Create `Config/Local.xcconfig` outside git only if your build needs signing or account-platform values.
4. Open `TuneAV.xcodeproj` in Xcode.

The public repository ships with neutral defaults. Local builds can override `TUNEAV_BUNDLE_IDENTIFIER`, `AVALSYS_APPLE_DEVELOPMENT_TEAM`, and the other client-facing values in the local, non-versioned `Config/Local.xcconfig`.

Optional shared-platform access config:

- set `ACCOUNTAV_API_BASE_URL` in `Config/Local.xcconfig` to enable backend-owned access resolution through Account AV
- when both `ACCOUNTAV_PUBLISHABLE_KEY` and `ACCOUNTAV_API_BASE_URL` are configured, signed-in access refreshes from `GET /v1/me/access`
- Account AV is the source of truth for Pro entitlements in this release

## Current app shape

- shared internal access model with `guest`, `signedInFree`, and `signedInPro`
- current product-facing states are `local mode`, `connected account`, and `pro`
- `Account AV` as the product-facing account layer name
- onboarding with `Skip for now`
- local-first shell that works without sign-in
- signing in does not change storage behavior yet; it only connects an account and can refresh backend-owned access when configured
- premium access remains the only state allowed to grow into backend-backed features

## Localization

- Development language is English and base strings live in `TuneAV/Resources/en.lproj/Localizable.strings`
- Spanish strings live in `TuneAV/Resources/es.lproj/Localizable.strings`
- No extra `InfoPlist.strings` are needed right now because the visible app name stays `Tune AV` across locales and the current build has no localized permission prompts
- Dynamic catalog content such as station names, countries, languages, tags, and external metadata is shown as returned by the provider and is not translated by the app
