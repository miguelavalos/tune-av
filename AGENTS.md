# Tune AV Agent Rules

Before work that touches signed runtime, subscriptions, purchases, deployment,
TestFlight/App Store, Convex, Cloudflare remote state, or cross-app workflow
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

- use Cloudflare preview for signed API runtime;
- use Convex cloud `dev`, not local Convex, when a native app workflow depends
  on Convex-backed state;
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
- on macOS, consume a single consecutive realtime library generation for a
  known resource with one exact resource GET and no unrelated feedback read;
  generation gaps, unknown resources, bootstrap, and manual recovery must keep
  the conservative full-library path;
- preserve confirmed Pro capabilities while refreshing the same internal user,
  but drop capabilities from the previous account before resolving a different
  internal user.
- Coalesce concurrent iOS account refresh callers in `AccessController` and
  reuse the resolved `/v1/me` summary in account UI. A signed-in cold launch
  should issue one profile read and one access read; `ProfileScreen` must not
  add its own duplicate summary fetch after the shared bootstrap.

If the private repo is unavailable, stop and say that the authoritative runbook
cannot be checked. Do not substitute a guessed local workflow.
