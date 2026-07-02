import { describe, expect, test } from "vite-plus/test";
import { normalizePersistedSyncStatus, normalizeRestoredSyncStatus } from "@/lib/tune-store";

describe("Tune store sync status persistence", () => {
  test("does not restore stale transient sync failures", () => {
    expect(normalizeRestoredSyncStatus("failed")).toBe("idle");
    expect(normalizeRestoredSyncStatus("syncing")).toBe("idle");
    expect(normalizeRestoredSyncStatus("conflict")).toBe("idle");
    expect(normalizeRestoredSyncStatus("synced")).toBe("synced");
    expect(normalizeRestoredSyncStatus(undefined)).toBe("idle");
  });

  test("persists only stable sync state", () => {
    expect(normalizePersistedSyncStatus("failed")).toBe("idle");
    expect(normalizePersistedSyncStatus("syncing")).toBe("idle");
    expect(normalizePersistedSyncStatus("conflict")).toBe("idle");
    expect(normalizePersistedSyncStatus("synced")).toBe("synced");
  });
});
