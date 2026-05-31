# Tune AV iOS Animation And Audio Performance

Tune AV is a streaming audio app. UI animation must not compete with playback,
stream metadata updates, artwork loading, or Now Playing system updates.

## Default Policy

Keep these surfaces static while audio can be playing:

- Home;
- mini-player;
- tab shell;
- live/now-playing summary panels;
- station lists and compact cards;
- search results;
- library rows/grids;
- skeleton/loading cards.

Do not use continuous animation in those surfaces:

- no `.repeatForever`;
- no decorative `TimelineView`;
- no animated equalizer/waveform overlays;
- no shimmer loops;
- no per-cell animated artwork.

## Allowed Animation

Allowed:

- one-shot transitions from user actions;
- button press/selection feedback;
- navigation or sheet transitions;
- restrained continuous motion only in the full player when it is visible and
  focused.

The full player is the only default place for procedural playback visuals.

## Runtime Guards

Any continuous player animation must stop unless all are true:

- app scene is active;
- full player is visible;
- playback is active;
- Reduce Motion is disabled;
- Low Power Mode is disabled.

## Artwork And Metadata

Stream metadata and artwork can arrive while audio is playing. Keep the hot path
light:

- download/decode/downsample artwork off the main actor;
- cache decoded artwork;
- update UI only when title, artist, album, or artwork identity actually changes;
- avoid animated artwork replacement in Home, mini-player, or lists;
- avoid repeated `MPNowPlayingInfoCenter` writes for duplicate metadata;
- filter noisy broadcast metadata before showing it.

## Merge Checklist

Before merging playback-adjacent UI:

- Search the touched files for `repeatForever`, `TimelineView`, and animated
  artwork overlays.
- Confirm Home, mini-player, shell, search, and list cells remain static.
- Confirm image decoding is not performed on `MainActor`.
- Build on simulator.
- Test audio on a real device with one stable station and one problematic stream.
- Navigate Home, Search, Library, mini-player, and full player while playback is
  active.

Simulator audio stutter is a useful warning, but real-device playback is the
release gate.

## Launch Performance Profile

Use the launch profile before and after changes that affect startup,
dependency loading, app assets, the shell, or the first Home render:

```bash
bun run ios:profile:launch-performance
```

The profile runs the launch performance smoke several times and writes a local
markdown report under `.derived-data/ios-launch-performance-profile/report.md`.
Keep the same simulator/runtime when comparing commits. Tighten
`TUNEAV_IOS_MAX_LAUNCH_READY_MS` only after the median is stable in CI history.

## Avi Frame Animation Contract

Tune AV plays Avi motion as PNG frame loops. The runtime looks for production
frames first and falls back to the current static emotion assets when a loop is
missing.

### Runtime Behavior

`NowPlayingView` and the full player Avi header render frame loops with
`TimelineView` at 12 frames per second. The renderer asks for the production
loop mapped to the current `TuneAVAviEmotion`; if fewer than two frames exist,
it renders the existing static full-body asset for that emotion.

Feedback in the player drives the animated emotion directly:

- `liked` maps to `.celebrate`, which uses `AviTuneHappyReact000...019`.
- `notForMe` maps to `.thinking`, which uses `AviTuneThinking000...019`.
- `disliked` maps to `.dislike`, which uses `AviTuneDislike000...019`.

The footer tab still uses Avi as a cropped head/icon treatment with
`AviV2HeadNeutral`, so it does not duplicate the full-body Avi shown in content.

### Asset Rules

- Canvas: 1024 x 1024 transparent PNG.
- Avi must keep the same body scale, center, and foot baseline in every frame.
- Do not mix emotion poses as frames. Each sequence must be one coherent acting
  beat for a single emotion.
- Export 20 frames per production loop unless a shorter loop is deliberately
  approved.
- Use three-digit frame suffixes.

### Current Loops

```text
AviTuneListeningIdle000.png ... AviTuneListeningIdle019.png
AviTuneHappyReact000.png ... AviTuneHappyReact019.png
AviTuneSaved000.png ... AviTuneSaved019.png
AviTuneCurious000.png ... AviTuneCurious019.png
AviTuneThinking000.png ... AviTuneThinking019.png
AviTuneDislike000.png ... AviTuneDislike019.png
AviTuneSurprised000.png ... AviTuneSurprised019.png
AviTuneCalmIdle000.png ... AviTuneCalmIdle019.png
AviTuneSleepIdle000.png ... AviTuneSleepIdle019.png
```

These frames can be replaced by hand-drawn or generated production frames
without changing Swift code, as long as names and canvas contract stay the same.

### Acting Direction Examples

`AviTuneHappyReact` is one animation, not a sequence of emotion changes:

- Avi keeps a happy face for the whole loop.
- Frame 000 starts in a balanced happy/listening pose.
- Frames 001-006 lift the head and shoulders slightly.
- Frames 007-012 add a small dance sway and arm bounce.
- Frames 013-019 return to the starting pose cleanly for looping.

`AviTuneThinking` can be simpler:

- Avi keeps a thinking face.
- Eyes/pixels shift once or twice.
- Head dips slightly.
- Body remains nearly still.

The face expression may change within the same emotion only as part of the same
acting beat, for example happy eyes blinking or thinking pixels scanning. It
must not jump from happy to surprised to focused unless the animation itself is
explicitly a transition.
