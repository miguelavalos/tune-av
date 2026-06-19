import { appsAvExternalSearchUrl, useAppsAvLocale } from "@avalsys/apps-av-web";
import type { AppsAvLocale } from "@avalsys/apps-av-web";
import { Link } from "@tanstack/react-router";
import { ChevronDown, ExternalLink, Heart, Info, Library, Maximize2, Music, Pause, Play, Radio, RotateCcw, Search, SkipBack, SkipForward, Sparkles, ThumbsDown, ThumbsUp, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { localizedTunePath } from "@/lib/tune-i18n";
import { stationArtworkUrl, stationDetailText, stationFallbackArtworkUrl, stationInitials } from "@/lib/tune-station";
import { useTune } from "@/lib/tune-store";
import type { TuneDiscoveredTrack, TuneStation } from "@/lib/tune-types";
import { tuneBrandAssets } from "@/lib/tune-config";

export function TunePlayer() {
  const tune = useTune();
  const station = tune.playback.currentStation;
  const [isFullPlayerOpen, setIsFullPlayerOpen] = useState(false);
  const locale = useAppsAvLocale();
  const labels = playerText[locale];

  useEffect(() => {
    document.body.classList.toggle("tune-full-player-open", isFullPlayerOpen);
    return () => document.body.classList.remove("tune-full-player-open");
  }, [isFullPlayerOpen]);

  useEffect(() => {
    document.body.classList.toggle("tune-mini-player-active", Boolean(station));
    return () => document.body.classList.remove("tune-mini-player-active");
  }, [station]);

  useEffect(() => {
    if (!station) setIsFullPlayerOpen(false);
  }, [station]);

  if (!station) return null;

  const artwork = stationArtworkUrl(station);
  const currentDiscovery = latestDiscoveryForStation(tune.visibleDiscoveries, station.id);
  const nowPlayingLine = currentDiscovery ? [currentDiscovery.artist, currentDiscovery.title].filter(Boolean).join(" - ") : labels.liveRadio;
  const status = statusText(tune.playback.status, tune.playback.error, labels);

  return (
    <>
      <div className="fixed inset-x-0 bottom-0 z-40 px-3 pb-3 sm:px-5">
        <div className="mx-auto max-w-5xl rounded-xl border border-white/14 bg-[#10284f]/96 p-2.5 text-white shadow-2xl shadow-[#071b22]/28 backdrop-blur">
          <div className="grid grid-cols-[1fr_auto] items-center gap-3 sm:grid-cols-[1fr_auto_auto]">
            <button className="flex min-w-0 items-center gap-3 rounded-lg text-left transition hover:bg-white/8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#29d3c8]" type="button" onClick={() => setIsFullPlayerOpen(true)}>
              <StationArtwork station={station} artwork={artwork} className="size-12" />
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">{station.name}</p>
                <p className="truncate text-xs text-white/64">{nowPlayingLine || status}</p>
              </div>
            </button>
            <PlayerControls labels={labels} />
            <Button className="hidden size-10 rounded-md bg-white/10 p-0 text-white hover:bg-white/18 sm:inline-flex" onClick={() => setIsFullPlayerOpen(true)} title={labels.openFull} aria-label={labels.openFull}>
              <Maximize2 className="size-4" />
            </Button>
          </div>
        </div>
      </div>

      {isFullPlayerOpen ? <FullPlayer labels={labels} locale={locale} station={station} status={status} artwork={artwork} currentDiscovery={currentDiscovery} onClose={() => setIsFullPlayerOpen(false)} /> : null}
    </>
  );
}

function FullPlayer({ artwork, currentDiscovery, labels, locale, onClose, station, status }: { artwork: string | null; currentDiscovery: TuneDiscoveredTrack | null; labels: PlayerLabels; locale: AppsAvLocale; onClose: () => void; station: TuneStation; status: string }) {
  const tune = useTune();
  const isFavorite = tune.favoriteStations.some((item) => item.id === station.id);
  const feedback = tune.stationFeedback[station.id]?.feedback;
  const recommendation = tune.recommendations.find((item) => item.id !== station.id);
  const upNext = useMemo(() => nextQueueStations(tune.playback.queue, station.id), [station.id, tune.playback.queue]);
  const stationSummary = station.editorial?.summary ?? stationDetailText(station) ?? labels.liveRadio;
  const profile = station.editorial?.discoveryProfile;
  const nowPlayingTitle = currentDiscovery?.title ?? labels.liveRadio;
  const nowPlayingSubtitle = currentDiscovery?.artist ?? (station.hasExtendedInfo ? labels.metadataPending : labels.metadataUnavailable);
  const primaryArtwork = currentDiscovery?.artworkURL ?? artwork;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-[#071b22] text-white">
      <div className="mx-auto flex min-h-screen w-full max-w-7xl flex-col px-4 py-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between gap-3">
          <Button className="size-10 rounded-md bg-white/10 p-0 text-white hover:bg-white/18" onClick={onClose} title={labels.collapse} aria-label={labels.collapse}>
            <ChevronDown className="size-5" />
          </Button>
          <p className="text-sm font-semibold text-[#29d3c8]">{labels.nowPlaying}</p>
          <Button className="size-10 rounded-md bg-white/10 p-0 text-white hover:bg-white/18" onClick={onClose} title={labels.close} aria-label={labels.close}>
            <X className="size-5" />
          </Button>
        </div>

        <section className="mt-6 grid flex-1 gap-6 lg:grid-cols-[minmax(18rem,25rem)_1fr] lg:items-center">
          <div className="mx-auto w-full max-w-md">
            <div className="relative aspect-square overflow-hidden rounded-2xl border border-white/14 bg-white/8 shadow-2xl shadow-black/28">
              <img className="h-full w-full object-cover" src={primaryArtwork ?? stationFallbackArtworkUrl(station)} alt="" />
              {!primaryArtwork ? <div className="absolute inset-x-8 bottom-8 rounded-xl bg-[#10284f]/78 px-4 py-2 text-center text-4xl font-semibold text-white backdrop-blur">{stationInitials(station)}</div> : null}
            </div>
            <div className="mt-3 flex items-center justify-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] text-white/44">
              {currentDiscovery?.artworkURL ? <Music className="size-4" /> : <Radio className="size-4" />}
              <span>{currentDiscovery?.artworkURL ? labels.trackArtwork : labels.stationArtwork}</span>
            </div>
            <div className="mt-4 rounded-xl border border-white/12 bg-white/7 p-4">
              <div className="flex items-center gap-3">
                <img className="size-14 rounded-full border border-white/12 bg-[#10284f] object-cover" src={tuneBrandAssets.aviFullBody} alt="" />
                <div className="min-w-0">
                  <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#29d3c8]">Avi</p>
                  <p className="mt-1 text-sm leading-5 text-white/72">{aviSummary(labels, station, isFavorite, feedback, tune.recentStations.length, tune.savedDiscoveries.length)}</p>
                </div>
              </div>
            </div>
          </div>

          <div className="min-w-0">
            <p className="text-sm font-semibold uppercase tracking-[0.16em] text-[#29d3c8]">{station.country ?? station.countryCode ?? labels.liveRadio}</p>
            <h1 className="mt-3 text-4xl font-semibold leading-tight sm:text-5xl">{station.name}</h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-white/70">{stationSummary}</p>

            <div className="mt-6 grid gap-3 sm:grid-cols-[1fr_auto] sm:items-center">
              <div className="rounded-xl border border-white/12 bg-white/7 p-4">
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-white/44">{labels.nowPlaying}</p>
                <h2 className="mt-2 truncate text-xl font-semibold">{nowPlayingTitle}</h2>
                <p className="mt-1 truncate text-sm text-white/64">{nowPlayingSubtitle}</p>
                {!currentDiscovery ? <p className="mt-3 text-xs leading-5 text-white/48">{labels.webMetadataNote}</p> : null}
              </div>
              <div className="rounded-xl border border-white/12 bg-white/7 p-4">
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-white/44">{labels.queue}</p>
                <p className="mt-2 text-lg font-semibold">{sourceLabel(tune.playback.queueSource, labels)}</p>
                <p className="text-sm text-white/64">{upNext.length ? upNext.slice(0, 2).map((item) => item.name).join(" / ") : labels.noQueue}</p>
              </div>
            </div>

            <div className="mt-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <PlayerControls labels={labels} large />
              <p className="text-sm text-white/58">{status}</p>
            </div>

            <div className="mt-8 grid gap-3 xl:grid-cols-2">
              <ActionPanel title={labels.aviActions} subtitle={labels.aviActionsHint}>
                <ActionButton active={isFavorite} icon={<Heart className="size-4" />} label={isFavorite ? labels.removeFavorite : labels.saveFavorite} onClick={() => tune.toggleFavorite(station)} />
                <ActionButton active={feedback === "liked"} icon={<ThumbsUp className="size-4" />} label={labels.like} onClick={() => tune.setStationFeedback(station, feedback === "liked" ? null : "liked")} />
                <ActionButton active={feedback === "not_for_me"} icon={<ThumbsDown className="size-4" />} label={labels.notForMe} onClick={() => tune.setStationFeedback(station, feedback === "not_for_me" ? null : "not_for_me")} />
                {recommendation ? <ActionButton icon={<Sparkles className="size-4" />} label={labels.playRecommended} onClick={() => {
                  tune.recordDailyFeatureUse("aviActionsPerDay", recommendation.id);
                  void tune.playStation(recommendation, "avi", tune.recommendations);
                }} /> : null}
                <ActionLink icon={<Search className="size-4" />} label={labels.tuneSimilar} to={localizedTunePath("/listen", locale)} />
                <ActionLink icon={<Library className="size-4" />} label={labels.openLibrary} to={localizedTunePath("/library", locale)} />
              </ActionPanel>

              <ActionPanel title={labels.stationActions} subtitle={station.editorial?.primaryFormat ?? labels.liveRadio}>
                <ActionLink icon={<Info className="size-4" />} label={labels.publicInfo} href={appsAvExternalSearchUrl({ engine: tune.settings.externalSearchEngine, query: `${station.name} radio` }) ?? undefined} />
                {station.homepageURL ? <ActionLink icon={<ExternalLink className="size-4" />} label={labels.website} href={station.homepageURL} /> : null}
                {profile?.genres?.slice(0, 2).map((genre) => <Badge key={genre}>{genre}</Badge>)}
                {station.codec ? <Badge>{station.codec}</Badge> : null}
                {station.bitrate ? <Badge>{`${station.bitrate} kbps`}</Badge> : null}
                {station.qualityScore ? <Badge>{`${labels.quality} ${station.qualityScore}/100`}</Badge> : null}
              </ActionPanel>
            </div>

            {currentDiscovery ? (
              <ActionPanel className="mt-3" title={labels.songActions} subtitle={[currentDiscovery.artist, currentDiscovery.title].filter(Boolean).join(" - ")}>
                <ExternalMusicAction discovery={currentDiscovery} feature="lyricsSearchesPerDay" label={labels.lyrics} url={appsAvExternalSearchUrl({ engine: tune.settings.externalSearchEngine, query: `${currentDiscovery.title} ${currentDiscovery.artist ?? ""} lyrics` }) ?? "#"} />
                <ExternalMusicAction discovery={currentDiscovery} feature="youtubeSearchesPerDay" label="YouTube" url={`https://www.youtube.com/results?search_query=${encodeURIComponent(`${currentDiscovery.title} ${currentDiscovery.artist ?? ""}`)}`} />
                <ExternalMusicAction discovery={currentDiscovery} feature="appleMusicSearchesPerDay" label="Apple Music" url={`https://music.apple.com/search?term=${encodeURIComponent(`${currentDiscovery.title} ${currentDiscovery.artist ?? ""}`)}`} />
                <ExternalMusicAction discovery={currentDiscovery} feature="spotifySearchesPerDay" label="Spotify" url={`https://open.spotify.com/search/${encodeURIComponent(`${currentDiscovery.title} ${currentDiscovery.artist ?? ""}`)}`} />
                <ActionButton active={Boolean(currentDiscovery.markedInterestedAt)} icon={<Music className="size-4" />} label={currentDiscovery.markedInterestedAt ? labels.unsaveTrack : labels.saveTrack} onClick={() => tune.toggleDiscoverySaved(currentDiscovery)} />
              </ActionPanel>
            ) : null}
          </div>
        </section>
      </div>
    </div>
  );
}

function PlayerControls({ labels, large }: { labels: PlayerLabels; large?: boolean }) {
  const tune = useTune();
  const buttonSize = large ? "size-14" : "size-10";
  const iconSize = large ? "size-6" : "size-4";

  return (
    <div className="flex items-center gap-2">
      <Button className={`${buttonSize} rounded-md bg-white/10 p-0 text-white hover:bg-white/18`} onClick={() => void tune.previousStation()} title={labels.previous} aria-label={labels.previous}>
        <SkipBack className={iconSize} />
      </Button>
      {tune.playback.status === "playing" || tune.playback.status === "loading" ? (
        <Button className={`${large ? "size-16" : buttonSize} rounded-md bg-[#29d3c8] p-0 text-[#10284f] hover:bg-[#7be6df]`} onClick={() => void tune.pausePlayback()} title={labels.pause} aria-label={labels.pause}>
          <Pause className={large ? "size-7" : iconSize} />
        </Button>
      ) : (
        <Button className={`${large ? "size-16" : buttonSize} rounded-md bg-[#29d3c8] p-0 text-[#10284f] hover:bg-[#7be6df]`} onClick={() => void tune.retryPlayback()} title={tune.playback.status === "failed" ? labels.retry : labels.play} aria-label={tune.playback.status === "failed" ? labels.retry : labels.play}>
          {tune.playback.status === "failed" ? <RotateCcw className={large ? "size-7" : iconSize} /> : <Play className={large ? "size-7" : iconSize} />}
        </Button>
      )}
      <Button className={`${buttonSize} rounded-md bg-white/10 p-0 text-white hover:bg-white/18`} onClick={() => void tune.nextStation()} title={labels.next} aria-label={labels.next}>
        <SkipForward className={iconSize} />
      </Button>
    </div>
  );
}

function ActionPanel({ children, className = "", subtitle, title }: { children: ReactNode; className?: string; subtitle: string; title: string }) {
  return (
    <section className={`rounded-xl border border-white/12 bg-white/7 p-4 ${className}`}>
      <div className="mb-4">
        <h2 className="text-lg font-semibold">{title}</h2>
        <p className="mt-1 line-clamp-2 text-sm text-white/58">{subtitle}</p>
      </div>
      <div className="flex flex-wrap gap-2">{children}</div>
    </section>
  );
}

function ActionButton({ active, icon, label, onClick }: { active?: boolean; icon: ReactNode; label: string; onClick: () => void }) {
  return (
    <button className={active ? "inline-flex items-center gap-2 rounded-md bg-[#29d3c8] px-3 py-2 text-sm font-semibold text-[#10284f]" : "inline-flex items-center gap-2 rounded-md border border-white/14 bg-white/8 px-3 py-2 text-sm font-semibold text-white hover:bg-white/14"} onClick={onClick} type="button">
      {icon}
      <span>{label}</span>
    </button>
  );
}

function ActionLink({ href, icon, label, to }: { href?: string; icon: ReactNode; label: string; to?: string }) {
  const className = "inline-flex items-center gap-2 rounded-md border border-white/14 bg-white/8 px-3 py-2 text-sm font-semibold text-white hover:bg-white/14";
  if (to) {
    return <Link className={className} to={to}>{icon}<span>{label}</span></Link>;
  }
  return <a className={className} href={href} rel="noreferrer" target="_blank">{icon}<span>{label}</span></a>;
}

function ExternalMusicAction({ discovery, feature, label, url }: { discovery: TuneDiscoveredTrack; feature: "lyricsSearchesPerDay" | "youtubeSearchesPerDay" | "appleMusicSearchesPerDay" | "spotifySearchesPerDay"; label: string; url: string }) {
  const tune = useTune();
  return (
    <a className="inline-flex items-center gap-2 rounded-md border border-white/14 bg-white/8 px-3 py-2 text-sm font-semibold text-white hover:bg-white/14" href={url} rel="noreferrer" target="_blank" onClick={(event) => {
      if (!tune.recordDailyFeatureUse(feature, discovery.trackKey ?? `${discovery.title}:${discovery.artist ?? ""}`)) event.preventDefault();
    }}>
      <ExternalLink className="size-4" />
      <span>{label}</span>
    </a>
  );
}

function StationArtwork({ artwork, className, station }: { artwork: string | null; className: string; station: TuneStation }) {
  return (
    <div className={`relative flex shrink-0 items-center justify-center overflow-hidden rounded-md bg-white/10 ${className}`}>
      <img className="h-full w-full object-cover" src={artwork ?? stationFallbackArtworkUrl(station)} alt="" />
      {!artwork ? <span className="absolute inset-x-1 bottom-1 truncate rounded bg-[#10284f]/78 px-1 text-center text-[0.62rem] font-semibold text-white">{stationInitials(station)}</span> : null}
    </div>
  );
}

function Badge({ children }: { children: string }) {
  return <span className="rounded-md border border-white/14 bg-white/8 px-3 py-2 text-sm font-semibold text-white/76">{children}</span>;
}

function latestDiscoveryForStation(discoveries: TuneDiscoveredTrack[], stationId: string) {
  return discoveries.filter((item) => item.stationID === stationId).sort((a, b) => new Date(b.playedAt).getTime() - new Date(a.playedAt).getTime())[0] ?? null;
}

function nextQueueStations(queue: TuneStation[], stationId: string) {
  const index = queue.findIndex((item) => item.id === stationId);
  if (index < 0) return queue.filter((item) => item.id !== stationId);
  return [...queue.slice(index + 1), ...queue.slice(0, index)].filter((item) => item.id !== stationId);
}

function aviSummary(labels: PlayerLabels, station: TuneStation, isFavorite: boolean, feedback: string | undefined, recentCount: number, savedCount: number) {
  if (feedback === "not_for_me") return labels.aviNotForMe;
  if (isFavorite) return labels.aviFavorite;
  if (savedCount > 0 && station.hasExtendedInfo) return labels.aviMusicSignals;
  if (recentCount > 1) return labels.aviRecentSignals;
  return labels.aviNeutral;
}

function sourceLabel(source: string, labels: PlayerLabels) {
  if (source === "avi") return "Avi";
  if (source === "library") return labels.library;
  if (source === "music") return labels.music;
  if (source === "search") return labels.search;
  if (source === "home") return labels.home;
  return labels.queueLive;
}

type PlayerLabels = {
  aviActions: string;
  aviActionsHint: string;
  aviFavorite: string;
  aviMusicSignals: string;
  aviNeutral: string;
  aviNotForMe: string;
  aviRecentSignals: string;
  close: string;
  collapse: string;
  home: string;
  library: string;
  like: string;
  liveRadio: string;
  loading: string;
  lyrics: string;
  metadataPending: string;
  metadataUnavailable: string;
  music: string;
  next: string;
  noQueue: string;
  notForMe: string;
  nowPlaying: string;
  openFull: string;
  openLibrary: string;
  pause: string;
  paused: string;
  play: string;
  playRecommended: string;
  playing: string;
  previous: string;
  publicInfo: string;
  quality: string;
  queue: string;
  queueLive: string;
  ready: string;
  removeFavorite: string;
  retry: string;
  saveFavorite: string;
  saveTrack: string;
  search: string;
  songActions: string;
  stationActions: string;
  stationArtwork: string;
  trackArtwork: string;
  tuneSimilar: string;
  unsaveTrack: string;
  webMetadataNote: string;
  website: string;
};

function statusText(status: string, error: string | null, labels: PlayerLabels) {
  if (error) return error;
  if (status === "loading") return labels.loading;
  if (status === "playing") return labels.playing;
  if (status === "paused") return labels.paused;
  return labels.ready;
}

const playerText = {
  ca: { aviActions: "Accions d'Avi", aviActionsHint: "Senyals locals de la teva radio i biblioteca.", aviFavorite: "Avi la conserva a prop perque forma part de la teva biblioteca.", aviMusicSignals: "Avi veu senyals musicals recents i pot obrir accions de descobriment.", aviNeutral: "Avi et guia amb aquesta emissora, els teus recents i la teva biblioteca.", aviNotForMe: "Avi reduira recomanacions semblants a aquesta emissora.", aviRecentSignals: "Avi usa els teus recents per continuar amb emissores properes.", close: "Tanca", collapse: "Minimitza", home: "Inici", library: "Biblioteca", like: "M'agrada", liveRadio: "Radio en directe", loading: "Carregant stream", lyrics: "Lletra", metadataPending: "Metadata musical disponible quan el stream la publiqui", metadataUnavailable: "El stream web no publica titol i artista", music: "Musica", next: "Seguent", noQueue: "Sense cua", notForMe: "No es per a mi", nowPlaying: "Ara sona", openFull: "Obre el reproductor complet", openLibrary: "Obre biblioteca", pause: "Pausa", paused: "En pausa", play: "Reprodueix", playRecommended: "Reprodueix recomanada", playing: "Reproduint en directe", previous: "Anterior", publicInfo: "Info publica", quality: "Qualitat", queue: "Cua", queueLive: "Directe", ready: "A punt", removeFavorite: "Treu favorit", retry: "Reintenta", saveFavorite: "Desa favorit", saveTrack: "Desa canco", search: "Cerca", songActions: "Accions de canco", stationActions: "Emissora", stationArtwork: "Artwork de radio", trackArtwork: "Artwork de canco", tuneSimilar: "Sintonitza similar", unsaveTrack: "Treu canco", webMetadataNote: "La web mostra canco i portada quan hi ha discovery/metadata disponible; si no, manté la radio en directe.", website: "Web" },
  de: { aviActions: "Avi-Aktionen", aviActionsHint: "Lokale Signale aus Radio und Bibliothek.", aviFavorite: "Avi haelt diesen Sender nah, weil er in deiner Bibliothek ist.", aviMusicSignals: "Avi sieht neue Musiksignale und kann Entdeckungsaktionen oeffnen.", aviNeutral: "Avi fuehrt mit diesem Sender, deinen zuletzt gehoerten Sendern und deiner Bibliothek.", aviNotForMe: "Avi reduziert aehnliche Empfehlungen zu diesem Sender.", aviRecentSignals: "Avi nutzt deine letzten Sender fuer passende Fortsetzungen.", close: "Schliessen", collapse: "Minimieren", home: "Start", library: "Bibliothek", like: "Mag ich", liveRadio: "Live-Radio", loading: "Stream wird geladen", lyrics: "Lyrics", metadataPending: "Musik-Metadaten erscheinen, wenn der Stream sie liefert", metadataUnavailable: "Der Web-Stream liefert keinen Titel und Artist", music: "Musik", next: "Weiter", noQueue: "Keine Queue", notForMe: "Nicht fuer mich", nowPlaying: "Jetzt laeuft", openFull: "Vollplayer oeffnen", openLibrary: "Bibliothek oeffnen", pause: "Pause", paused: "Pausiert", play: "Abspielen", playRecommended: "Empfehlung spielen", playing: "Live-Wiedergabe", previous: "Zurueck", publicInfo: "Oeffentliche Info", quality: "Qualitaet", queue: "Queue", queueLive: "Live", ready: "Bereit", removeFavorite: "Favorit entfernen", retry: "Erneut versuchen", saveFavorite: "Favorit sichern", saveTrack: "Song sichern", search: "Suche", songActions: "Song-Aktionen", stationActions: "Sender", stationArtwork: "Radio-Artwork", trackArtwork: "Song-Artwork", tuneSimilar: "Aehnliches finden", unsaveTrack: "Song entfernen", webMetadataNote: "Die Web-App zeigt Song und Cover, wenn Discovery/Metadaten vorhanden sind; sonst bleibt sie bei Live-Radio.", website: "Website" },
  en: { aviActions: "Avi actions", aviActionsHint: "Local signals from this station and your library.", aviFavorite: "Avi keeps this station close because it is in your library.", aviMusicSignals: "Avi sees recent music signals and can open discovery actions.", aviNeutral: "Avi guides from this station, your recents, and your library.", aviNotForMe: "Avi will lower similar recommendations for this station.", aviRecentSignals: "Avi uses your recents to keep nearby stations moving.", close: "Close", collapse: "Minimize", home: "Home", library: "Library", like: "Like", liveRadio: "Live radio", loading: "Loading stream", lyrics: "Lyrics", metadataPending: "Music metadata appears when the stream publishes it", metadataUnavailable: "The web stream is not publishing title and artist", music: "Music", next: "Next", noQueue: "No queue", notForMe: "Not for me", nowPlaying: "Now playing", openFull: "Open full player", openLibrary: "Open library", pause: "Pause", paused: "Paused", play: "Play", playRecommended: "Play recommendation", playing: "Playing live", previous: "Previous", publicInfo: "Public info", quality: "Quality", queue: "Queue", queueLive: "Live", ready: "Ready", removeFavorite: "Remove favorite", retry: "Retry", saveFavorite: "Save favorite", saveTrack: "Save track", search: "Search", songActions: "Song actions", stationActions: "Station", stationArtwork: "Radio artwork", trackArtwork: "Track artwork", tuneSimilar: "Tune similar", unsaveTrack: "Unsave track", webMetadataNote: "The web app shows track and cover when discovery/metadata is available; otherwise it stays on live radio.", website: "Website" },
  es: { aviActions: "Acciones de Avi", aviActionsHint: "Senales locales de esta emisora y tu biblioteca.", aviFavorite: "Avi la mantiene cerca porque forma parte de tu biblioteca.", aviMusicSignals: "Avi ve senales musicales recientes y puede abrir acciones de descubrimiento.", aviNeutral: "Avi guia desde esta emisora, tus recientes y tu biblioteca.", aviNotForMe: "Avi reducira recomendaciones parecidas a esta emisora.", aviRecentSignals: "Avi usa tus recientes para seguir con emisoras cercanas.", close: "Cerrar", collapse: "Minimizar", home: "Inicio", library: "Biblioteca", like: "Me gusta", liveRadio: "Radio en directo", loading: "Cargando stream", lyrics: "Letra", metadataPending: "La metadata musical aparece cuando el stream la publica", metadataUnavailable: "El stream web no publica titulo y artista", music: "Musica", next: "Siguiente", noQueue: "Sin cola", notForMe: "No es para mi", nowPlaying: "Ahora suena", openFull: "Abrir reproductor completo", openLibrary: "Abrir biblioteca", pause: "Pausa", paused: "En pausa", play: "Reproducir", playRecommended: "Reproducir recomendada", playing: "Reproduciendo en directo", previous: "Anterior", publicInfo: "Info publica", quality: "Calidad", queue: "Cola", queueLive: "Directo", ready: "Listo", removeFavorite: "Quitar favorito", retry: "Reintentar", saveFavorite: "Guardar favorito", saveTrack: "Guardar cancion", search: "Buscar", songActions: "Acciones de cancion", stationActions: "Emisora", stationArtwork: "Artwork de radio", trackArtwork: "Artwork de cancion", tuneSimilar: "Sintonizar similar", unsaveTrack: "Quitar cancion", webMetadataNote: "La web muestra cancion y portada cuando hay discovery/metadata disponible; si no, mantiene la radio en directo.", website: "Web" },
  fr: { aviActions: "Actions Avi", aviActionsHint: "Signaux locaux de cette radio et de votre bibliotheque.", aviFavorite: "Avi garde cette radio proche car elle est dans votre bibliotheque.", aviMusicSignals: "Avi voit des signaux musicaux recents et peut ouvrir des actions de decouverte.", aviNeutral: "Avi guide depuis cette radio, vos recents et votre bibliotheque.", aviNotForMe: "Avi reduira les recommandations similaires a cette radio.", aviRecentSignals: "Avi utilise vos recents pour continuer avec des radios proches.", close: "Fermer", collapse: "Reduire", home: "Accueil", library: "Bibliotheque", like: "J'aime", liveRadio: "Radio en direct", loading: "Chargement du flux", lyrics: "Paroles", metadataPending: "Les metadonnees musicales apparaissent quand le flux les publie", metadataUnavailable: "Le flux web ne publie pas le titre et l'artiste", music: "Musique", next: "Suivant", noQueue: "Aucune file", notForMe: "Pas pour moi", nowPlaying: "En cours", openFull: "Ouvrir le lecteur complet", openLibrary: "Ouvrir bibliotheque", pause: "Pause", paused: "En pause", play: "Lire", playRecommended: "Lire recommandee", playing: "Lecture en direct", previous: "Precedent", publicInfo: "Info publique", quality: "Qualite", queue: "File", queueLive: "Direct", ready: "Pret", removeFavorite: "Retirer favori", retry: "Reessayer", saveFavorite: "Sauver favori", saveTrack: "Sauver titre", search: "Recherche", songActions: "Actions du titre", stationActions: "Radio", stationArtwork: "Artwork radio", trackArtwork: "Artwork titre", tuneSimilar: "Trouver similaire", unsaveTrack: "Retirer titre", webMetadataNote: "La web affiche titre et pochette quand discovery/metadonnees existent; sinon elle reste sur radio en direct.", website: "Site" }
};
