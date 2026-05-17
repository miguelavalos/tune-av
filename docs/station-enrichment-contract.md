# Station Enrichment Contract

This document describes the station enrichment shape that Tune AV iOS expects and how backend import jobs should prepare stations for that experience.

## iOS Display Contract

The iOS app can render a station with only public directory data, but the richer `Info radio` card depends on backend enrichment.

When `editorial.summary` is present and non-empty, the app shows:

- The editorial summary.
- Primary format and music/speech intensity chips.
- Up to two secondary format chips.
- Music discovery score.
- Discovery metrics for music, speech, news, sports, and ads.
- Context tags from discovery profile genres, moods, programming, and languages.

When no usable editorial summary exists, the app keeps the same `Info radio` UI and shows a pending state. The copy should communicate that Avi has not processed the station yet.

## Expected Editorial Fields

The backend should prefer this shape for enriched stations:

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
editorial.reviewStatus
editorial.updatedAt
```

The app also accepts technical enrichment outside `editorial`, such as canonical station id, category, visibility, quality score, enrichment status, and artwork.

## Content Quality Rules

Editorial text should be written for listeners, not operators.

Good enrichment:

- Says what the station is useful for.
- Uses listener-facing genre, mood, format, and language terms.
- Avoids internal catalog reasoning.
- Avoids raw URLs, provider names, and backend implementation details.
- Keeps summaries short enough for a compact mobile card.

Avoid surfacing technical phrases such as:

- Catalog quality scores.
- Stream health status.
- Bitrate explanations.
- Internal queue status.
- Provider-specific source diagnostics.

Those details can exist in backend metadata, but the iOS `Info radio` card should not rely on them for visible copy.

## Reconciliation Behavior

The app can open a station from different sources: search results, saved radios, recent radios, now playing, or local history. Some of those sources may hold an older snapshot without enrichment.

When a selected station has weaker enrichment than a cached/backend version, iOS should prefer the richer station snapshot. If a selected station is still weak, iOS can request a small bounded search to find the backend-enriched match and remember it locally.

This is a display consistency layer. It is not a replacement for backend queue processing.

## Import And Enrichment Flow

Keep source import separate from enrichment processing.

Recommended flow:

1. Discover stations from the source.
2. Normalize station name, stream URL, country, language, tags, and family identity.
3. Upsert idempotently.
4. Deduplicate stale or duplicate records.
5. Mark new or changed stations for enrichment.
6. Let the enrichment queue process bounded batches.
7. Verify search results in Tune AV.

Imports should not enrich every station inline. Inline enrichment makes source refreshes slower, harder to retry, and more expensive.

## Station Family Imports

For a broadcaster family import, store enough information to make search useful:

- Canonical family name.
- Station display name.
- Stream URL.
- Homepage or source page when public.
- Country and language.
- Format/genre tags.
- Active/inactive status.
- Last source refresh time.

After import, searching for the family name in Tune AV should return all active stations in that family without relying on duplicate public directory records.

## Cost Controls

Enrichment should be queued, deduplicated, and rate-limited.

Recommended priority model:

- Pro-user activity can enqueue higher-priority enrichment.
- Free-user activity should enqueue conservatively and deduplicate aggressively.
- Recently enriched stations should not be reprocessed unless source data changed or enrichment became stale.
- Broad imports should mark work for the queue instead of calling paid services immediately.

The backend should record enough status to explain whether a station is pending, processing, enriched, failed, or skipped.

## iOS Verification Checklist

After a backend enrichment or import change:

- Search for a known station family and confirm expected stations appear.
- Open a station from search and confirm `Info radio` shows enriched details.
- Open the same station from saved/recent radios and confirm it reconciles to the same enriched view.
- Confirm stations without enrichment show the pending state.
- Confirm no backend URL, provider secret, or internal diagnostic appears in visible UI.
