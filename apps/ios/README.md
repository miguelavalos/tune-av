# Tune AV iOS

SwiftUI iOS app for Tune AV.

Use [`../../docs/pro-sync-scope.md`](../../docs/pro-sync-scope.md) as the
authoritative Pro sync contract and
[`../../docs/ios-current-state.md`](../../docs/ios-current-state.md) as the
wider current public state document for the iOS app.

Current checked-in iOS bundle version: `1.0.6` build `45`.
`Config/ExportOptionsUpload.plist` remains the checked-in export options file
for signed App Store Connect upload workflows.

## Local Config

1. From the repo root, run `pnpm install`.
2. Create `Config/Local.xcconfig` outside git only if your build needs signing or account-platform values.
3. Open `TuneAV.xcodeproj` in Xcode.

The public repository ships with neutral defaults. Local builds can override `TUNEAV_BUNDLE_IDENTIFIER`, `AVALSYS_APPLE_DEVELOPMENT_TEAM`, and the other client-facing values in the local, non-versioned `Config/Local.xcconfig`.

Optional account-connected behavior:

- private configuration can enable signed-in client behavior
- subscription builds can set `TUNEAV_REVENUECAT_PUBLIC_API_KEY`, `TUNEAV_REVENUECAT_OFFERING_ID`, and `TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID` in `Config/Local.xcconfig`
- public docs should avoid non-public operational details, private endpoints, and implementation plans
- support builds can set `SUPPORTAV_BASE_URL` to open the Support AV web surface from Profile; `SUPPORT_EMAIL_TO` remains the fallback contact route

## Current app shape

- shared internal access model with local and signed-in states
- onboarding with `Skip for now`
- local-first shell that works without sign-in
- Home, Search, Avi, Library, Music, and Profile tabs
- music-first station discovery with an explicit all-radio mode
- Profile settings include local external-link preferences: web links open
  inside Tune AV by default and can be changed to the system browser, and
  public-info/lyrics searches use a shared Apps AV search-engine list with
  DuckDuckGo as the default
- Radios and Music use overview screens with lightweight section previews, plus dedicated detail pages for long lists, search, and sorting
- Radio surfaces contain only radios; Music surfaces contain songs and artists
- full player uses a fixed portrait-only layout with large artwork, truncating title text, artwork/text zoom for full metadata, and no mini-player overlay
- optional RevenueCat monthly Pro purchase/restore flow when configured
- Pro paywall can route guests to sign-in first and shows purchase/restore only when subscription config and account state allow it
- Pro cloud sync for explicitly saved stations and explicitly saved songs when Account AV backend config is available
- deliberate Pro feedback actions may upload once for server-side summaries and recommendations, but feedback remains device-local and is not restored across devices; Guest and signed-in Free feedback remains fully local
- recents, discovery history, playback state, and settings remain local-only unless a future public contract says otherwise
- signing in keeps local-first storage behavior unless private configuration enables account-connected behavior
- shared app shell, launch, settings/account, Avi feedback/actions, paywall, and
  text-fit foundations are consumed from `apps-av/apple` where they are
  app-neutral

## Localization

- Development language is English and base strings live in `TuneAV/Resources/en.lproj/Localizable.strings`
- Spanish strings live in `TuneAV/Resources/es.lproj/Localizable.strings`
- All user-visible default copy must be English in `en.lproj` first, then translated in the other locale files
- Do not hardcode user-visible SwiftUI copy in Swift files; use localization keys for `Text`, `Button`, `Label`, navigation titles, sheet titles, empty states, cards, alerts, accessibility labels, and paywall copy
- Swift code, comments, identifiers, and localization keys must be English
- Hardcoded Swift strings are only acceptable for non-visible technical values such as SF Symbols, accessibility identifiers, persistence keys, cache keys, asset names, debug messages, test fixtures, and external provider data shown as returned
- No extra `InfoPlist.strings` are needed right now because the visible app name stays `Tune AV` across locales and the current build has no localized permission prompts
- Dynamic catalog content such as station names, countries, languages, tags, and external metadata is shown as returned by the provider and is not translated by the app
- Before any App Store Review submission, run a localization audit: every shipped `.lproj/Localizable.strings` file must have the same key set as `en.lproj`, every `L10n.string(...)` reference used by the submitted targets must resolve, and Swift/SwiftUI must not contain user-visible hardcoded copy outside the technical exceptions above
- Include iOS, macOS, and shared Apple sources in the audit when shared code or macOS surfaces changed
