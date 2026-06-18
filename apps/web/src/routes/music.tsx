import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ExternalLink, EyeOff, Music, Radio, Search, Star, Trash2, Undo2 } from "lucide-react";
import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAccountArea } from "@/components/tune-account-area";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { getLocalizedTuneProductConfig } from "@/lib/tune-config";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { useTune } from "@/lib/tune-store";
import type { TuneDiscoveredTrack } from "@/lib/tune-types";
import { localizedTunePath, useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/music")({
  component: MusicRoute
});

type MusicMode = "songs" | "saved" | "hidden" | "artists";

function MusicRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const labels = tuneFunctionalText[locale].music;
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const productConfig = getLocalizedTuneProductConfig(locale);
  const tune = useTune();
  const [mode, setMode] = useState<MusicMode>("songs");
  const [query, setQuery] = useState("");
  const visible = mode === "saved" ? tune.savedDiscoveries : mode === "hidden" ? tune.discoveries.filter((item) => item.hiddenAt && !item.deletedAt) : tune.visibleDiscoveries;
  const filtered = visible.filter((item) => `${item.title} ${item.artist ?? ""} ${item.stationName}`.toLowerCase().includes(query.toLowerCase()));
  const artists = useMemo(() => artistSummaries(tune.visibleDiscoveries), [tune.visibleDiscoveries]);

  return (
    <ProtectedRoute>
      <AppShell accountArea={<TuneAccountArea />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={productConfig}>
        <div className="grid gap-6">
          <Card className="tune-paper rounded-lg border-[#d7c494] p-5 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><Music className="size-4" /> {text.nav.music}</p>
                <h1 className="mt-2 text-3xl font-semibold">{labels.title}</h1>
                <p className="mt-3 max-w-2xl text-sm leading-6 text-[#53617a]">{labels.body}</p>
              </div>
              <Button asChild className="rounded-lg bg-[#112a55] text-white hover:bg-[#19396f]">
                <Link to={localizedTunePath("/listen", locale)}><Radio className="size-4" /> {labels.findStations}</Link>
              </Button>
            </div>
            <div className="mt-6 flex flex-wrap gap-2">
              {(["songs", "saved", "hidden", "artists"] as MusicMode[]).map((item) => <Button key={item} className="rounded-lg" variant={mode === item ? "default" : "outline"} onClick={() => setMode(item)}>{modeTitle(item, labels)}</Button>)}
            </div>
          </Card>

          <label className="relative max-w-md">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#53617a]" />
            <Input className="rounded-lg bg-white pl-9" placeholder={labels.filter} value={query} onChange={(event) => setQuery(event.target.value)} />
          </label>

          {mode === "artists" ? (
            <div className="grid gap-3 md:grid-cols-2">
              {artists.map((artist) => (
                <Card key={artist.name} className="rounded-lg border-[#d7c494] bg-white/82 p-4 text-[#112a55]">
                  <h2 className="font-semibold">{artist.name}</h2>
                  <p className="mt-1 text-sm text-[#53617a]">{artist.count} discoveries · {artist.stations.slice(0, 3).join(", ")}</p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <ExternalSearchButtons query={artist.name} tune={tune} />
                  </div>
                </Card>
              ))}
            </div>
          ) : (
            <div className="grid gap-3">
              {filtered.length === 0 ? <EmptyMusic labels={labels} /> : null}
              {filtered.map((discovery) => <DiscoveryRow key={discovery.discoveryID} discovery={discovery} />)}
            </div>
          )}
        </div>
      </AppShell>
    </ProtectedRoute>
  );
}

function DiscoveryRow({ discovery }: { discovery: TuneDiscoveredTrack }) {
  const tune = useTune();
  const saved = Boolean(discovery.markedInterestedAt);
  return (
    <Card className="rounded-lg border-[#d7c494] bg-white/82 p-4 text-[#112a55]">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0">
          <h2 className="truncate font-semibold">{discovery.title}</h2>
          <p className="mt-1 text-sm text-[#53617a]">{[discovery.artist, discovery.stationName].filter(Boolean).join(" · ")}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <IconButton active={saved} label={saved ? "Unsave" : "Save"} onClick={() => tune.toggleDiscoverySaved(discovery)}><Star className="size-4" /></IconButton>
          {discovery.hiddenAt ? <IconButton label="Restore" onClick={() => tune.restoreDiscovery(discovery)}><Undo2 className="size-4" /></IconButton> : <IconButton label="Hide" onClick={() => tune.hideDiscovery(discovery)}><EyeOff className="size-4" /></IconButton>}
          <IconButton label="Remove" onClick={() => tune.removeDiscovery(discovery)}><Trash2 className="size-4" /></IconButton>
          <ExternalSearchButtons query={[discovery.title, discovery.artist].filter(Boolean).join(" ")} tune={tune} />
        </div>
      </div>
    </Card>
  );
}

function ExternalSearchButtons({ query, tune }: { query: string; tune: ReturnType<typeof useTune> }) {
  const searches = [
    { label: "Lyrics", feature: "lyricsSearchesPerDay" as const, url: `https://www.google.com/search?q=${encodeURIComponent(`${query} lyrics`)}` },
    { label: "YouTube", feature: "youtubeSearchesPerDay" as const, url: `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}` },
    { label: "Apple", feature: "appleMusicSearchesPerDay" as const, url: `https://music.apple.com/search?term=${encodeURIComponent(query)}` },
    { label: "Spotify", feature: "spotifySearchesPerDay" as const, url: `https://open.spotify.com/search/${encodeURIComponent(query)}` }
  ];
  return searches.map((search) => (
    <a key={search.label} className="rounded-md border border-[#d7c494] bg-[#fff8df]/85 px-3 py-2 text-xs font-semibold text-[#112a55] hover:border-[#087f79]" href={search.url} rel="noreferrer" target="_blank" onClick={(event) => {
      if (!tune.recordDailyFeatureUse(search.feature, search.url)) event.preventDefault();
    }}>{search.label}</a>
  ));
}

function IconButton({ active, children, label, onClick }: { active?: boolean; children: ReactNode; label: string; onClick: () => void }) {
  return <button aria-label={label} className={active ? "inline-flex size-9 items-center justify-center rounded-md bg-[#112a55] text-white" : "inline-flex size-9 items-center justify-center rounded-md border border-[#d7c494] bg-[#fff8df]/85 text-[#112a55]"} onClick={onClick} title={label} type="button">{children}</button>;
}

function EmptyMusic({ labels }: { labels: typeof tuneFunctionalText.en.music }) {
  return (
    <Card className="rounded-lg border-dashed border-[#c8ad72] bg-[#fff8df]/72 p-8 text-center text-[#112a55]">
      <h2 className="text-2xl font-semibold">{labels.emptyTitle}</h2>
      <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-[#53617a]">{labels.emptyBody}</p>
    </Card>
  );
}

function modeTitle(mode: MusicMode, labels: typeof tuneFunctionalText.en.music) {
  return labels.modes[mode];
}

function artistSummaries(discoveries: TuneDiscoveredTrack[]) {
  const byArtist = new Map<string, { name: string; count: number; stations: string[] }>();
  for (const discovery of discoveries) {
    const name = discovery.artist?.trim();
    if (!name) continue;
    const current = byArtist.get(name) ?? { name, count: 0, stations: [] };
    current.count += 1;
    if (!current.stations.includes(discovery.stationName)) current.stations.push(discovery.stationName);
    byArtist.set(name, current);
  }
  return [...byArtist.values()].sort((a, b) => b.count - a.count);
}
