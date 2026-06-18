import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Compass, Heart, Library, Radio, Sparkles } from "lucide-react";
import { useMemo } from "react";
import type { ReactNode } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { TuneStationCard } from "@/components/tune-station-card";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { tuneBrandAssets } from "@/lib/tune-config";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { scoreStationForAvi } from "@/lib/tune-station";
import { useTune } from "@/lib/tune-store";
import { localizedTunePath, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/avi")({
  component: AviRoute
});

function AviRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const labels = tuneFunctionalText[locale].avi;
  const tune = useTune();
  const favoriteIds = useMemo(() => new Set(tune.favoriteStations.map((station) => station.id)), [tune.favoriteStations]);
  const recommendationReason = tune.recommendations.length ? labels.bodyReady : labels.bodyEmpty;

  return (
    <ProtectedRoute>
      <TuneAppShell>
        <div className="grid gap-6">
          <Card className="tune-paper gap-0 overflow-hidden rounded-lg border-[#d7c494] p-0 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
            <div className="grid lg:grid-cols-[1fr_21rem]">
              <div className="p-6 sm:p-8">
                <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><Sparkles className="size-4" /> Avi</p>
                <h1 className="mt-3 text-3xl font-semibold leading-tight">{labels.title}</h1>
                <p className="mt-4 max-w-2xl text-sm leading-6 text-[#53617a]">{recommendationReason}</p>
                <div className="mt-6 flex flex-wrap gap-3">
                  <Button asChild className="rounded-lg bg-[#112a55] text-white hover:bg-[#19396f]">
                    <Link to={localizedTunePath("/listen", locale)}><Radio className="size-4" /> {labels.search}</Link>
                  </Button>
                  <Button asChild className="rounded-lg" variant="outline">
                    <Link to={localizedTunePath("/library", locale)}><Library className="size-4" /> {labels.library}</Link>
                  </Button>
                </div>
              </div>
              <div className="relative min-h-64 overflow-hidden bg-[#10284f]">
                <img className="h-full w-full object-cover object-bottom" src={tuneBrandAssets.aviLoginPeek} alt="" />
              </div>
            </div>
          </Card>

          <div className="grid gap-4 md:grid-cols-3">
            <SignalCard icon={<Heart className="size-4" />} label={labels.labels.favorites} value={tune.favoriteStations.length} />
            <SignalCard icon={<Compass className="size-4" />} label={labels.labels.recents} value={tune.recentStations.length} />
            <SignalCard icon={<Sparkles className="size-4" />} label={labels.labels.savedTracks} value={tune.savedDiscoveries.length} />
          </div>

          <section className="grid gap-3">
            <div>
              <h2 className="text-xl font-semibold text-[#112a55]">{labels.recommended}</h2>
              <p className="text-sm text-[#53617a]">{labels.note}</p>
            </div>
            {tune.recommendations.length === 0 ? (
              <Card className="rounded-lg border-dashed border-[#c8ad72] bg-[#fff8df]/72 p-8 text-center text-[#112a55]">
                <h2 className="text-2xl font-semibold">{labels.emptyTitle}</h2>
                <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-[#53617a]">{labels.emptyBody}</p>
              </Card>
            ) : null}
            {tune.recommendations.map((station) => (
              <TuneStationCard
                key={`avi-${station.id}`}
                feedback={tune.stationFeedback[station.id]?.feedback}
                isFavorite={favoriteIds.has(station.id)}
                onFeedback={tune.setStationFeedback}
                onPlay={(nextStation, source, queue) => {
                  tune.recordDailyFeatureUse("aviActionsPerDay", nextStation.id);
                  void tune.playStation(nextStation, source, queue);
                }}
                onToggleFavorite={tune.toggleFavorite}
                queue={tune.recommendations}
                source="avi"
                station={station}
              />
            ))}
          </section>
        </div>
      </TuneAppShell>
    </ProtectedRoute>
  );
}

function SignalCard({ icon, label, value }: { icon: ReactNode; label: string; value: number }) {
  return (
    <Card className="rounded-lg border-[#d7c494] bg-[#fff8df]/80 p-4 text-[#112a55]">
      <div className="flex items-center gap-2 text-sm font-semibold text-[#087f79]">{icon}{label}</div>
      <div className="mt-2 text-3xl font-semibold">{value}</div>
    </Card>
  );
}
