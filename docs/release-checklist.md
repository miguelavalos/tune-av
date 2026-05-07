# Release Checklist

Use this checklist before creating the first public GitHub release and before each later tagged release.

## Repository Hygiene

1. Run `bun install`.
2. Run the default hygiene check during local development:

   ```bash
   bun run config:hygiene
   ```

3. Run the strict hygiene check before tagging or publishing:

   ```bash
   TUNEAV_STRICT_PUBLIC_HYGIENE=1 bun run config:hygiene
   ```

   The default check validates tracked files and keeps development usable. Strict mode verifies the public release workspace is clean.
4. Confirm no generated config files are present in the strict release workspace:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - `.infisical/bootstrap.env`
5. Confirm no signing files, provisioning profiles, private keys, exported certificates, or local build products are present.
6. Confirm public docs do not contain private email addresses, personal account names, Team IDs, local backend URLs, or provider secrets.

## Build Verification

1. Regenerate local config outside git if needed:

   ```bash
   bun run ios:config
   bun run macos:config
   ```

2. Build iOS for simulator:

   ```bash
   xcodebuild -project apps/ios/TuneAV.xcodeproj \
     -scheme TuneAV \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     build
   ```

3. Run focused tests when touching shared policy, access, or persistence behavior:

   ```bash
   xcodebuild -project apps/ios/TuneAV.xcodeproj \
     -scheme TuneAV \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     test
   ```

4. Remove generated local config again before publishing the repository state.

5. For macOS changes, run:

   ```bash
   bun run macos:preflight
   xcodebuild -project apps/macos/TuneAVMac.xcodeproj \
     -scheme TuneAVMac \
     -configuration Debug \
     -destination 'platform=macOS' \
     test
   ```

## Apple Developer

1. Confirm the production App ID exists for `com.avalsys.tuneav`.
2. Confirm the development App ID exists for `com.avalsys.tuneav.dev`.
3. Confirm the macOS App IDs exist for `com.avalsys.tuneav.mac` and `com.avalsys.tuneav.mac.dev` when preparing Mac App Store distribution.
4. Confirm required capabilities are enabled before archiving:
   - Sign in with Apple, when native login is shipped.
   - Associated Domains, Push Notifications, or iCloud only if the shipped target uses them.
   - App Sandbox and outbound network client entitlement for the macOS App Store target.
5. Keep the Apple team value in private configuration as `AVALSYS_APPLE_DEVELOPMENT_TEAM`; do not commit a literal Team ID.

## Pro And Store Purchases

1. First App Store release does not sell subscriptions from the iOS or macOS client.
2. Confirm there are no visible App Store purchase, restore purchase, or manage subscription actions in the shipping build.
3. Confirm Pro copy is framed as access state resolved by Account AV, not as an in-app purchasable offer.
4. Enable the In-App Purchase capability only when a future build ships client-side purchase or restore flows.
5. Before paid Pro is enabled later, confirm Account AV owns product mapping, server notification handling, reconciliation, and restore semantics.
6. For App Store macOS distribution, use StoreKit subscriptions shared with iOS; do not route digital subscription purchase through Apple Pay or web billing inside the Mac App Store build.

## Clerk And Account AV

1. Confirm Clerk production Apple SSO is configured before enabling native Apple sign-in.
2. Confirm Clerk development and production allowed origins and redirect URLs cover the Account AV surfaces used by this build.
3. Confirm `ACCOUNTAV_PUBLISHABLE_KEY` is the shared public client key for Account AV.
4. Confirm account management links resolve through `ACCOUNTAV_MANAGEMENT_URL`.
5. Confirm no Clerk secret key, smoke token, private relay config, or provider secret is present in this public repo.

## Infisical

1. Resolve local values through ambient `INFISICAL_*` variables or private operator tooling outside this repo.
2. Required shared values:
   - `AVALSYS_APPLE_DEVELOPMENT_TEAM`
   - `ACCOUNTAV_PUBLISHABLE_KEY`
   - `ACCOUNTAV_API_BASE_URL`
   - `ACCOUNTAV_MANAGEMENT_URL`
3. Required Tune AV values:
   - `TUNEAV_SUPPORT_EMAIL`
   - `TUNEAV_TERMS_URL`
   - `TUNEAV_PRIVACY_URL`
   - `TUNEAV_OPEN_SOURCE_URL`
4. Do not add `.infisical/bootstrap.env`, `.env`, `.env.example`, or generated `Local.xcconfig` examples to the public repository.

## Cloudflare And API Dependencies

1. Confirm `ACCOUNTAV_API_BASE_URL` points at the intended Account AV API environment for the build.
2. Confirm `GET /v1/me/access` is available when signed-in access is enabled.
3. Confirm Account AV production or preview smokes pass from the private infrastructure before releasing a client that depends on those routes.
4. Confirm `GET /v1/me`, `POST /v1/me/delete-account-request`, and `POST /v1/me/delete-account-finalize` are available before shipping the native account-deletion flow.
5. Confirm Tune AV renders `deleteAccountEligibility` from Account AV and blocks deletion when eligibility is unavailable, linked apps exist, Pro is active, or provider subscriptions are active/trialing/past due.
6. Confirm public support, terms, privacy, open-source, and account-management URLs are reachable. Keep `https://tune-av.avalsys.com/delete-account` as the public support/store URL, not the primary signed-in iOS deletion flow.
5. Keep Worker names, D1/R2 names, API tokens, and Cloudflare account details in private infrastructure only.

## GitHub Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe the current public workflow.
3. Create a version tag only after the build and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.
