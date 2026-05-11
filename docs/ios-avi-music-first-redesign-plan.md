# iOS Avi Music-First Redesign Plan

## Context

Tune AV should feel clearly focused on live music radio discovery: finding stations, understanding what is playing, saving radios, cataloging tracks/artists, and tuning preferences through Avi.

Avi should be present across music-related surfaces as a curator and contextual guide, without becoming visually noisy. Artwork remains useful but secondary: station artwork and track artwork should be small, tappable, and expandable, not the main hierarchy driver.

Current baseline:

- iOS app lives in `apps/ios/TuneAV`.
- First redesign phase is already on `origin/main`.
- Current local work may include fallback artwork identity changes in `shared/apple/TuneAVStationArtworkView.swift`; inspect `git status` before editing.
- Dev simulator should use bundle id `com.avalsys.tuneav.dev`.
- Station service defaults to preview endpoints in `shared/apple/TuneAVStationService.swift`.

Hard constraints:

- Do not touch backend.
- Do not introduce backend AI.
- Do not rewrite the app.
- Keep SwiftUI idiomatic and follow existing component patterns.
- Preserve current playback behavior and queue behavior.
- Verify iOS Simulator build at the end.

## Product Direction

Default experience is music-first:

- Home, Search, popular recommendations, and Avi picks prioritize music stations.
- News, sports, talk, culture, local, public, religion, and other station types remain accessible, but they do not lead the default experience.
- Search gets an explicit `Music / All radio` mode. Default is `Music`.
- If the user explicitly searches for or selects non-music categories, the app respects that intent.

Avi is the product layer that explains, curates, and guides:

- Avi owns statuses such as searching, listening, tuning, curious, excited, unsure, and focused.
- The global header should not show those status pills anymore.
- Avi should appear with different intensity per screen:
  - Home: high.
  - Radios: medium.
  - Music: high.
  - Search: medium.
  - Full Player: high.
  - Account: low, mostly subscription/perks later.
  - Settings: none unless there are explicit Avi settings later.

## UX Decisions

### Global Header

Current top header is `settings + logo + account` with a status label/pill below the logo.

Change direction:

- Keep `settings + Tune AV logo + account`.
- Remove the status pill/label from the global header.
- Move state/status language into Avi components inside each screen.
- Add scroll-aware behavior for the top header:
  - scrolling down compacts or hides it;
  - scrolling up shows it again.
- Keep footer as-is for now because it contains mini player behavior.

Implementation notes:

- Start in `Features/Shell/ShellChromeViews.swift` and `Features/Shell/AppShellView.swift`.
- Prefer a reusable scroll offset/header visibility helper if simple.
- Do not destabilize footer/mini-player positioning.

### Home

Home should become the primary Avi music discovery desk.

Target order:

1. Avi brief/status:
   - Avi emotion.
   - Short comment.
   - Current focus, e.g. "Avi is tuning music stations for you".
2. Continue listening:
   - If a station is currently playing, show it.
   - If no station is playing but `lastPlayedStationID` exists, use the last played station as the main "Continue listening" candidate.
   - Then favorite, then music-first popular/feed fallback.
3. Music states and genres:
   - Only music tags in first-level chips.
   - Suggested visible tags: Pop, Rock, Electronic, Latin, Jazz, Chill, Dance, Classical, Oldies, Hip-Hop, Indie.
   - Do not show News/Sports/Talk/Culture in this block.
4. Avi music picks:
   - Music-first recommendations.
   - Show Avi reason text where possible.
5. Around you:
   - Music-first country/context matches.
6. More live radio:
   - Secondary access to News, Sports, Talk, Culture, Local, etc.

Implementation notes:

- Home code is mostly in `Features/Shell/AppShellView.swift`.
- `LibraryStore.settings.lastPlayedStationID` is already persisted in `Core/Persistence/LibraryStore.swift`, but Home currently does not use it directly as hero unless the station is current/favorite/feed. Add a safe resolver using `libraryStore.station(for:)`.
- Avoid changing audio playback restoration unless explicitly needed.

