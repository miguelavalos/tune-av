import { readFileSync } from "node:fs";
import { describe, expect, it } from "vite-plus/test";

describe("music discovery actions", () => {
  const routeSource = readFileSync(new URL("./music.tsx", import.meta.url), "utf8");
  const textSource = readFileSync(new URL("../lib/tune-functional-text.ts", import.meta.url), "utf8");

  it("keeps destructive discovery removal behind a localized confirmation", () => {
    expect(routeSource).toContain("window.confirm(labels.confirmRemove)");
    expect(routeSource).toContain("labels.actions.remove");
    expect(textSource).toContain("confirmRemove");
  });

  it("keeps music action labels in functional text instead of route literals", () => {
    expect(routeSource).toContain("labels.actions.save");
    expect(routeSource).toContain("labels.actions.unsave");
    expect(routeSource).toContain("label: labels.lyrics");
    expect(routeSource).not.toContain('label="Remove"');
    expect(routeSource).not.toContain('label: "Lyrics"');
  });
});
