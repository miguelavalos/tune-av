import type { TuneAccessLimits, TuneAccessMode, TuneAccessState } from "@/lib/tune-types";

const signedInFreeLimits: TuneAccessLimits = {
  favoriteStations: 15,
  recentStations: 50,
  discoveredTracks: 100,
  savedTracks: 50,
  aviActionsPerDay: 15,
  lyricsSearchesPerDay: 15,
  webSearchesPerDay: 15,
  youtubeSearchesPerDay: 15,
  appleMusicSearchesPerDay: 15,
  spotifySearchesPerDay: 15,
  discoverySharesPerDay: 15
};

const signedInProLimits: TuneAccessLimits = {
  favoriteStations: 1_000,
  recentStations: 1_000,
  discoveredTracks: 1_000,
  savedTracks: 1_000,
  aviActionsPerDay: null,
  lyricsSearchesPerDay: null,
  webSearchesPerDay: null,
  youtubeSearchesPerDay: null,
  appleMusicSearchesPerDay: null,
  spotifySearchesPerDay: null,
  discoverySharesPerDay: null
};

export const signedInFreeAccess: TuneAccessState = {
  accessMode: "signedInFree",
  planTier: "free",
  capabilities: {
    isSignedIn: true,
    canUseBackend: true,
    canUsePremiumFeatures: false,
    canUseCloudSync: false,
    canManagePlan: true
  },
  limits: signedInFreeLimits
};

export const signedInProAccess: TuneAccessState = {
  accessMode: "signedInPro",
  planTier: "pro",
  capabilities: {
    isSignedIn: true,
    canUseBackend: true,
    canUsePremiumFeatures: true,
    canUseCloudSync: true,
    canManagePlan: true
  },
  limits: signedInProLimits
};

export function fallbackAccessForMode(mode: TuneAccessMode): TuneAccessState {
  return mode === "signedInPro" ? signedInProAccess : signedInFreeAccess;
}

export function limitForFeature(limits: TuneAccessLimits, feature: keyof TuneAccessLimits) {
  return limits[feature];
}

export function canAddItem(currentCount: number, limit: number | null) {
  return limit === null || currentCount < limit;
}

