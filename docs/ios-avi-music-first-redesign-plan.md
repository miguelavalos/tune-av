# iOS Avi Music-First Redesign Plan

Status: superseded for active UI decisions.

This public-safe plan is historical context for the iOS Avi music-first
redesign. Active V1 UI, app behavior, and Avi decisions now live in the private
Apps AV documentation. Keep this file only for public-repo context and do not
update it with new private planning decisions.

## Context

Tune AV should feel clearly focused on live music radio discovery: finding stations, understanding what is playing, saving radios, cataloging tracks/artists, and tuning preferences through Avi.

Avi should be present across music-related surfaces as a curator and contextual guide, without becoming visually noisy. Artwork remains useful but secondary: station artwork and track artwork should be small, tappable, and expandable, not the main hierarchy driver.

Current baseline:

- iOS app lives in `apps/ios/TuneAV`.
- Current local work is focused on the Radios, Music, Search, and Avi detail experience.
- Simulator verification uses the `TuneAV` scheme with local signing config only when needed.
- Signing, account, and production values must remain in local non-versioned configuration.
- Public docs should stay technical and avoid non-public operational or planning details.

Hard constraints:

- Do not rewrite the app.
- Keep SwiftUI idiomatic and follow existing component patterns.
- Preserve current playback behavior and queue behavior.
- Verify iOS Simulator build at the end.
- Do not expose private endpoints, signing values, account operations, internal roadmaps, or non-public planning details in product-facing copy or public docs.

## Current Implementation Status

As of May 14, 2026, the iOS redesign direction is:

- Search no longer automatically focuses the search field or opens the keyboard when entering the screen.
- Radio, Music, and Search headings no longer use the Avi avatar as a decorative top-left page marker.
- Main app screens use tighter shared horizontal padding. Onboarding and Login may keep their own logo positioning and spacing.
- Radios and Music use summary landing screens with lightweight previews and dedicated detail pages for long lists.
- Radio owns radio content only. Music owns songs and artists only.
- Radio summary exposes saved, recent, most-played/listened, tuned/feedback, and music-related radio signals when data exists. Empty sections are hidden; an all-empty state appears when there is no useful content.
- Music summary exposes songs, artists, tuned tracks, and listening history. It does not show radio lists.
- Detail pages keep top navigation visible while scrolling, preserve search/sort controls, and default sorting toward recent listening where relevant.
- Song and artist cards follow the radio card language: compact visual identity, aligned padding, and no unrelated action buttons on the right.
- Navigating from a list to an Avi detail page must return to the exact source screen and state, not a generic tab.
- Product copy should describe the content the user is seeing, not internal rules such as preview limits, service status, roadmap plans, or implementation constraints.
- Account-connected behavior is optional and configuration-gated. Public docs should describe only the client-facing technical boundary.

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
  - Account: low.
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

- Explaining private implementation details.
- Explaining non-public operational or planning decisions.
- Long instructional text.
- Overusing Avi in settings/account.

## Avi Action Menu Guidelines

Avi actions should scale by context. Lists are for scanning and quick action; detail pages are where richer actions belong.

Principles:

- In list rows for radios, songs, and artists, keep the Avi menu minimal.
- Prefer one primary "ask Avi" entry point in the row instead of many visible controls.
- The list menu should contain only the most basic actions needed without leaving the list.
- Full action sets belong in the related detail page for the radio, song, or artist.
- Detail pages may show multiple Avi action pages, with a maximum of 4 actions per page.
- If a detail action set has 4 or fewer actions, show a single page without pagination controls.
- Use the same visual treatment, text sizing, icon sizing, spacing, and destructive-action styling across radio, song, and artist Avi menus.
- Destructive actions may use a red icon, but action text should remain the standard primary text color.

Current direction:

- Radio list: keep basic actions only, such as save/remove, open details, and website when available.
- Song list: keep a single Avi entry point; detailed song actions should move into the song detail page during the song detail redesign.
- Artist list: keep a single Avi entry point; detailed artist actions should move into the artist detail page during the artist detail redesign.
- Radio detail: continue supporting richer actions because the user is already inside the radio context.
- Future song and artist detail pages should follow the radio detail pattern: basic entry from the list, richer organized actions in detail.

### Current Avi Interaction Contract

The active iOS implementation keeps Avi contextual, while making the context explicit:

- The global Avi footer button opens Avi for the current live signal when audio is playing.
- The global Avi footer button opens the general Avi landing state when no current signal exists.
- A small waveform badge on the Avi footer button indicates that Avi has active audio context.
- Avi actions inside station cards or station detail remain scoped to that station.
- The current Avi player surface keeps playback source, previous, play/pause, next, and close-signal controls in one control row.
- Closing the active signal clears playback and returns the user to the prior screen when possible, otherwise Home.

Related radios are now a real Avi action, not just a Search shortcut:

- Avi first ranks locally available candidates against the base station.
- Similarity uses shared tags/genres, country, language, existing recommendation signals, and user feedback.
- The base station is excluded and stations with negative feedback are suppressed.
- If local candidates are thin, Avi queries the station service with the base station's primary tag, country, and language.
- Results render in Avi with a reason such as similar genre, same country, or same language.

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

Simulator run through XcodeBuildMCP:

- session defaults should point to:
  - project: `/Users/elibot/github/avalsys/public/tune-av/apps/ios/TuneAV.xcodeproj`
  - scheme: `TuneAV`
  - an available iOS simulator, for example the current `iPhone 17`
  - bundle id: use local configuration when intentionally testing a signed build flavor

Keep signing and account values in `apps/ios/Config/Local.xcconfig`, which is gitignored and must not be committed. If private local config has been removed for repository hygiene, restore or regenerate it locally before signed run verification.

Repository hygiene before commit:

```sh
bun run config:hygiene
git diff --check
plutil -lint apps/ios/TuneAV/Resources/*.lproj/Localizable.strings
```

## Open Questions

- Should Search automatically switch to `All radio` when the query is clearly non-music?
- Should Home include a small "More live radio" section immediately after music genres or lower on the page?
- Should Avi emotion be centralized in a single model/helper before redesigning the player?
- Should station artwork expansion happen in this phase or wait until backend artwork is more stable?
