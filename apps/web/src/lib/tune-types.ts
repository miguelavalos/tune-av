export type TuneAccessMode = "signedInFree" | "signedInPro";
export type TunePlanTier = "free" | "pro";
export type TuneFeedbackValue = "liked" | "not_for_me" | "disliked";
export type TuneDiscoveryMode = "music" | "allRadio";
export type TuneListeningSource = "home" | "search" | "library" | "music" | "avi" | "player" | "unknown";
export type TuneListeningEndedReason = "station_changed" | "paused" | "app_backgrounded" | "app_closed" | "stream_error" | "unknown";

export interface TuneStationArtwork {
  status: "none" | "queued" | "generated" | "failed" | "blocked";
  url: string | null;
  version: string | null;
}

export interface TuneStationDiscoveryProfile {
  musicDiscoveryScore: number;
  musicLevel: string;
  speechLevel: string;
  newsLevel: string;
  sportsLevel: string;
  adLoad: string;
  metadataQuality: string;
  attentionMode: string;
  bestFor: string[];
  notIdealFor: string[];
  genres: string[];
  moods: string[];
  reasons: string[];
}

export interface TuneStationEditorial {
  summary: string;
  primaryFormat: string;
  secondaryFormats: string[];
  musicIntensity: string;
  speechIntensity: string;
  languages: string[];
  audience: string[];
  programming: string[];
  sourceUrls: string[];
  discoveryProfile?: TuneStationDiscoveryProfile;
  confidence: string;
  reviewStatus: string;
  updatedAt: string;
}

export interface TuneStation {
  id: string;
  name: string;
  country: string | null;
  countryCode: string | null;
  state: string | null;
  language: string | null;
  languageCodes: string[];
  tags: string | null;
  streamURL: string;
  faviconURL: string | null;
  bitrate: number | null;
  codec: string | null;
  homepageURL: string | null;
  votes: number;
  clickCount: number;
  clickTrend: number;
  isHLS: boolean;
  hasExtendedInfo: boolean;
  hasSSLError: boolean;
  lastCheckOKAt: string | null;
  geoLatitude: number | null;
  geoLongitude: number | null;
  canonicalStationId?: string;
  category?: "music" | "sports" | "news" | "talk" | "mixed" | "unknown";
  visibility?: "public" | "unlisted" | "hidden" | "quarantined";
  qualityScore?: number;
  enrichmentStatus?: "enriched" | "pendingEnrichment" | "providerFallback" | "localOnly" | "bundled";
  metadataUpdatedAt?: string;
  artwork?: TuneStationArtwork;
  editorial?: TuneStationEditorial;
}

export interface TuneStationSearchResponse {
  stations: TuneStation[];
  pagination?: {
    total: number | null;
    limit: number;
    returned: number;
    hasMore: boolean;
    nextCursor: string | null;
    totalIsExact: boolean;
  };
  provider: "radioBrowser";
  generatedAt: string;
}

export interface TuneSearchParams {
  q?: string;
  country?: string;
  countryCode?: string;
  language?: string;
  tag?: string;
  mode?: TuneDiscoveryMode;
  cursor?: string | null;
  locale?: string;
  limit?: number;
}

export interface TunePopularParams {
  countryCode?: string;
  language?: string;
  tag?: string;
  locale?: string;
  surface?: "home" | "avi" | "discover";
  limit?: number;
}

export interface TuneStationFeedbackRecord {
  stationID: string;
  feedback: TuneFeedbackValue;
  updatedAt: string;
}

export interface TuneTrackFeedbackRecord {
  trackKey: string;
  title: string;
  artist: string | null;
  stationID: string | null;
  feedback: TuneFeedbackValue;
  updatedAt: string;
}

export interface TuneFeedbackSnapshot {
  generatedAt: string;
  stationFeedback: TuneStationFeedbackRecord[];
  trackFeedback: TuneTrackFeedbackRecord[];
}

export interface TuneListeningSessionInput {
  id: string;
  stationId: string;
  stationName: string;
  startedAt: string;
  endedAt: string;
  durationSeconds: number;
  source: TuneListeningSource;
  endedReason: TuneListeningEndedReason;
  trackDetectedCount: number;
}

export interface TuneListeningSessionsResponse {
  accepted: number;
  duplicate: number;
  rejected: number;
}

export interface TuneUserSummary {
  generatedAt: string;
  period: "7d";
  limit: number;
  accessMode: "localFallback" | "signedInFree" | "signedInPro";
  radio: {
    cards: {
      saved: { count: number };
      recent: { count: number };
      topWeek: { count: number };
      tuned: { count: number };
    };
    topStations: Array<{
      stationId: string;
      stationName: string;
      listeningSeconds7d: number;
      sessionCount7d: number;
      discoveryCount: number;
      discoveryCount7d: number;
      lastListenedAt: string | null;
      feedback: TuneFeedbackValue | null;
      rankScore: number;
    }>;
  };
  music: {
    cards: {
      songs: { count: number };
      artists: { count: number };
      radios: { count: number };
      history: { count: number };
    };
    latestDiscoveries: TuneDiscoveredTrack[];
  };
}

export interface FavoriteStationRecord {
  station: TuneStation;
  createdAt: string | null;
  deletedAt?: string | null;
}

export interface TuneDiscoveredTrack {
  discoveryID: string;
  trackKey: string | null;
  title: string;
  artist: string | null;
  stationID: string;
  stationName: string;
  artworkURL: string | null;
  stationArtworkURL: string | null;
  playedAt: string;
  markedInterestedAt: string | null;
  hiddenAt: string | null;
  deletedAt: string | null;
  updatedAt: string | null;
}

export interface TuneLibrarySnapshot {
  favorites: FavoriteStationRecord[];
  savedDiscoveries: TuneDiscoveredTrack[];
}

export interface TuneAccessLimits {
  favoriteStations: number | null;
  recentStations: number | null;
  discoveredTracks: number | null;
  savedTracks: number | null;
  aviActionsPerDay: number | null;
  lyricsSearchesPerDay: number | null;
  webSearchesPerDay: number | null;
  youtubeSearchesPerDay: number | null;
  appleMusicSearchesPerDay: number | null;
  spotifySearchesPerDay: number | null;
  discoverySharesPerDay: number | null;
}

export interface TuneAccessCapabilities {
  isSignedIn: boolean;
  canUseBackend: boolean;
  canUsePremiumFeatures: boolean;
  canUseCloudSync: boolean;
  canManagePlan: boolean;
}

export interface TuneAccessState {
  accessMode: TuneAccessMode;
  planTier: TunePlanTier;
  capabilities: TuneAccessCapabilities;
  limits: TuneAccessLimits;
}

