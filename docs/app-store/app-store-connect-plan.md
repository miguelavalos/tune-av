# Tune AV App Store Connect Plan

Working plan for Tune AV App Store releases across iOS and macOS.

App Store Connect app:
Use the existing Tune AV App Store Connect record in the private Apple developer account.

Apple references:

- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- App privacy reference: https://developer.apple.com/help/app-store-connect/reference/app-privacy/
- Radio Browser API docs and usage statement: https://api.radio-browser.info/

## Release Positioning

Tune AV is a local-first live radio player focused on fast discovery, clean playback, favorites, recents, and optional Account AV access.

First iOS release scope:

- Live radio discovery and playback.
- Local favorites, recents, and app preferences.
- Optional Account AV sign-in.
- Backend-owned Pro/access state display.
- No in-app subscription purchase, restore purchase, or manage subscription flow in the iOS client.

macOS release direction:

- Mac App Store distribution.
- Native macOS UI with one-to-one product parity against the iOS app.
- Same Account AV entitlement source as iOS.
- No in-app subscription purchase, restore purchase, or manage subscription flow until the later StoreKit subscription release.

Recommended category:

- Primary: Music
- Secondary: Entertainment or Lifestyle

Recommended age rating:

- 4+ if App Store Connect questionnaire confirms no unrestricted web browsing, user-generated content, gambling, medical, mature, or commerce content.
- Re-check this if external station metadata, station artwork, or in-app browser behavior expands.

## Product Page Copy

Name:
Tune AV

Subtitle:
Cleaner live radio

Promotional text:
Listen to live stations from around the world with a fast, focused interface built for easy radio discovery.

Description:
Tune AV brings live radio, quick search, and a local-first listening experience into a clean native iPhone app.

Explore featured stations, search by name, country, language, or tag, save favorites, and quickly return to stations you recently played. The app is designed to make live radio feel simple again: open, choose a station, and start listening.

Key features:

- Live radio stations from around the world.
- Search by station name, country, language, or tags.
- Favorites and recents stored on device.
- Clear now playing screen with metadata when available.
- Optional Account AV sign-in for compatible access states.
- Local-first experience: listening works without creating an account.

Tune AV uses external station directories and public station streams. Availability, quality, metadata, and artwork may vary by station.

Keywords:
radio,live,fm,music,stations,streaming,online,favorites,world,player

What's New:
First iPhone release of Tune AV with live radio, station search, favorites, recents, and a local-first listening experience.

## Screenshot Package

Apple allows 1 to 10 screenshots in JPEG or PNG. For iPhone, prioritize 6.9-inch screenshots. Accepted portrait sizes include 1260 x 2736, 1290 x 2796, and 1320 x 2868 depending on device.

Final English 6.9-inch upload-ready screenshots captured from iPhone 17 Pro Max simulator:

- `docs/app-store/screenshots/en/pro-max/01-home.png`
- `docs/app-store/screenshots/en/pro-max/02-search.png`
- `docs/app-store/screenshots/en/pro-max/03-music.png`
- `docs/app-store/screenshots/en/pro-max/04-library.png`
- `docs/app-store/screenshots/en/pro-max/05-profile.png`

These files are 1320 x 2868 PNGs, which is an accepted 6.9-inch portrait size in Apple's screenshot specification.

Recommended screenshot order:

1. Home: featured live stations and quick playback.
2. Search: station discovery by station, country, language, or genre.
3. Music: songs/artists discovered while listening.
4. Library: favorites and recents in one place.
5. Profile: local-first account and app settings.

Screenshot requirements:

- Avoid showing personal accounts, private emails, tokens, or non-public backend URLs.
- Prefer real app UI over over-designed marketing frames unless the text overlay materially improves clarity.
- Keep all claims accurate: no paid subscription CTA until purchase flows ship.
- Use the English screenshot set for the English App Store locale.

## Privacy Nutrition Label Draft

This must be confirmed against production SDKs, backend logging, analytics, and Account AV behavior before submission.

Likely data types if Account AV sign-in is enabled:

- Contact Info: email address, if collected by Account AV/Clerk for sign-in.
- Identifiers: user ID/account ID, if Account AV links access state to an account.
- User Content: favorites, recents, or library data only if cloud sync is enabled for the shipped build.
- Usage Data: only if production analytics, diagnostics, or backend event logging collect listening/search/app usage.
- Diagnostics: only if crash reporting or diagnostic tooling is enabled.

Likely not collected by the iOS app itself unless added later:

