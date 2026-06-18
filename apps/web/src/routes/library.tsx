import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Heart, Music, Radio, RotateCcw, Search, SlidersHorizontal } from "lucide-react";
import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { StationDetailsPanel, TuneStationCard } from "@/components/tune-station-card";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { hasMusicSignal } from "@/lib/tune-station";
import { useTune } from "@/lib/tune-store";
import type { TuneStation } from "@/lib/tune-types";
import { localizedTunePath, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/library")({
  component: LibraryRoute
});

type LibraryMode = "overview" | "favorites" | "recents" | "tuned" | "music";

function LibraryRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const labels = tuneFunctionalText[locale].library;
  const tune = useTune();
  const [mode, setMode] = useState<LibraryMode>("overview");
  const [query, setQuery] = useState("");
  const [selectedStation, setSelectedStation] = useState<TuneStation | null>(null);
  const favoriteIds = useMemo(() => new Set(tune.favoriteStations.map((station) => station.id)), [tune.favoriteStations]);
  const tunedStations = useMemo(() => [...tune.favoriteStations, ...tune.recentStations].filter((station, index, stations) => tune.stationFeedback[station.id] && stations.findIndex((item) => item.id === station.id) === index), [tune.favoriteStations, tune.recentStations, tune.stationFeedback]);
  const musicStations = useMemo(() => [...tune.favoriteStations, ...tune.recentStations].filter((station, index, stations) => hasMusicSignal(station) && stations.findIndex((item) => item.id === station.id) === index), [tune.favoriteStations, tune.recentStations]);
  const stations = mode === "favorites" ? tune.favoriteStations : mode === "recents" ? tune.recentStations : mode === "tuned" ? tunedStations : mode === "music" ? musicStations : [];
  const filteredStations = stations.filter((station) => `${station.name} ${station.country ?? ""} ${station.tags ?? ""}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <ProtectedRoute>
      <TuneAppShell>
        <div className="grid gap-6">
          <Card className="tune-paper gap-0 rounded-lg border-[#d7c494] p-5 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><SlidersHorizontal className="size-4" /> {text.nav.library}</p>
                <h1 className="mt-2 text-3xl font-semibold">{labels.title}</h1>
                <p className="mt-3 max-w-2xl text-sm leading-6 text-[#53617a]">{labels.body}</p>
              </div>
              <Button asChild className="rounded-lg bg-[#112a55] text-white hover:bg-[#19396f]">
                <Link to={localizedTunePath("/listen", locale)}><Radio className="size-4" /> {labels.add}</Link>
              </Button>
            </div>
            <div className="mt-6 grid gap-3 sm:grid-cols-4">
              <Metric icon={<Heart className="size-4" />} label={labels.metrics.favorites} value={tune.favoriteStations.length} onClick={() => setMode("favorites")} />
              <Metric icon={<RotateCcw className="size-4" />} label={labels.metrics.recent} value={tune.recentStations.length} onClick={() => setMode("recents")} />
              <Metric icon={<SlidersHorizontal className="size-4" />} label={labels.metrics.tuned} value={tunedStations.length} onClick={() => setMode("tuned")} />
              <Metric icon={<Music className="size-4" />} label={labels.metrics.music} value={musicStations.length} onClick={() => setMode("music")} />
            </div>
          </Card>

          <StationDetailsPanel feedback={selectedStation ? tune.stationFeedback[selectedStation.id]?.feedback : undefined} station={selectedStation} onClose={() => setSelectedStation(null)} onFeedback={tune.setStationFeedback} />

          {mode === "overview" ? (
            <OverviewSection labels={labels} setMode={setMode} />
          ) : (
            <section className="grid gap-3">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <h2 className="text-xl font-semibold text-[#112a55]">{modeTitle(mode, labels)}</h2>
                  <p className="text-sm text-[#53617a]">{filteredStations.length} {labels.stationCount}</p>
                </div>
                <label className="relative sm:w-72">
                  <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#53617a]" />
                  <Input className="rounded-lg bg-white pl-9" placeholder={labels.filter} value={query} onChange={(event) => setQuery(event.target.value)} />
                </label>
              </div>
              {filteredStations.length === 0 ? (
                <Card className="rounded-lg border-dashed border-[#c8ad72] bg-[#fff8df]/72 p-8 text-center text-[#112a55]">
                  <h2 className="text-2xl font-semibold">{labels.emptyTitle}</h2>
                  <p className="mt-2 text-sm text-[#53617a]">{labels.emptyBody}</p>
                </Card>
              ) : null}
              {filteredStations.map((station) => (
                <TuneStationCard
                  key={`${mode}-${station.id}`}
                  feedback={tune.stationFeedback[station.id]?.feedback}
                  isFavorite={favoriteIds.has(station.id)}
                  onDetails={setSelectedStation}
                  onFeedback={tune.setStationFeedback}
                  onPlay={(nextStation, source, queue) => void tune.playStation(nextStation, source, queue)}
                  onToggleFavorite={tune.toggleFavorite}
                  queue={filteredStations}
                  source="library"
                  station={station}
                />
              ))}
            </section>
          )}
        </div>
      </TuneAppShell>
    </ProtectedRoute>
  );
}

function Metric({ icon, label, onClick, value }: { icon: ReactNode; label: string; onClick: () => void; value: number }) {
  return (
    <button className="rounded-lg border border-[#d7c494] bg-[#fff8df]/76 p-4 text-left transition hover:border-[#087f79]" type="button" onClick={onClick}>
      <div className="flex items-center gap-2 text-sm font-semibold text-[#087f79]">{icon}{label}</div>
      <div className="mt-2 text-3xl font-semibold text-[#112a55]">{value}</div>
    </button>
  );
}

function OverviewSection({ labels, setMode }: { labels: typeof tuneFunctionalText.en.library; setMode: (mode: LibraryMode) => void }) {
  return (
    <Card className="rounded-lg border-dashed border-[#c8ad72] bg-[#fff8df]/72 p-8 text-center text-[#112a55]">
      <h2 className="text-2xl font-semibold">{labels.chooseTitle}</h2>
      <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-[#53617a]">{labels.chooseBody}</p>
      <div className="mt-5 flex flex-wrap justify-center gap-2">
        {(["favorites", "recents", "tuned", "music"] as LibraryMode[]).map((item) => <Button key={item} className="rounded-lg" variant="outline" onClick={() => setMode(item)}>{modeTitle(item, labels)}</Button>)}
      </div>
    </Card>
  );
}

function modeTitle(mode: LibraryMode, labels: typeof tuneFunctionalText.en.library) {
  return labels.modes[mode];
}
