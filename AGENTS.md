# Tune AV Agent Rules

Before work that touches signed runtime, subscriptions, purchases, deployment,
TestFlight/App Store, Cloudflare remote state, or cross-app workflow
behavior, run the private workspace preflight first:

```bash
bash ../../private/avalsys-suite/scripts/agent-preflight.sh --app tune-av --intent <intent>
```

Read `../../private/avalsys-suite/docs/agents/workspace-guardrails.md` and every doc
printed by the preflight before executing commands. If the private repo is
unavailable, stop instead of guessing.

For local iOS/macOS builds, also follow
`../../private/avalsys-suite/docs/agents/native-cache-hygiene.md`: use
repo-local purpose-named `-derivedDataPath` directories and remove repo-local
`.DerivedData*`/`.derived-data*` caches after the task when no build is using
them.

This public repo does not define the full signed-runtime testing workflow.

For any native app workflow validation that touches signed account state,
subscriptions, purchases, RevenueCat identity, uploads, backend-owned library
state, deletion flows, or private API access, follow the private AVALSYS guides.
Do not invent a local runtime flow from this public repo.

- `private/avalsys-suite/docs/platform/native-preview-dev-validation-guide.md`
- `private/avalsys-suite/docs/tune-av/development-runbook.md`
- `private/avalsys-suite/docs/tune-av/public-repo-release-process.md`
- `private/avalsys-suite/docs/agents/plan-step.md` when the user says
  `usa plan-step` or asks for step-by-step plan execution.
- `private/avalsys-suite/docs/agents/plan-goal.md` when the user says
  `usa plan-goal` or asks for reviewed full-plan execution.

Mandatory rules:

- Infisical is owner-managed and strictly read-only for agents and repository
  workflows. Never create, add, update, rotate, rename, restore, import, or
  delete any Infisical value through CLI, API, browser, MCP, or a script. If a
  value must be added or changed, tell the user the exact variable name, target
  environment, reason, and secret-free validation result; the user performs
  the change personally and confirms it before read-only validation resumes.
- use Cloudflare preview for signed API runtime;
- do not use `wrangler dev` or another local Worker as product app backend;
- do not invent alternate runtime/testing flows when the private guide already
  defines one;
- use Infisical/Varlock-backed private tooling for config, deploy keys, and
  secret resolution;
- before unattended TestFlight/App Store export/upload from a new or recently
  reconfigured Mac, complete the private release-machine setup in
  `private/avalsys-suite/docs/platform/apple-release-machine-setup.md`; the
  Apple Distribution private key must pass non-interactive `codesign`;
- keep private URLs, service identifiers, approval status, and operations
  evidence out of this public repo;
- treat Account AV provider session identity as session metadata only; product
  ownership and backend-owned state must resolve through the internal Apps AV
  account user contract;
- keep Pro cloud sync calm: one automatic library sync at startup or after a
  successful sign-in, explicit manual retry when requested, and no periodic or
  repeated foreground sync;
- treat `docs/pro-sync-scope.md` as the authoritative product boundary: only
  explicitly saved stations and songs sync; feedback is device-local, may have
  one explicit Pro analytics mutation, and must not be restored or delivered
  through any realtime fanout; Pro sync is open/foreground/manual with
  conditional GETs (ETag/304), there is no realtime channel;
- keep station and track feedback clear payloads explicit: the strict Tune API
  requires a present `feedback` key with JSON `null`; Swift optional encoding
  that omits the key is a permanent regression covered on both Apple clients;
- on both Apple clients, Pro library refresh happens once at startup or after
  sign-in, on foreground/activation with a 60-second throttle, and on explicit
  manual sync; resource GETs send `If-None-Match` and treat `304` as unchanged;
- after a successful item-level library mutation, retain the response
  `updatedAt` as coverage for that exact resource so the authoring device does
  not re-fetch what it just wrote;
- preserve confirmed Pro capabilities while refreshing the same internal user,
  but drop capabilities from the previous account before resolving a different
  internal user.
- Coalesce concurrent iOS account refresh callers in `AccessController` and
  reuse the resolved `/v1/me` summary in account UI. A signed-in cold launch
  should issue one profile read and one access read; `ProfileScreen` must not
  add its own duplicate summary fetch after the shared bootstrap.

If the private repo is unavailable, stop and say that the authoritative runbook
cannot be checked. Do not substitute a guessed local workflow.
