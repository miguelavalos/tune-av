# Tune AV Web Audit

Status: current as of 2026-06-19.

Tune AV commercial web was checked as part of the AV web visual audit.
Tune AV app web now exists at `apps/web`.

## Contract

- User-facing web content supports `en`, `es`, `fr`, `de`, and `ca`.
- AV-owned links preserve the active language.
- The commercial surface may use AVALSYS naming where legal, brand, or company
  context requires it.
- App web has a public informational `/` route.
- App web product routes require login; no guest-mode product functionality is
  exposed on web.
- App web runs on app origins: preview `https://app.tune-av-preview.avalsys.com`
  and production `https://app.tune-av.avalsys.com`.

## Latest Audit Result

- Desktop and mobile browser QA passed.
- Footer links to AV-owned surfaces preserve language.
- Commercial metadata was aligned with the preview domain during the audit.
- Local and preview app web QA passed for public `/`, protected `/listen`, and
  five-language rendering.
- Preview app web deployed to `https://app.tune-av-preview.avalsys.com`.
- Preview app web build now resolves Account AV configuration through the
  private suite Varlock wrapper and splits Clerk/localization/serialization/UI
  vendor chunks without large client chunk warnings.
- Signed-in preview QA passed for `/avi`, `/listen`, and `/library` in localized
  routes after completing protected-route copy for `ca`, `de`, and `fr`.
- App-owned logo, navigation, CTA, and Avi assistant links preserve the active
  `lang` query value in the preview app.
- Production app web was deployed to `https://app.tune-av.avalsys.com` after
  production build and dry-run passed. Initial production smoke exposed missing
  Worker Clerk secrets; after syncing runtime secrets, HTTP smoke and signed-in
  browser QA passed for public, sign-in, and protected localized routes.

## 2026-06-19 Series/Shared Baseline Alignment

- Tune AV app web consumes the shared Apps AV shell through a Tune wrapper and
  passes the current route to keep active navigation semantics aligned with
  Series AV.
- Functional routes remain protected behind Account AV; `/` and `/sign-in`
  remain public. The signed-out state now uses shared `ProtectedAppGate`.
- `/account` was added as a protected Account AV surface using shared
  `SettingsProfileScaffold`, `PlanFeatureSection`, `CloudSyncSection`, and
  `AccountSafetySection`. Web billing is not implemented in Tune AV; plan
  management opens Account AV.
- `/settings` was rebuilt on the shared Settings scaffold with language,
  System/Light/Dark appearance, Tune listening preferences, local device data,
  and shared help/legal rows.
- `/settings` uses shared `@avalsys/apps-av-web` settings controls, including
  `SettingsSelect` for the external search-engine list; public-info and lyrics
  lookups use the configured shared engine list with DuckDuckGo as the default.
- Tune Pro sync copy is constrained to the existing app-data contract: favorites
  and saved discoveries can sync when Account AV reports Pro cloud sync; recents,
  playback/session context, feedback queue, and local preferences stay
  local-first unless the backend contract changes.
- `apps/web` now has `qa:shared`, powered by the shared Apps AV smoke QA runner
  across `en`, `es`, `fr`, `de`, and `ca` for public routes, protected gates,
  language preservation, product identity, and no guest product copy.
- Preview deploy completed for `https://app.tune-av-preview.avalsys.com`; shared
  web QA passed across five locales and eight routes.
- Production deploy completed for `https://app.tune-av.avalsys.com`; shared web
  QA passed across five locales and eight routes.

## 2026-06-19 Player Hydration Hotfix

- Fixed Tune app store hydration so the initial client render matches SSR and
  restores local favorites/player state after mount instead of during
  hydration.
- Hotfix commit `955fcc4` was pushed to `main`.
- Preview deploy completed for `https://app.tune-av-preview.avalsys.com`; shared
  web QA passed across five locales and eight routes.
- Production deploy completed for `https://app.tune-av.avalsys.com`; shared web
  QA passed across five locales and eight routes.
- In-app browser QA on production passed for signed-in `/listen?lang=es`,
  station playback attempt, persisted player reload, full player, and mobile
  viewport. No new React hydration errors were captured in fresh production
  tabs after the hotfix.

## 2026-06-19 External Link Preferences

- Tune AV web now uses the shared Apps AV external-search helpers from
  `@avalsys/apps-av-web`.
- The settings screen exposes the shared engine list through shared
  `SettingsSelect` rather than product-local buttons or form styling.
