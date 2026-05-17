# Backend Automation Runbook

This document explains how to recreate Tune AV backend automations in the correct Codex App installation. Do not run long-lived backend automations from a laptop or temporary workstation.

## Goal

Use Codex App automations to run operational backend tasks from a machine that is intended to own them, for example:

- Periodically process queued station enrichment work.
- Import or refresh known station families after source changes.
- Review failed enrichment jobs and produce an operator summary.
- Run lightweight health checks against backend functions and logs.

The automation should not contain private URLs, tokens, API keys, project IDs, or secrets in its prompt. Those belong in the target machine's private environment configuration.

## Where It Should Run

Run backend automations only on the machine that has:

- The private backend monorepo checked out.
- The correct private environment access configured.
- The expected Node/Bun toolchain installed.
- Permission to access development or production backend deployments.
- Enough uptime for scheduled tasks.
- A Codex App profile that is intentionally used for backend operations.

Do not rely on an automation created on another Mac. Codex App automations are local to the machine/profile where they were created.

## Required Local Setup

On the correct machine:

1. Open Codex App.
2. Open the backend workspace, not this public iOS app workspace.
3. Confirm the backend repo builds and can read private configuration locally.
4. Confirm the backend CLI commands work manually before scheduling them.
5. Confirm the working tree is clean or that local changes are intentional.

Run the backend task manually once before creating an automation. The automation should only repeat a command or workflow that has already been verified.

## Recommended Automation Shape

Use a Codex App cron automation with:

- **Execution environment:** local, unless the backend repo has a reviewed worktree setup.
- **Workspace:** the backend repo root.
- **Model:** a reliable coding/reasoning model.
- **Prompt:** self-contained operational instructions, but no secrets.
- **Schedule:** conservative at first.
- **Status:** active only after a manual dry run.

Start with a low frequency. Increase only after observing cost, backend request volume, and queue behavior.

## Station Enrichment Automation

Recommended prompt:

```text
Process Tune AV station enrichment work from the backend queue.

Use the existing backend scripts/functions and private environment for this workspace.
Do not create new backend endpoints.
Do not write secrets, private URLs, tokens, or environment values to tracked files.
Process a bounded batch only.
Prefer idempotent updates.
Record a concise summary: processed count, skipped count, failed count, notable failures, and whether follow-up is needed.
If the queue or environment is not available, stop and report the blocker.
```

Recommended schedule:

- Development: every 1-3 hours while validating.
- Production: start daily or a few times per day, then tune based on queue size and cost.

Recommended batch controls:

- Free-user triggered work should be rate-limited and deduplicated.
- Pro-user triggered work can have higher priority and larger daily allowance.
- Reprocess only stale or incomplete enrichment records.
- Do not call paid external services when cached enrichment is fresh.

## Radio Family Import Automation

For imports such as a broadcaster family refresh, keep import and enrichment separate:

1. Import or update station records from source discovery.
2. Deduplicate by canonical stream URL, station family, country, language, and slug.
3. Mark changed or newly imported stations for enrichment.
4. Let the enrichment automation process the queue in bounded batches.

Recommended prompt:

```text
Refresh a known Tune AV station family using the existing backend import tooling.

Do not hardcode private backend URLs or credentials.
Discover current public stream entries from the source configured by the backend tooling.
Upsert stations idempotently.
Deduplicate stale or duplicate entries according to existing backend rules.
Mark new or changed stations for enrichment instead of enriching everything inline.
Report added, updated, deduplicated, skipped, and queued counts.
```

## Safety Rules

- Never paste secrets into the automation prompt.
- Never commit generated local config files.
- Never store backend base URLs in this public repo.
- Keep production batch sizes bounded.
- Prefer queue processing over immediate enrichment from user-facing app requests.
- Add dry-run mode to backend scripts before scheduling destructive or broad updates.
- Stop on schema mismatches instead of guessing.
- Report failures instead of retrying indefinitely.

## Verification Checklist

Before enabling an automation:

- The manual command succeeds from the backend workspace.
- The task reads environment from private local config.
- The task does not modify tracked public files.
- The task has a batch limit.
- The task deduplicates already processed stations.
- The task logs useful counts without exposing secrets.
- The task distinguishes development and production deployments.

After the first scheduled run:

- Check the automation summary.
- Check backend logs for failures.
- Check request volume and external-service cost.
- Open a few enriched stations in Tune AV and verify the UI displays useful details.
- Reduce frequency or batch size if free-user activity creates too much backend work.

## Migration From The Wrong Machine

If an automation was created on the wrong computer:

1. Pause or delete it in Codex App on that computer.
2. Copy only the safe prompt and schedule intent.
3. Recreate it in Codex App on the correct backend machine.
4. Point it at the backend repo root.
5. Run one manual dry run.
6. Enable the schedule.
7. Confirm the next run happens on the correct machine.

Do not export or copy local environment files between machines through this public repo.
