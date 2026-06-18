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
- Tune Pro sync copy is constrained to the existing app-data contract: favorites
  and saved discoveries can sync when Account AV reports Pro cloud sync; recents,
  playback/session context, feedback queue, and local preferences stay
  local-first unless the backend contract changes.
- `apps/web` now has `qa:shared`, powered by the shared Apps AV smoke QA runner
  across `en`, `es`, `fr`, `de`, and `ca` for public routes, protected gates,
  language preservation, product identity, and no guest product copy.
