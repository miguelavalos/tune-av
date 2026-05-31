# Station Info UI Contract

This document describes the station detail shape that Tune AV iOS can render.
It is a public frontend contract, not an operations runbook.

## iOS Display Contract

The iOS app can render a station with only public directory data. When richer
station info is available, the `Info radio` card can show:

- editorial summary;
- primary format and music/speech intensity chips;
- up to two secondary format chips;
- music discovery score;
- discovery metrics for music, speech, news, sports, and ads;
- context tags from genres, moods, programming, and languages.

When no usable summary exists, the app keeps the same `Info radio` UI and shows
a pending or unavailable state.

## Expected Client Fields

The iOS UI can use this public shape when present:

```text
editorial.summary
editorial.primaryFormat
editorial.secondaryFormats
editorial.musicIntensity
editorial.speechIntensity
editorial.languages
editorial.audience
editorial.programming
editorial.discoveryProfile.musicDiscoveryScore
editorial.discoveryProfile.musicLevel
editorial.discoveryProfile.speechLevel
editorial.discoveryProfile.newsLevel
editorial.discoveryProfile.sportsLevel
editorial.discoveryProfile.adLoad
editorial.discoveryProfile.genres
editorial.discoveryProfile.moods
editorial.confidence
editorial.updatedAt
```

The app can also use public station identity, category, visibility, quality,
status, and artwork fields when they are available in the station snapshot.

## Content Quality Rules

Editorial text should be written for listeners.

Good station info:

- says what the station is useful for;
- uses listener-facing genre, mood, format, and language terms;
- avoids internal catalog reasoning;
- avoids raw URLs, service/source names, and implementation details;
- keeps summaries short enough for a compact mobile card.

Avoid surfacing technical phrases such as:

- catalog quality scores;
- stream health status;
- bitrate explanations;
- internal queue status;
- source diagnostics.

Those details can exist outside the UI, but the iOS `Info radio` card should not
rely on them for visible copy.

## Reconciliation Behavior

The app can open a station from search results, saved radios, recent radios, now
playing, or local history. Some of those sources may hold an older station
snapshot.

When a selected station has weaker station info than a newer local or fetched
snapshot, iOS should prefer the richer visible station details and remember them
locally when appropriate.

## iOS Verification Checklist

After a station-info display change:

- Search for a known station family and confirm expected stations appear.
- Open a station from search and confirm `Info radio` shows enriched details
  when present.
- Open the same station from saved/recent radios and confirm the visible station
  details stay consistent.
- Confirm stations without richer info show the fallback state.
- Confirm no private URL, service secret, or internal diagnostic appears in
  visible UI.
