# Tune AV Pro Sync Scope

Decision date: 2026-07-13

This document is the public product source of truth for what Tune AV calls
cloud sync. If an older checklist, release note, test record, localization, or
build says otherwise, this decision takes precedence.

## Approved Contract

Tune AV Pro synchronizes exactly two user-library resources between devices:

- explicitly saved stations (`favorites`);
- explicitly saved songs (`savedDiscoveries`).

The following state remains local to each device:

- recents and automatic discovery history;
- playback and queue state;
- app and device settings;
- station feedback and song feedback shown in the client.

Feedback is not cloud sync. A deliberate Pro feedback action may be uploaded
once to the Tune backend so that server-side summaries and recommendations can
use it, but it must not be downloaded, restored, or broadcast to another
device. Guest and signed-in Free feedback remains entirely local.

Listening analytics may be uploaded under the applicable account and privacy
contract. It is analytics input, never synchronized or restored app state.

## Traffic Contract

Only saved-station and saved-song mutations may publish library realtime
invalidations. Feedback must not create a Convex feedback invalidation, a
projection outbox/Queue event, or a cross-device feedback snapshot read.

The steady-state budget for one saved-item mutation is:

- one mutation from the authoring device;
- zero author-side reads for the covered projection;
- one exact-resource read on each active receiving device;
- no unrelated library, feedback, summary, retry, or extra realtime-session
  request.

## Migration And Release Status

TestFlight iOS `1.0.7 (52)` and macOS `1.0.7 (61)` implement the earlier,
superseded feedback-sync contract. Their saved-station and saved-song evidence
is still valid, but they are migration-pending and must not be submitted for App
Review as the final implementation of this decision.

The source migration was implemented, locally verified, and deployed on
2026-07-13: feedback bootstrap/restore and realtime fanout were removed from
both Apple clients and the compatible Workers, Free/Guest uploads were
disabled, and all affected product copy was updated. Signed-in Pro feedback
save/clear production smokes retained the D1 mutation without creating a new
feedback outbox event. Compatibility feedback endpoints remain temporarily for
older installed builds, but new clients do not use feedback reads as sync.

Replacement TestFlight candidates iOS/iPadOS `1.0.7 (53)` and macOS `1.0.7
(62)` were archived from public source commit `515bd93`, passed the governed
release gates, and were accepted for processing by App Store Connect on
2026-07-13. Apple subsequently completed both uploads and assigned the builds to
the internal TestFlight group. Neither upload was submitted to App Review.

TestFlight automatically installed macOS build `62` on the verification Mac.
Its signed-in Pro cold launch fetched only `favorites` and
`savedDiscoveries` as app-data resources and created the expected realtime
session. A bounded live-tail window observed no feedback GET, summary, retry,
or mutation.

The deliberate macOS feedback gate subsequently proved that one Pro selection
created exactly one successful Tune API write and no feedback GET, summary,
retry, realtime request, or projection fanout. Clearing the selection exposed a
shared Apple-client defect: synthesized `Encodable` omitted the optional
`feedback` field when it was `nil`, while the backend contract requires the key
with a JSON `null` value. The clear request therefore returned `400` and was not
retried. The one temporary row was removed by an exact, fully constrained
production cleanup; the feedback projection outbox remained unchanged at four
historical rows, latest `2026-07-10T10:40:38.112Z`.

Current source fixes that client-only defect on both Apple platforms: station
and track feedback request encoders now emit explicit JSON `null` for a clear.
Exact payload regressions passed through the iOS service request path and the
macOS request models, and the complete suites passed 363 iOS and 63 macOS tests
with zero failures. No Worker, Convex, production configuration, production
data, or App Review state changed as part of the repair. Builds `53` and `62`
predate it and remain ineligible for review; later TestFlight candidates still
need a bounded save/clear live-tail proof. Physical iOS proof remains open.

Repaired candidates iOS/iPadOS `1.0.7 (54)` and macOS `1.0.7 (63)` were then
archived from public source commit `efc9515`. Both governed production
preflights passed with zero failures and zero warnings; the iOS Release
simulator build, final archive identity/privacy checks, and matching
application/Sentry dSYMs also passed. The retained exact archives are
`.derived-data/release-archives/TuneAV-1.0.7-54-2026-07-13-205426.xcarchive`
and
`.derived-data/macos-release-archives/TuneAVMac-1.0.7-63-2026-07-13-205902.xcarchive`.
App Store Connect accepted iOS at 20:57 CEST and macOS at 21:02 CEST; both
uploads ended with `Upload succeeded` and `EXPORT SUCCEEDED` and entered
processing. The App Store Connect session expired before processing completion
or internal `Tune AV Test` assignment could be confirmed. Neither build was
submitted to App Review. Do not install, test, or select these builds for
review until processing and intended-group availability are confirmed; after
that, require the bounded Pro save/clear proof described above.

The product-copy migration must update every locale for at least these shared
iOS/macOS keys before a replacement archive is accepted:

- `profile.alert.clearSyncedLibrary.message`;
- `limits.upgrade.discoveredTracks.message`;
- `paywall.benefit.sync`;
- `profile.pro.sync.detail`.

This list remains a release guard for every replacement archive.

## Terminology

- **Sync** means user-visible state is restored across devices.
- **Upload** means one explicit event may be retained for server-side product
  processing; it does not imply download, restore, or realtime delivery.
- **Historical evidence** records what an older build actually did and does not
  override this contract.
