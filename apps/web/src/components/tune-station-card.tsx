import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { ExternalLink, Heart, Info, Play, Radio, SignalHigh, ThumbsDown, ThumbsUp } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { stationArtworkUrl, stationDetailText, stationFallbackArtworkUrl, stationInitials, stationTags } from "@/lib/tune-station";
import type { TuneFeedbackValue, TuneListeningSource, TuneStation } from "@/lib/tune-types";

export function TuneStationCard({
  feedback,
  isFavorite,
  onDetails,
  onFeedback,
  onPlay,
  onToggleFavorite,
  queue,
  source,
  station
}: {
  feedback?: TuneFeedbackValue;
  isFavorite: boolean;
  onDetails?: (station: TuneStation) => void;
  onFeedback: (station: TuneStation, feedback: TuneFeedbackValue | null) => void;
  onPlay: (station: TuneStation, source: TuneListeningSource, queue?: TuneStation[]) => void;
  onToggleFavorite: (station: TuneStation) => void;
  queue?: TuneStation[];
  source: TuneListeningSource;
  station: TuneStation;
}) {
  const artwork = stationArtworkUrl(station);
  const tags = stationTags(station);
  const text = stationCardText[useAppsAvLocale()];

  return (
    <Card className="gap-0 rounded-lg border-[#d7c494] bg-white/82 p-4 text-[#112a55] shadow-sm">
      <div className="grid gap-4 sm:grid-cols-[4.5rem_1fr_auto] sm:items-center">
        <div className="relative flex size-[4.5rem] items-center justify-center overflow-hidden rounded-lg border border-[#d7c494] bg-[#e9f4ef]">
          <img className="h-full w-full object-cover" src={artwork ?? stationFallbackArtworkUrl(station)} alt="" />
          {!artwork ? <span className="absolute inset-x-2 bottom-2 truncate rounded bg-[#10284f]/78 px-1.5 py-0.5 text-center text-xs font-semibold text-white">{stationInitials(station)}</span> : null}
        </div>

        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate text-base font-semibold">{station.name}</h3>
            {station.enrichmentStatus === "enriched" ? <Badge>{text.guide}</Badge> : null}
            {station.hasExtendedInfo ? <Badge>{text.songInfo}</Badge> : null}
            {station.qualityScore && station.qualityScore >= 72 ? <Badge>{text.goodSignal}</Badge> : null}
          </div>
          <p className="mt-1 line-clamp-2 text-sm leading-5 text-[#53617a]">{station.editorial?.summary ?? (stationDetailText(station) || text.liveStream)}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            {tags.map((tag) => <span key={tag} className="rounded-md bg-[#edf7f1] px-2 py-1 text-xs font-semibold text-[#336046]">{tag}</span>)}
            {station.countryCode ? <span className="rounded-md bg-[#f6efd8] px-2 py-1 text-xs font-semibold text-[#72572a]">{station.countryCode}</span> : null}
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2 sm:justify-end">
          <IconButton label={text.play} onClick={() => onPlay(station, source, queue)}>
            <Play className="size-4" aria-hidden="true" />
          </IconButton>
          <IconButton active={isFavorite} label={isFavorite ? text.removeFavorite : text.favorite} onClick={() => onToggleFavorite(station)}>
            <Heart className="size-4" aria-hidden="true" />
          </IconButton>
          {onDetails ? (
            <IconButton label={text.details} onClick={() => onDetails(station)}>
              <Info className="size-4" aria-hidden="true" />
            </IconButton>
          ) : null}
        </div>
      </div>
    </Card>
  );
}

export function StationDetailsPanel({
  feedback,
  onClose,
  onFeedback,
  station
}: {
  feedback?: TuneFeedbackValue;
  onClose: () => void;
  onFeedback?: (station: TuneStation, feedback: TuneFeedbackValue | null) => void;
  station: TuneStation | null;
}) {
  const text = stationCardText[useAppsAvLocale()];
  if (!station) return null;

  return (
    <Card className="rounded-lg border-[#d7c494] bg-[#fff8df] p-5 text-[#112a55]">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><SignalHigh className="size-4" /> {text.details}</p>
          <h2 className="mt-2 text-2xl font-semibold">{station.name}</h2>
        </div>
        <Button variant="outline" className="rounded-md" onClick={onClose}>{text.close}</Button>
      </div>
      <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
        <Detail label={text.country} value={station.country ?? station.countryCode ?? text.unknown} />
        <Detail label={text.language} value={station.language ?? (station.languageCodes.join(", ") || text.unknown)} />
        <Detail label={text.format} value={station.editorial?.primaryFormat ?? station.category ?? text.unknown} />
        <Detail label={text.stream} value={[station.codec, station.bitrate ? `${station.bitrate} kbps` : null, station.isHLS ? "HLS" : null].filter(Boolean).join(" · ") || text.liveStream} />
        <Detail label={text.quality} value={station.qualityScore ? `${station.qualityScore}/100` : station.lastCheckOKAt ? text.checked : text.unknown} />
        <Detail label={text.updated} value={station.metadataUpdatedAt ? new Date(station.metadataUpdatedAt).toLocaleDateString() : text.unknown} />
      </dl>
      <div className="mt-5 flex flex-wrap gap-2">
        {onFeedback ? (
          <>
            <Button className="rounded-md" variant={feedback === "liked" ? "default" : "outline"} onClick={() => onFeedback(station, feedback === "liked" ? null : "liked")}><ThumbsUp className="size-4" /> {text.like}</Button>
            <Button className="rounded-md" variant={feedback === "not_for_me" ? "default" : "outline"} onClick={() => onFeedback(station, feedback === "not_for_me" ? null : "not_for_me")}><ThumbsDown className="size-4" /> {text.notForMe}</Button>
          </>
        ) : null}
        {station.homepageURL ? <Button asChild className="rounded-md" variant="outline"><a href={station.homepageURL} rel="noreferrer" target="_blank"><ExternalLink className="size-4" /> {text.website}</a></Button> : null}
      </div>
      {station.editorial?.discoveryProfile?.reasons.length ? (
        <div className="mt-5">
          <h3 className="text-sm font-semibold">{text.why}</h3>
          <ul className="mt-2 grid gap-2 text-sm text-[#53617a]">
            {station.editorial.discoveryProfile.reasons.slice(0, 4).map((reason) => <li key={reason}>{reason}</li>)}
          </ul>
        </div>
      ) : null}
    </Card>
  );
}

