# Release Checklist

Use this checklist before creating the first public GitHub release and before each later tagged release.

## Repository Hygiene

1. Run `bun install`.
2. Run `bun run config:hygiene`.
3. Confirm no generated config files are present:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/AvtunesysMac/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - `.infisical/bootstrap.env`
4. Confirm no signing files, provisioning profiles, private keys, exported certificates, or local build products are present.
5. Confirm public docs do not contain private email addresses, personal account names, Team IDs, local backend URLs, or provider secrets.

## Build Verification

1. Regenerate local config outside git if needed:

   ```bash
   bun run ios:config
   ```

2. Build iOS for simulator:

   ```bash
   xcodebuild -project apps/ios/Avtunesys.xcodeproj \
     -scheme Avtunesys \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     build
   ```

3. Run focused tests when touching shared policy, access, or persistence behavior:

   ```bash
   xcodebuild -project apps/ios/Avtunesys.xcodeproj \
     -scheme Avtunesys \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     test
   ```

4. Remove generated local config again before publishing the repository state.

## Apple Developer

1. Confirm the production App ID exists for `com.avalsys.avtunesys`.
2. Confirm the development App ID exists for `com.avalsys.avtunesys.dev`.
3. Confirm the macOS App IDs are only used if the macOS target is part of the release.
4. Confirm required capabilities are enabled before archiving:
   - Sign in with Apple, when native login is shipped.
   - In-App Purchase, when subscriptions are shipped.
   - Associated Domains, Push Notifications, or iCloud only if the shipped target uses them.
5. Keep the Apple team value in private configuration as `AVALSYS_APPLE_DEVELOPMENT_TEAM`; do not commit a literal Team ID.

## Clerk And AV Account

1. Confirm Clerk production Apple SSO is configured before enabling native Apple sign-in.
2. Confirm Clerk development and production allowed origins and redirect URLs cover the AV Account surfaces used by this build.
3. Confirm `AVACCOUNT_PUBLISHABLE_KEY` is the shared public client key for AV Account.
4. Confirm account management links resolve through `AVACCOUNT_MANAGEMENT_URL`.
5. Confirm no Clerk secret key, smoke token, private relay config, or provider secret is present in this public repo.

## Infisical

1. Resolve local values through ambient `INFISICAL_*` variables or private operator tooling outside this repo.
2. Required shared values:
   - `AVALSYS_APPLE_DEVELOPMENT_TEAM`
   - `AVACCOUNT_PUBLISHABLE_KEY`
   - `AVACCOUNT_API_BASE_URL`
   - `AVACCOUNT_MANAGEMENT_URL`
3. Required AV Tunesys values:
   - `AVTUNESYS_PREMIUM_PRODUCT_IDS`
   - `AVTUNESYS_SUPPORT_EMAIL`
   - `AVTUNESYS_TERMS_URL`
   - `AVTUNESYS_PRIVACY_URL`
   - `AVTUNESYS_OPEN_SOURCE_URL`
4. Do not add `.infisical/bootstrap.env`, `.env`, `.env.example`, or generated `Local.xcconfig` examples to the public repository.

## Cloudflare And API Dependencies

1. Confirm `AVACCOUNT_API_BASE_URL` points at the intended AV Account API environment for the build.
2. Confirm `GET /v1/me/access` is available when signed-in access is enabled.
3. Confirm AV Account production or preview smokes pass from the private infrastructure before releasing a client that depends on those routes.
4. Confirm public support, terms, privacy, open-source, and account-management URLs are reachable.
5. Keep Worker names, D1/R2 names, API tokens, and Cloudflare account details in private infrastructure only.

## GitHub Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe the current public workflow.
3. Create a version tag only after the build and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.