### Search

Search should be music-first by default but make all radio discoverable.

Target UI:

- Title/copy should make search feel like music radio discovery.
- Add segmented control:
  - `Music`
  - `All radio`
- Default mode: `Music`.
- Visible music chips in `Music` mode:
  - Pop, Rock, Electronic, Latin, Jazz, Chill, Dance, Classical, Oldies, Hip-Hop, Indie.
- In `All radio` mode:
  - Include all categories, including News, Sports, Talk, Culture, Local, Public, Religion.
- Country filter remains available.
- Search field remains prominent on Search screen only.

Behavior:

- `Music` mode filters or strongly prioritizes music stations.
- `All radio` mode does not penalize non-music categories.
- If query or selected tag is clearly non-music, either switch to `All radio` or show a subtle Avi hint offering to broaden results.

Implementation notes:

- `AppShellSearchRequest` in `shared/apple/TuneAVAppShellSearch.swift` likely needs a discovery mode.
- Add something like:

```swift
enum TuneAVStationDiscoveryMode {
    case music
    case allRadio
}
```

- Thread mode into Search UI and local ranking/filter logic.
- Use existing station fields first: `category`, `tagsList`, `editorial`, discovered track history if available.
- Avoid backend parameter changes unless already supported and proven.

### Radios

Radios should feel like a library/collection surface, not a search page.

Target order:

1. Avi library brief:
   - saved count, recent count, quick comment.
2. My collection / saved radios.
3. Recently played.
4. Avi recommends revisiting:
   - based on recents/favorites/feedback.
5. Search access:
   - collapsed row, icon button, or "Find more stations" CTA.
   - Not the primary hero.

Implementation notes:

- `LibraryScreen` is in `Features/Shell/AppShellView.swift`.
- Keep existing saved/recent playback/favorite/details actions.
- Do not remove search ability; demote it visually.

### Music

Music should feel like Avi's memory of detected songs/artists.

Target order:

1. Avi music memory brief:
   - saved tracks, recent discoveries, strongest station source.
2. Saved tracks.
3. Recent discoveries.
4. Artists / recurring artists if data supports it.
5. Stations that produced discoveries.
6. Search access secondary.

Implementation notes:

- Music screen is in `Features/Shell/AppShellView.swift` and `Features/Shell/MusicDiscoveryViews.swift`.
- Use existing `DiscoveredTrack` and `LibraryStore` methods.
- Avoid adding external artist APIs in this phase.

### Full Player

Full Player should become an Avi listening desk.

Principles:

- Avi has high presence as commentator/recommender.
- Station artwork and track artwork are small and tappable to expand.
- The key hierarchy is information and action, not artwork.

Target order:

1. Avi state/comment:
   - avatar small/medium;
   - emotion chip;
   - one useful sentence.
2. Station identity:
   - small station artwork;
   - station name;
   - country/language/music tags;
   - save/details/feedback.
3. Now playing:
   - track title;
   - artist;
   - small track artwork if available;
   - save track, artist/search, lyrics/YouTube if existing actions are available.
4. Avi recommendations:
   - similar music stations;
   - why Avi picked them.
5. Radio profile/context:
   - tags, quality, stream info, source context.
6. Playback controls:
   - preserve current controls and queue behavior.

Implementation notes:

- Full player is in `Features/Player/NowPlayingView.swift`.
- Do not break playback queue, audio session, now playing metadata, or discovery persistence.
- Artwork expansion can be a sheet/fullscreen cover later; first phase may make artwork tappable only if cheap.

### Account And Settings

Account:

- Keep account/account-safety content.
- Later, add Avi subscription/perk card if subscription exists.
- Do not overdo Avi here yet.

Settings:

- No Avi presence unless adding explicit Avi settings later.
- Possible future settings:
  - Avi recommendation tone.
  - Music-first default.
  - Explicit content/discovery preferences.

