# Tune AV App Review Response - Guideline 5.2.3

Submission ID: b3813c06-abf0-44c2-af9e-d46a6fc44e99
Review date: May 07, 2026
Version reviewed: 1.0 (1)

## Message to App Review

Hello App Review Team,

Thank you for reviewing Tune AV.

Tune AV is a live radio player and station discovery app. It discovers publicly listed radio stations through the open Radio Browser API and plays the public stream URLs published for those radio stations. Tune AV does not host, upload, download, convert, record, cache, or redistribute third-party audio or video content. The app does not enable file sharing, media extraction, offline saving, or downloading from YouTube, Spotify, Apple Music, SoundCloud, Vimeo, or any other third-party media catalog.

Radio Browser documents that its API is free and open source and may be used in free and non-free software:
https://api.radio-browser.info/

Tune AV uses Radio Browser only as a public station directory. The app requests station metadata, filters out broken stations, and connects playback directly to the public stream URL returned for each station. Radio station availability, programming, stream quality, metadata, artwork, and rights remain controlled by the individual station or stream operator.

Tune AV also contains optional search links for discovered track metadata, including web search, YouTube search, Apple Music search, and Spotify search. These features only open search result pages. Tune AV does not access private catalogs, bypass access controls, embed unauthorized media playback from those services, download media, or convert media.

We have attached a short third-party services and content-rights summary for this submission. Please let us know if you need any additional clarification or if there is a specific station, service, or feature that requires further documentation.

Best regards,

Avalsys

## Third-Party Services and Content-Rights Summary

### 1. Radio station discovery

Provider:
Radio Browser

Relevant URL:
https://api.radio-browser.info/

Use in Tune AV:
Tune AV searches the Radio Browser public station directory for live radio stations by station name, country, language, and tag. The app uses station metadata including name, country, language, tags, homepage URL, favicon URL, stream URL, codec/bitrate fields, and station health fields such as `lastcheckok`.

Reason this is allowed:
Radio Browser states that the API is free and open source and says: "You may use it in free and non free software." Tune AV uses the API as a public directory and does not claim ownership of the Radio Browser database or of any station content.

### 2. Radio stream playback

Provider:
Individual radio stations and public stream hosts listed in Radio Browser.

Use in Tune AV:
Tune AV connects the device player directly to the public stream URL returned for a selected station. Audio content is streamed live from the station or its stream host.

Tune AV limitations:

- Tune AV does not host third-party audio.
- Tune AV does not record streams.
- Tune AV does not download streams for offline playback.
- Tune AV does not convert audio or video.
- Tune AV does not redistribute stream files.
- Tune AV does not provide illegal file sharing.
- Tune AV does not bypass paywalls, DRM, login requirements, geo-blocks, or access controls.
- Tune AV hides stations marked as broken by the station directory.

Rights position:
Tune AV acts as a live radio directory/player for publicly published station streams. Station operators and stream hosts remain responsible for the programming and broadcast rights of their own streams. Tune AV does not alter, rehost, or republish that content.

### 3. Track metadata and artwork

Provider:
Stream metadata from live radio streams, station metadata from Radio Browser, and artwork lookup services where available.

Use in Tune AV:
Tune AV may display currently playing title/artist metadata when a radio stream exposes it. The app may show station artwork/favicon or track artwork when available.

Tune AV limitations:

- Metadata is informational only.
- Artwork and station logos are not sold, sublicensed, or redistributed as standalone assets.
- Metadata and artwork availability may vary by station.

### 4. YouTube, Apple Music, Spotify, and web search links

Providers:
YouTube, Apple Music, Spotify, and general web search.

Use in Tune AV:
Tune AV creates normal search-result URLs for discovered song/artist metadata and opens those pages in an in-app browser or the user's browser.

Tune AV limitations:

- Tune AV does not use YouTube, Apple Music, or Spotify APIs for catalog playback.
- Tune AV does not embed unauthorized media playback from those services.
- Tune AV does not download, convert, save, or extract audio/video from those services.
- Tune AV does not bypass account requirements, subscriptions, DRM, region restrictions, or platform access controls.

### 5. App behavior relevant to Guideline 5.2.3

Tune AV does not include any feature to download, save offline, convert, record, rip, extract, or share media files from third-party audio/video services. The only saved music-related data in the app is local metadata such as a discovered track title/artist and the user's favorites/recents.

The app's playback feature is live radio streaming from public station URLs. The app's external music features are search links only.
