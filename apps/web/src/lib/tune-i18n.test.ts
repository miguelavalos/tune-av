import { describe, expect, test } from "vite-plus/test";
import { localizedTunePath, tuneText } from "@/lib/tune-i18n";

const locales = ["en", "es", "ca", "fr", "de"] as const;

function leafKeys(value: unknown, prefix = ""): string[] {
  if (typeof value !== "object" || value === null) return [prefix];
  return Object.entries(value).flatMap(([key, child]) => leafKeys(child, prefix ? `${prefix}.${key}` : key));
}

describe("Tune web text", () => {
  test("keeps every locale aligned with the English key set", () => {
    const reference = leafKeys(tuneText.en).sort();
    for (const locale of locales) {
      expect(leafKeys(tuneText[locale]).sort()).toEqual(reference);
    }
  });

  test("has no empty strings in any locale", () => {
    for (const locale of locales) {
      const empty = leafKeys(tuneText[locale]).filter((path) => path.split(".").reduce<unknown>((node, key) => (node as Record<string, unknown>)[key], tuneText[locale]) === "");
      expect(empty).toEqual([]);
    }
  });

  test("keeps English paths bare and appends lang for other locales", () => {
    expect(localizedTunePath("/account", "en")).toBe("/account");
    expect(localizedTunePath("/account", "es")).toBe("/account?lang=es");
    expect(localizedTunePath("/settings?tab=plan", "ca")).toBe("/settings?tab=plan&lang=ca");
  });
});
