# Tune AV macOS / iOS Parity

Status: active Mac App Store preparation.

## Distribution Decision

Tune AV macOS will be distributed through the Mac App Store. Subscriptions, when enabled later, should use StoreKit auto-renewable subscriptions shared with the iOS App Store product setup. Apple Pay is not the in-app subscription mechanism for this App Store build.

## Current Parity Snapshot

Implemented in macOS:

- Native SwiftUI macOS shell with `NavigationSplitView`.
- Home, Search, Library, Music, Profile, and Settings surfaces.
- Radio search and playback.
- Favorites, recents, discoveries, saved tracks, and local settings.
- Desktop player inspector and station detail sheets.
- Local limits and contextual upgrade prompts.
- Account AV sign-in/sign-out through the shared `AccountAV` package and Clerk.
- Account AV backend access refresh using the signed-in session token.
- Native account deletion and app-unlink flow matching the iOS safety model.
- Backend app-data sync primitives for Pro/cloud-enabled access.
- Unit coverage for access, limits, sync, persistence, and account deletion behavior.

Known gaps before macOS App Store submission:

- Signed production QA for Account AV provider redirects on macOS is still required after Clerk callback/origin settings are confirmed.
- StoreKit is intentionally absent for v1; keep subscription copy and CTAs non-purchasing until the paid release scope begins.
- Manual macOS QA is still required for playback, sandboxed networking, settings, profile/account flows, and window resizing.
- App Store Connect macOS metadata, screenshots, and privacy answers need their own review, even if they mirror iOS.

## Subscription Architecture For Later

Use one entitlement model across iOS and macOS:

- StoreKit owns purchase/restore UX in App Store clients.
- Account AV backend owns verified entitlement state.
- App Store Server Notifications and server-side reconciliation write provider-backed subscriptions and `user_app_entitlements`.
- Clients render access from `/v1/me/access`.
- Local StoreKit transaction state should not be the final authority for Pro access.

Recommended shared product IDs:

- `com.avalsys.tuneav.pro.monthly`
- `com.avalsys.tuneav.pro.yearly`

Before enabling purchases in either client:

1. Confirm the subscription group and products in App Store Connect.
2. Confirm products are associated with the iOS and macOS platform versions as intended.
3. Add StoreKit purchase, restore, and manage-subscription UI to both clients.
4. Send `appAccountToken` or equivalent mapping data so backend reconciliation can connect Apple transactions to Account AV users.
5. Run sandbox purchase/restore/cancel/expire tests on iOS and macOS.
6. Update App Privacy: Purchases become collected, linked to user, and used for App Functionality.
7. Update App Review notes and metadata so paid Pro claims match shipped behavior.

## App Store Readiness Checklist

- [ ] `bun run macos:config:production` generated private local config.
- [ ] `bun run macos:preflight:production` passes.
- [ ] `xcodebuild ... -scheme TuneAVMac ... test` passes.
- [ ] Release build resolves `PRODUCT_BUNDLE_IDENTIFIER = com.avalsys.tuneav.mac`.
- [ ] `ENABLE_APP_SANDBOX = YES`.
- [ ] `CODE_SIGN_ENTITLEMENTS = Supporting/TuneAVMac.entitlements`.
- [ ] Apple Developer App ID has Mac App Store compatible capabilities.
- [ ] App Review notes explain third-party radio stream availability and ATS if broad ATS remains enabled.
- [ ] Metadata does not claim in-app purchases, restore purchases, or subscription management until StoreKit ships.
- [ ] Mac screenshots are captured from the actual macOS app, not iOS screenshots.
- [ ] Manual QA covers launch, search, playback, pause/resume, app backgrounding, favorites, recents, discoveries, settings, Account AV sign-in/sign-out, account deletion/app unlink, and sandboxed network behavior.