- Production deploy completed for `https://app.tune-av.avalsys.com`; HTTP smoke
  passed for `/` and `/settings`.

## 2026-11-01 Account-Only Reduction

- Decision: the web app duplicated the native app (radio playback, library,
  music, Avi) at ~140 requests/day and cannot sell Pro, because purchase is
  App Store only. It is reduced to a landing plus account surfaces so delete
  account, privacy, support, and Pro status stay reachable, and users are
  pointed to the App Store app.
- Routes kept: `/`, `/sign-in`, `/account`, `/settings`. Routes removed:
  `/listen`, `/music`, `/library`, `/avi`. Removed with them: the audio store
  (`tune-store.tsx`), the player (`tune-player.tsx`, `tune-listen.tsx`,
  `tune-station-card.tsx`), the public station API proxies
  (`tune-public-api.ts`), `tune-station.ts`, `tune-api.ts`, `tune-types.ts`,
  `tune-access.ts`, `tune-functional-text.ts`, the unused `tune-account-area`
  and `ui/input` components, their tests, the station fallback artwork, and the
  i18n keys that only those surfaces used (the five locales stay).
- Signed-in `/` now shows a short product summary, a localized "Download on
  the App Store" badge linking to the same listing as the commercial site
  (`https://apps.apple.com/us/app/tune-av/id6766301702`), links to Account and
  Settings, and the Free/Pro plan state from `useAccountAppAccess("tuneav")`.
  Signed-out `/` keeps the informational landing plus the App Store badge.
- `/account` keeps session, email, plan, sign out, Pro feature summary, and
  the shared account deletion row. For Free users the Pro button opens the
  App Store; for Pro users it opens Account AV. Cloud sync status was removed
  with the store. `/settings` keeps language, appearance, and help/legal rows;
  the listening preferences and local-data sections were removed.
- Signed-out protected routes now render the public landing (with sign-in and
  App Store CTAs) instead of a skeleton plus client redirect, so
  `/account?lang=es` answers 200 with a real gate.
- The navigation shell lists only Home, Account, and Settings; the Avi
  assistant entry was removed from the product config.
- `__root.tsx` now emits a localized `<meta name="description">`, Open Graph
  `type/site_name/title/description/url/image`, and `twitter:card`.
- Dependencies: `apps/web/package.json` went from 48 to 19 direct
  dependencies. The 17 exact-pinned `@tanstack/*` internals, `@clerk/backend`,
  `@clerk/shared`, and the transitive pins (`cookie-es`, `dequal`,
  `glob-to-regexp`, `h3-v2`, `isbot`, `js-cookie`, `scheduler`, `seroval`,
  `seroval-plugins`, `standardwebhooks`, `tslib`, `use-sync-external-store`)
  were removed. They existed only because `preserveSymlinks: true` in
  `vite.config.ts` and `tsconfig.json` forced transitive imports to resolve
  from `apps/web/node_modules`; pnpm already installs the `file:` shared
  packages (`@avalsys/account-av-web`, `@avalsys/apps-av-web`) into its store
  with their own dependencies, so `preserveSymlinks` was dropped instead of
  restoring the pins. No root `pnpm-workspace.yaml` or root `package.json`
  change was needed; `pnpm-lock.yaml` shrank accordingly.
- `manualChunks` now only splits `vendor-react`, `vendor-clerk-localizations`,
  and `vendor-clerk`.
- Preview build client JS went from 1,057,912 bytes to 923,552 bytes
  (CSS 58.1 kB to 47.8 kB); player and public-scene CSS and six unused
  brand images under `public/assets` were removed. Typecheck, `vp test run` (i18n parity test), and
  `build:preview` pass.
- Preview deploy completed for `https://app.tune-av-preview.avalsys.com`. HTTP
  checks: `/` 200, `/account?lang=es` 200, `/settings?lang=fr` 200, `/sign-in`
  200, `/listen` 404.
- Known limitation, pre-existing: the server render emits only the document
  head; the body is filled on the client because `SignedIn`/`SignedOut` in
  `@avalsys/account-av-web` wait for Clerk to load. Production
  `app.tune-av.avalsys.com` behaves the same today, so the shared HTTP smoke
  QA checks for public and gate copy fail on both. `qa:shared` was updated to
  the four remaining routes and the new copy; it will pass once the shared
  provider renders auth state on the server.
- Production was not deployed; `CHANGELOG.md` is edited on another branch.