function Badge({ children }: { children: string }) {
  return <span className="rounded-md bg-[#d8f6ed] px-2 py-1 text-xs font-semibold text-[#087f79]">{children}</span>;
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="font-semibold text-[#334766]">{label}</dt>
      <dd className="mt-1 text-[#53617a]">{value}</dd>
    </div>
  );
}

function IconButton({ active, asLink, children, href, label, onClick }: { active?: boolean; asLink?: boolean; children: ReactNode; href?: string; label: string; onClick?: () => void }) {
  const className = active
    ? "inline-flex size-10 items-center justify-center rounded-md bg-[#112a55] text-white transition hover:bg-[#19396f]"
    : "inline-flex size-10 items-center justify-center rounded-md border border-[#d7c494] bg-[#fff8df]/85 text-[#112a55] transition hover:border-[#087f79] hover:text-[#087f79]";
  if (asLink && href) {
    return <a aria-label={label} className={className} href={href} rel="noreferrer" target="_blank" title={label}>{children}</a>;
  }
  return <button aria-label={label} className={className} onClick={onClick} title={label} type="button">{children}</button>;
}

const stationCardText = {
  ca: { checked: "Comprovat", close: "Tanca", country: "Pais", details: "Detalls", favorite: "Favorit", format: "Format", goodSignal: "Bon senyal", guide: "Guia", language: "Idioma", like: "M'agrada", liveStream: "Emissio en directe", notForMe: "No es per mi", play: "Reprodueix", quality: "Qualitat", removeFavorite: "Treure favorit", songInfo: "Info de canco", stream: "Stream", unknown: "Desconegut", updated: "Actualitzat", website: "Web", why: "Per que encaixa" },
  de: { checked: "Geprueft", close: "Schliessen", country: "Land", details: "Details", favorite: "Favorit", format: "Format", goodSignal: "Gutes Signal", guide: "Guide", language: "Sprache", like: "Mag ich", liveStream: "Live-Stream", notForMe: "Nicht fuer mich", play: "Abspielen", quality: "Qualitaet", removeFavorite: "Favorit entfernen", songInfo: "Songinfo", stream: "Stream", unknown: "Unbekannt", updated: "Aktualisiert", website: "Website", why: "Warum es passt" },
  en: { checked: "Checked", close: "Close", country: "Country", details: "Station details", favorite: "Favorite", format: "Format", goodSignal: "Good signal", guide: "Guide", language: "Language", like: "Like", liveStream: "Live radio stream", notForMe: "Not for me", play: "Play station", quality: "Quality", removeFavorite: "Remove favorite", songInfo: "Song info", stream: "Stream", unknown: "Unknown", updated: "Updated", website: "Website", why: "Why it fits" },
  es: { checked: "Comprobada", close: "Cerrar", country: "Pais", details: "Detalles", favorite: "Favorito", format: "Formato", goodSignal: "Buena senal", guide: "Guia", language: "Idioma", like: "Me gusta", liveStream: "Emision en directo", notForMe: "No es para mi", play: "Reproducir", quality: "Calidad", removeFavorite: "Quitar favorito", songInfo: "Info de cancion", stream: "Stream", unknown: "Desconocido", updated: "Actualizada", website: "Web", why: "Por que encaja" },
  fr: { checked: "Verifie", close: "Fermer", country: "Pays", details: "Details", favorite: "Favori", format: "Format", goodSignal: "Bon signal", guide: "Guide", language: "Langue", like: "J'aime", liveStream: "Flux radio en direct", notForMe: "Pas pour moi", play: "Lire", quality: "Qualite", removeFavorite: "Retirer le favori", songInfo: "Info titre", stream: "Flux", unknown: "Inconnu", updated: "Mis a jour", website: "Site web", why: "Pourquoi cela convient" }
};
