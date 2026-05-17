# Tune AV iOS

SwiftUI iOS app for Tune AV.

## Local Config

1. From the repo root, run `bun install`.
2. Create `Config/Local.xcconfig` outside git only if your build needs signing or account-platform values.
3. Open `TuneAV.xcodeproj` in Xcode.

The public repository ships with neutral defaults. Local builds can override `TUNEAV_BUNDLE_IDENTIFIER`, `AVALSYS_APPLE_DEVELOPMENT_TEAM`, and the other client-facing values in the local, non-versioned `Config/Local.xcconfig`.

Optional account-connected behavior:

- private configuration can enable signed-in client behavior
- subscription builds can set `TUNEAV_REVENUECAT_PUBLIC_API_KEY`, `TUNEAV_REVENUECAT_OFFERING_ID`, and `TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID` in `Config/Local.xcconfig`
- public docs should avoid non-public operational details, private endpoints, and implementation plans

## Current app shape

- shared internal access model with local and signed-in states
- onboarding with `Skip for now`
- local-first shell that works without sign-in
- Radios and Music use overview screens with lightweight section previews, plus dedicated detail pages for long lists, search, and sorting
- Radio surfaces contain only radios; Music surfaces contain songs and artists
- signing in keeps local-first storage behavior unless private configuration enables account-connected behavior

## Localization

- Development language is English and base strings live in `TuneAV/Resources/en.lproj/Localizable.strings`
- Spanish strings live in `TuneAV/Resources/es.lproj/Localizable.strings`
- All user-visible default copy must be English in `en.lproj` first, then translated in the other locale files
- Do not hardcode user-visible SwiftUI copy in Swift files; use localization keys for `Text`, `Button`, `Label`, navigation titles, sheet titles, empty states, cards, alerts, accessibility labels, and paywall copy
- Swift code, comments, identifiers, and localization keys must be English
- Hardcoded Swift strings are only acceptable for non-visible technical values such as SF Symbols, accessibility identifiers, persistence keys, cache keys, asset names, debug messages, test fixtures, and external provider data shown as returned
- No extra `InfoPlist.strings` are needed right now because the visible app name stays `Tune AV` across locales and the current build has no localized permission prompts
- Dynamic catalog content such as station names, countries, languages, tags, and external metadata is shown as returned by the provider and is not translated by the app
