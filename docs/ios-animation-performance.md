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

## Review Checklist

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