- Location.
- Contacts.
- Photos or videos.
- Health and fitness.
- Financial information.
- Purchases, because the first iOS release does not sell subscriptions from the client.

Tracking:

- Select No unless the app or third-party SDKs track users across apps/websites owned by other companies for advertising or data-broker purposes.

Data linked to user:

- Mark account email/account identifier as linked if Account AV or Clerk stores it against the user account.
- Mark local-only favorites/recents as not collected if they remain only on device.
- Mark cloud-synced library data as linked if Account AV sync stores it under the account.

Required URLs:

- Privacy Policy URL: production public URL from `TUNEAV_PRIVACY_URL`.
- Support URL: preferably a public support page, not only `mailto:`.
- Terms URL: production public URL from `TUNEAV_TERMS_URL`.
- Account deletion URL: https://tune-av.avalsys.com/delete-account
- In-app deletion path: Profile > Account safety > Delete Apps AV account opens the native Account AV deletion flow. The public URL remains the support/store-console entry point.

## App Review Notes Draft

Tune AV is a live radio player. It discovers public radio stations through external station metadata providers and plays streams hosted by third-party radio stations.

For Guideline 5.2.3 / third-party audio review, attach or paste:

- `docs/app-store/app-review-5.2.3-response.md`

The app works in local mode without account creation. Account AV sign-in is optional and is used only for compatible account/access states. Account deletion starts in-app from Profile > Account safety > Delete Apps AV account. Account AV is shared across Apps AV products, so deletion may be blocked until linked Apps AV products, active Pro access, or active provider subscription state are resolved. This first release does not sell subscriptions or include App Store purchase/restore flows in the iOS client.

If App Review needs a test account, provide a non-personal review account here:

- Email:
- Password or sign-in method:
- Expected access state:

Networking note:

Some public radio streams may use non-HTTPS stream URLs. If `NSAllowsArbitraryLoads` remains enabled, explain that it is used for compatibility with live radio station streams not controlled by Tune AV.

Background audio note:

Tune AV uses the audio background mode so playback can continue while the device is locked or the app is in the background.

## Required App Store Connect Fields

App Information:

- App name: Tune AV
- Subtitle: use localized subtitle above.
- Category: Music.
- Content rights: confirm the app accesses/streams third-party radio content and does not claim ownership of station content.
- Age rating: complete questionnaire conservatively.

Pricing and availability:

- Recommended first release price: Free.
- Disable in-app purchases for this version.
- Confirm country availability based on legal/support readiness.

App Privacy:

- Add Privacy Policy URL.
- Complete data collection answers based on actual production Account AV/Clerk/cloud sync behavior.
- Confirm no tracking unless production SDKs prove otherwise.

Version Information:

- Screenshots for iPhone 6.9-inch display.
- Promotional text.
- Description.
- Keywords.
- Support URL.
- Marketing URL, optional.
- Version number matching Xcode build.
- Copyright.
- App Review notes and optional demo account.

Build:

- Upload TestFlight build from production bundle identifier.
- Confirm signing/capabilities match shipped features.
- Confirm no client IAP capability unless a future purchase flow ships.

macOS-specific build posture:

- Production bundle identifier: `com.avalsys.tuneav.mac`.
- Category: Music.
- App Sandbox enabled.
- Outbound network client entitlement enabled for station streams, artwork, and Account AV.
- Mac App Store screenshots and metadata must be captured from the macOS app.
- App Review notes should mention that the app plays third-party radio streams and may require broad ATS compatibility for non-HTTPS streams.

## Future Subscriptions

When paid Pro moves into scope, use StoreKit auto-renewable subscriptions for both iOS and macOS App Store builds. The clients should provide purchase, restore, and manage-subscription UI, while Account AV remains the entitlement authority after App Store Server Notification and server-side reconciliation.

Do not use Apple Pay or web billing for digital Pro subscription purchase inside the Mac App Store build.

## Production Readiness Tasks

1. Confirm production bundle identifier and Apple Developer Team.
2. Generate private production `Local.xcconfig` from Infisical.
3. Archive a device/App Store build and upload to TestFlight.
4. Smoke test on a physical iPhone:
   - Cold launch.
   - First-run local mode.
   - Station search.
   - Playback start/stop.
   - Background playback.
   - Lock screen controls.
   - Favorites and recents persistence.
   - Account sign-in/sign-out.
   - Weak network and stream failure states.
5. Create final screenshot package.
6. Fill App Store Connect metadata.
7. Fill privacy nutrition label.
8. Add App Review notes and demo account if account flows are visible.
9. Submit for review.
