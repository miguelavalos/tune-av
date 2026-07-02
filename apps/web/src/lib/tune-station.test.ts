import { describe, expect, test } from "vite-plus/test";
import { discoveryId, hasMusicSignal, scoreStationForAvi, stationIdentityKey, trackKey } from "@/lib/tune-station";
import type { TuneStation } from "@/lib/tune-types";

const baseStation: TuneStation = {
  id: "station-1",
  name: "Ràdio Indie",
  country: "Spain",
  countryCode: "ES",
  state: null,
  language: "Catalan",
  languageCodes: ["ca"],
  tags: "indie, local",
  streamURL: "https://stream.example.test/live",
  faviconURL: null,
  bitrate: 128,
  codec: "MP3",
  homepageURL: "https://radio.example.test",
  votes: 10,
  clickCount: 100,
  clickTrend: 2,
  isHLS: false,
  hasExtendedInfo: true,
  hasSSLError: false,
  lastCheckOKAt: "2026-06-18T08:00:00.000Z",
  geoLatitude: null,
  geoLongitude: null,
  category: "music",
  qualityScore: 70
};

describe("Tune station helpers", () => {
  test("normalizes station and track identity", () => {
    expect(stationIdentityKey(baseStation)).toBe("stream:https://stream.example.test/live");
    expect(trackKey("  Canción  Nueva ", " Artísta ")).toBe("cancion nueva::artista");
    expect(discoveryId("Canción Nueva", "Artísta", "station-1")).toBe("cancion-nueva::artista::station-1");
  });

  test("detects music stations from contract fields and tags", () => {
    expect(hasMusicSignal(baseStation)).toBe(true);
    expect(hasMusicSignal({ ...baseStation, category: "talk", tags: "news, public", editorial: { ...editorial(), primaryFormat: "music" } })).toBe(true);
    expect(hasMusicSignal({ ...baseStation, name: "Morning Talk", category: "talk", tags: "news, public", editorial: undefined })).toBe(false);
  });

  test("scores Avi recommendations from quality and user signals", () => {
    expect(scoreStationForAvi(baseStation, true, true, "liked")).toBeGreaterThan(scoreStationForAvi(baseStation, false, false, undefined));
    expect(scoreStationForAvi(baseStation, false, false, "disliked")).toBeLessThan(scoreStationForAvi(baseStation, false, false, "not_for_me"));
  });
});

function editorial() {
  return {
    summary: "A station summary.",
    primaryFormat: "music",
    secondaryFormats: [],
    musicIntensity: "medium",
    speechIntensity: "low",
    languages: ["ca"],
    audience: [],
    programming: [],
    sourceUrls: [],
    discoveryProfile: {
      musicDiscoveryScore: 70,
      musicLevel: "high",
      speechLevel: "low",
      newsLevel: "low",
      sportsLevel: "low",
      adLoad: "unknown",
      metadataQuality: "good",
      attentionMode: "focus",
      bestFor: [],
      notIdealFor: [],
      genres: ["indie"],
      moods: ["calm"],
      reasons: ["Strong music metadata"]
    },
    confidence: "medium",
    reviewStatus: "reviewed",
    updatedAt: "2026-06-18T08:00:00.000Z"
  };
}
