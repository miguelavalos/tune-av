import { describe, expect, test } from "vite-plus/test";
import { canAddItem, limitForFeature, signedInFreeAccess, signedInProAccess } from "@/lib/tune-access";

describe("Tune access policy", () => {
  test("keeps signed-in free limits aligned with the iOS Free policy", () => {
    expect(limitForFeature(signedInFreeAccess.limits, "favoriteStations")).toBe(15);
    expect(limitForFeature(signedInFreeAccess.limits, "recentStations")).toBe(50);
    expect(limitForFeature(signedInFreeAccess.limits, "discoveredTracks")).toBe(100);
    expect(limitForFeature(signedInFreeAccess.limits, "savedTracks")).toBe(50);
    expect(limitForFeature(signedInFreeAccess.limits, "aviActionsPerDay")).toBe(15);
    expect(signedInFreeAccess.capabilities.canUseCloudSync).toBe(false);
  });

  test("keeps signed-in pro limits unlimited for daily/external actions", () => {
    expect(limitForFeature(signedInProAccess.limits, "favoriteStations")).toBe(1_000);
    expect(limitForFeature(signedInProAccess.limits, "lyricsSearchesPerDay")).toBeNull();
    expect(limitForFeature(signedInProAccess.limits, "spotifySearchesPerDay")).toBeNull();
    expect(signedInProAccess.capabilities.canUseCloudSync).toBe(true);
  });

  test("checks bounded and unlimited collection inserts", () => {
    expect(canAddItem(14, 15)).toBe(true);
    expect(canAddItem(15, 15)).toBe(false);
    expect(canAddItem(10_000, null)).toBe(true);
  });
});
