# Tune AV iOS TestFlight feedback PR plan

Date: 2026-05-19

This plan turns the latest TestFlight feedback into three small PRs. Each PR should be reviewed, tested, and merged independently so regressions can be bisected cleanly.

## PR 1: Restore now playing immediately when returning to a station

User observation:

- A station already has now playing and artwork.
- Switch to another station.
- Return to the first station while the same song is still playing.
- The title/artwork disappear and sometimes take a long time to come back.

Likely code areas:

- `apps/ios/TuneAV/Core/Audio/AudioPlayerService.swift`
- `shared/apple/TuneAVNowPlayingService.swift`
- `shared/apple/TuneAVTrackArtworkService.swift`
- `apps/ios/TuneAV/Features/Shell/AppShellView.swift`

Hypothesis:

- `play(station:queue:)` calls `resetTransientStateForNewPlayback()` before `setCurrentStation(station)` and `restoreCachedNowPlaying(for:)`.
- `resetTransientStateForNewPlayback()` clears metadata, artwork image, artwork source URL, and the now playing signature.
- The cached metadata is restored after the reset, but the artwork image itself may need a fresh async load, so the UI/system now playing briefly falls back to station-only state until stream metadata or fallback polling catches up.

Implementation plan:

1. Add a focused regression test around cached now playing restoration where metadata and artwork URL survive a station switch and are available before fallback polling returns.
2. Preserve the cached track identity and artwork URL when returning to a station, including when stream metadata has not emitted again.
3. Make `updateNowPlayingInfo()` publish restored metadata immediately, then refresh artwork asynchronously without hiding the restored title/artist.
4. Consider adding a small station-scoped image cache lookup path so an artwork image already loaded for the same URL can be reused immediately.

Verification:

- Unit test for cached metadata restoration.
- Manual simulator flow: play station A until title/artwork appears, play station B, return to station A, verify title appears immediately and artwork appears from cache or as soon as the image loader resolves.
- Check Control Center/Lock Screen now playing title, artist, and artwork.

PR branch:

- `fix/ios-now-playing-restore-cache`

## PR 2: Preserve playback queue after sleep timer stops playback

User observation:

- A radio is playing from a list.
- Sleep mode stops playback.
- Pressing play again resumes only the single station, with no selected list, so next/previous cannot change stations.
- Similar loss of list context may happen in other workflows.

Likely code areas:

- `apps/ios/TuneAV/Core/Audio/AudioPlayerService.swift`
- `shared/apple/TuneAVSleepTimerController.swift`
- `shared/apple/TuneAVPlaybackQueueLogic.swift`
- `apps/ios/TuneAV/Features/Shell/MiniPlayerView.swift`
- `apps/ios/TuneAV/Features/Shell/AppShellView.swift`

Hypothesis:

- `setSleepTimer(minutes:)` fires `stop()`.
- `stop()` resets `playbackQueue` to `.singleStation` with an empty station list.
- Later `togglePlayback()` on `.idle` calls `play(station: currentStation)` without passing a queue, so the previous list context is lost.

Implementation plan:

1. Split stop semantics into two paths:
   - user/full stop: clear current station and queue when explicitly closing playback.
   - sleep timer stop: stop audio but preserve `currentStation` and `playbackQueue`.
2. Add a dedicated method such as `stopForSleepTimer()` or a `stop(preservingQueue:)` option.
3. Update sleep timer fire handling to use the preserving path.
4. Make `togglePlayback()` and `retry()` reuse the existing `playbackQueue` whenever the current station is still part of a multi-station queue.
5. Add tests for queue preservation after sleep timer stop and replay.

Verification:

- Unit test for queue preservation and `canCyclePlaybackQueue` after a sleep stop.
- Manual simulator flow: start from favorites/search/list, set a short sleep timer, wait for stop, press play, verify next/previous remain enabled and cycle within the same list.
- Regression check: explicit stop/close still clears playback context when intended.

PR branch:

- `fix/ios-sleep-timer-preserve-queue`

## PR 3: Harden station feedback selection against wrong action

User observation:

- Tapping like for a song/station sometimes results in dislike being selected.
- The dislike icon is far enough away that this does not look like a normal mistap.

Likely code areas:

- `apps/ios/TuneAV/Features/Shell/AppShellView.swift`
- `apps/ios/TuneAV/Features/Shell/MiniPlayerView.swift`
- `apps/ios/TuneAV/Features/Shell/MusicDiscoveryViews.swift`
- `apps/ios/TuneAV/Core/Persistence/LibraryStore.swift`
- `apps/ios/TuneAV/App/TuneAVAppDataService.swift`

Hypotheses:

- There may be a stale station or track feedback binding when the currently displayed station/track changes.
- The compact three-button `StationFeedbackControl` may be reused during SwiftUI diffing without enough identity around the selected station.
- Async feedback sync is probably not the cause of the local wrong icon, because local state is updated before backend sync, but it should still be checked.

Implementation plan:

1. Add logging or debug-only assertions around `setFeedback(_:for:)` and `setFeedbackForDiscoveredTrack(_:title:artist:)` to capture requested action, station ID, and visible station ID.
2. Ensure every feedback control is keyed by the station or track identity it mutates, for example via `.id(station.id)` at the call site if needed.
3. Confirm the like/dislike callbacks are never swapped in reused views and that selected state is derived from the same identity used by the action.
4. Add a UI test that opens feedback controls for two different stations in sequence and verifies tapping like never marks dislike.
5. If the issue is track feedback rather than station feedback, apply the same identity hardening to the track card/control.

Verification:

- UI test for like/dislike selection across station changes.
- Manual simulator flow: rapidly switch stations/list rows, open feedback, tap like, verify only like badge appears in hero, mini player, station row, and persisted library state.
- Backend smoke check: outgoing feedback payload uses `liked` for like and `disliked` for dislike.

PR branch:

- `fix/ios-feedback-selection-identity`

## Suggested execution order

1. PR 2 first, because the queue loss has a clear root cause and should be low risk.
2. PR 1 second, because it touches playback metadata/artwork and should be verified carefully on device.
3. PR 3 third, because it needs the most reproduction work and may require temporary instrumentation before the final fix.

## Release notes checklist

- Add each fix to `CHANGELOG.md` under the next iOS/TestFlight section.
- Include exact reproduction steps in each PR description.
- Include simulator/device used for verification.
- Capture before/after screen recordings for PR 1 and PR 2 if the issue reproduces locally.
