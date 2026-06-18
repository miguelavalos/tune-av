import { Filter, Loader2, Radio, Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { StationDetailsPanel, TuneStationCard } from "@/components/tune-station-card";
import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { allRadioTags, musicGenreTags } from "@/lib/tune-station";
import { useTune } from "@/lib/tune-store";
import type { TuneStation } from "@/lib/tune-types";

const countryOptions = [
  { code: "", label: "Worldwide" },
  { code: "ES", label: "Spain" },
  { code: "US", label: "United States" },
  { code: "FR", label: "France" },
  { code: "DE", label: "Germany" },
  { code: "GB", label: "United Kingdom" },
  { code: "CA", label: "Canada" }
];

export function TuneListen() {
  const tune = useTune();
  const labels = tuneFunctionalText[useAppsAvLocale()].listen;
  const [query, setQuery] = useState("");
  const [countryCode, setCountryCode] = useState(tune.settings.preferredCountryCode);
  const [selectedStation, setSelectedStation] = useState<TuneStation | null>(null);
  const tags = tune.settings.discoveryMode === "music" ? musicGenreTags : allRadioTags;

  useEffect(() => {
    if (tune.search.stations.length === 0 && !tune.search.isLoading) {
      void tune.refreshPopular();
    }
  }, []);

  const favoriteIds = useMemo(() => new Set(tune.favoriteStations.map((station) => station.id)), [tune.favoriteStations]);

  function submitSearch(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    void tune.searchStations({
      q: query,
      countryCode,
      tag: tune.settings.preferredTag,
      mode: tune.settings.discoveryMode,
      reset: true,
      source: "search"
    });
  }

  function selectTag(tag: string) {
    const next = tune.settings.preferredTag === tag ? "" : tag;
    tune.setPreferredTag(next);
    void tune.searchStations({ q: query, countryCode, tag: next, mode: tune.settings.discoveryMode, reset: true, source: "search" });
  }

  function selectCountry(code: string) {
    setCountryCode(code);
    tune.setPreferredCountry(code);
    void tune.searchStations({ q: query, countryCode: code, tag: tune.settings.preferredTag, mode: tune.settings.discoveryMode, reset: true, source: "search" });
  }

  return (
    <div className="grid gap-6">
      <Card className="tune-signal gap-0 rounded-lg border-[#234c58] p-5 text-white shadow-lg shadow-[#071b22]/18">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="flex items-center gap-2 text-sm font-semibold text-[#29d3c8]">
              <Radio className="size-4" aria-hidden="true" />
              Tune AV Radio
            </p>
            <h1 className="mt-3 text-3xl font-semibold leading-tight">{labels.title}</h1>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-white/72">{labels.body}</p>
          </div>
          <div className="flex rounded-lg border border-white/14 bg-white/8 p-1">
            <button className={modeClass(tune.settings.discoveryMode === "music")} type="button" onClick={() => tune.setDiscoveryMode("music")}>{labels.music}</button>
            <button className={modeClass(tune.settings.discoveryMode === "allRadio")} type="button" onClick={() => tune.setDiscoveryMode("allRadio")}>{labels.allRadio}</button>
          </div>
        </div>

        <form className="mt-6 grid gap-3 lg:grid-cols-[1fr_12rem_12rem_auto]" onSubmit={submitSearch}>
          <label className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#53617a]" aria-hidden="true" />
            <Input className="h-11 rounded-lg border-white/18 bg-white text-[#112a55] pl-9" placeholder={labels.searchPlaceholder} value={query} onChange={(event) => setQuery(event.target.value)} />
          </label>
          <select aria-label={labels.countries.worldwide} className="h-11 rounded-lg border border-white/18 bg-white px-3 text-sm font-semibold text-[#112a55]" value={countryCode} onChange={(event) => selectCountry(event.target.value)}>
            {countryOptions.map((country) => <option key={country.code} value={country.code}>{countryLabel(country.code, labels.countries)}</option>)}
          </select>
          <select aria-label={labels.genre} className="h-11 rounded-lg border border-white/18 bg-white px-3 text-sm font-semibold text-[#112a55]" value={tune.settings.preferredTag} onChange={(event) => selectTag(event.target.value)}>
            <option value="">{labels.genreAll}</option>
            {tags.map((tag) => <option key={tag} value={tag}>{tag}</option>)}
          </select>
          <Button className="h-11 rounded-lg bg-[#29d3c8] px-5 text-[#10284f] hover:bg-[#7be6df]" type="submit">
            <Filter className="size-4" />
            {labels.search}
          </Button>
        </form>
      </Card>

      <StationDetailsPanel feedback={selectedStation ? tune.stationFeedback[selectedStation.id]?.feedback : undefined} station={selectedStation} onClose={() => setSelectedStation(null)} onFeedback={tune.setStationFeedback} />

      <section className="grid gap-3">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h2 className="text-xl font-semibold text-[#112a55]">{query || tune.settings.preferredTag || countryCode ? labels.stationResults : labels.subtitle}</h2>
            <p className="text-sm text-[#53617a]">{tune.search.pagination?.total ? `${tune.search.pagination.total} ${labels.possibleMatches}` : labels.subtitle}</p>
          </div>
          {tune.search.isLoading ? <Loader2 className="size-5 animate-spin text-[#087f79]" aria-hidden="true" /> : null}
        </div>

        {tune.search.error ? <ErrorCard labels={labels} message={tune.search.error} retry={() => submitSearch()} /> : null}
        {!tune.search.isLoading && tune.search.stations.length === 0 ? <EmptyCard labels={labels} /> : null}

        {tune.search.stations.map((station) => (
          <TuneStationCard
            key={`${station.id}-${station.streamURL}`}
            feedback={tune.stationFeedback[station.id]?.feedback}
            isFavorite={favoriteIds.has(station.id)}
            onDetails={setSelectedStation}
            onFeedback={tune.setStationFeedback}
            onPlay={(nextStation, source, queue) => void tune.playStation(nextStation, source, queue)}
            onToggleFavorite={tune.toggleFavorite}
            queue={tune.search.stations}
            source="search"
            station={station}
          />
        ))}

        {tune.search.pagination?.hasMore ? (
          <Button className="mx-auto mt-2 rounded-lg bg-[#112a55] px-5 text-white hover:bg-[#19396f]" disabled={tune.search.isLoadingMore} onClick={() => void tune.loadMoreStations()}>
            {tune.search.isLoadingMore ? <Loader2 className="size-4 animate-spin" /> : null}
            {labels.loadMore}
          </Button>
        ) : null}
      </section>
    </div>
  );
}

function modeClass(active: boolean) {
  return active ? "rounded-md bg-white px-3 py-2 text-sm font-semibold text-[#10284f]" : "rounded-md px-3 py-2 text-sm font-semibold text-white/72 hover:text-white";
}

function ErrorCard({ labels, message, retry }: { labels: typeof tuneFunctionalText.en.listen; message: string; retry: () => void }) {
  return (
    <Card className="rounded-lg border-[#c36868] bg-[#fff4f2] p-5 text-[#681f1f]">
      <p className="font-semibold">{labels.errorTitle}</p>
      <p className="mt-1 text-sm">{message}</p>
      <Button className="mt-3 rounded-lg" variant="outline" onClick={retry}>{labels.retry}</Button>
    </Card>
  );
}

function EmptyCard({ labels }: { labels: typeof tuneFunctionalText.en.listen }) {
  return (
    <Card className="rounded-lg border-dashed border-[#c8ad72] bg-[#fff8df]/72 p-8 text-center text-[#112a55]">
      <h2 className="text-2xl font-semibold">{labels.emptyTitle}</h2>
      <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-[#53617a]">{labels.emptyBody}</p>
    </Card>
  );
}

function countryLabel(code: string, countries: typeof tuneFunctionalText.en.listen.countries) {
  return countries[(code || "worldwide") as keyof typeof countries] ?? code;
}