## Shared Music Classification

Create or centralize music classification logic so Home/Search/Radios/Player agree.

Possible helper:

```swift
enum TuneAVStationDiscoveryMode {
    case music
    case allRadio
}

enum TuneAVStationMusicClassifier {
    static func isMusicStation(_ station: Station) -> Bool
    static func musicScore(_ station: Station) -> Int
    static func nonMusicCategory(_ station: Station) -> String?
}
```

Music signals:

- `station.category == "music"`.
- Tags include music genres/moods.
- Station has discoveries / now playing track metadata.
- Editorial/discovery profile indicates music.

Non-music signals:

- Tags include news, sports, talk, culture, religion, public radio, comedy, politics, business.
- `station.category` indicates mixed/news/talk if present.

Important:

- In Music mode, prefer music strongly.
- In All radio mode, include all.
- If a non-music tag/query is explicit, respect user intent.

## Avi Copy Guidelines

Keep Avi copy short, contextual, and useful.

Good:

- "Avi is tuning music stations for you."
- "Avi found music-heavy stations near your recent listening."
- "Avi is showing all live radio."
- "Avi needs a few tracks before it can read this station."
- "Strong music signal."
- "Near your saved Spanish pop stations."

Avoid:

- Explaining backend/API/private implementation.
- Long instructional text.
- Overusing Avi in settings/account.

## Implementation Phases

### Phase 1: Product Structure And Shared Mode

- Add shared discovery mode/classifier.
- Update Home music genre chips to music only.
- Add Search `Music / All radio` mode.
- Keep UI changes small and buildable.

Verification:

- Build generic iOS Simulator.
- Run dev simulator.
- Confirm Search works in both `Music` and `All radio`.
- Confirm non-music categories are still reachable.

### Phase 2: Header And Avi Status Ownership

- Remove global status pill from header.
- Add screen-level Avi status/brief components.
- Add scroll-aware header compact/hide behavior.

Verification:

- Home/Search/Radios/Music scroll without overlapping footer/mini player.
- Header returns when scrolling upward.
- Accessibility identifiers remain usable for header buttons.

### Phase 3: Radios And Music Reframing

- Demote search in Radios and Music.
- Add Avi brief cards.
- Reorder screen content around saved/recent/discovered data.

Verification:

- Saved/favorite/details/play actions still work.
- Empty states remain useful.
- Search is still accessible.

### Phase 4: Full Player Redesign

- Reorganize player around Avi comment, station info, now playing, recommendations, controls.
- Keep artwork small and tappable/expandable if feasible.
- Preserve playback controls and queue behavior.

Verification:

- Start playback from Home/Search/Radio.
- Open full player.
- Save station/track and feedback still persist.
- No regressions in mini player.

## Verification Commands

Generic build:

```sh
xcodebuild -project /Users/elibot/github/avalsys/public/tune-av/apps/ios/TuneAV.xcodeproj -scheme TuneAV -destination 'generic/platform=iOS Simulator' build
```

Dev simulator run through XcodeBuildMCP:

- session defaults should point to:
  - project: `/Users/elibot/github/avalsys/public/tune-av/apps/ios/TuneAV.xcodeproj`
  - scheme: `TuneAV`
  - simulator: `iPhone 17 Pro`
  - bundle id: `com.avalsys.tuneav.dev`
- build/run extra args:

```text
TUNEAV_BUNDLE_IDENTIFIER=com.avalsys.tuneav.dev
-destination
id=8EA3138B-0338-4CB8-B21C-EB069FCEB0B7
```

## Open Questions

- Should Search automatically switch to `All radio` when the query is clearly non-music?
- Should Home include a small "More live radio" section immediately after music genres or lower on the page?
- Should Avi emotion be centralized in a single model/helper before redesigning the player?
- Should station artwork expansion happen in this phase or wait until backend artwork is more stable?

