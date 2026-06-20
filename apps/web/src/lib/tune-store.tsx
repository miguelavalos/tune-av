import { useAccountAppAccess, useAccountToken } from "@avalsys/account-av-web";
import type { AppsAvExternalSearchEngine, AppsAvLocale } from "@avalsys/apps-av-web";
import { normalizeAppsAvExternalSearchEngine, useAppsAvLocale } from "@avalsys/apps-av-web";
import { useQueryClient } from "@tanstack/react-query";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { TuneApiClient, TuneApiError } from "@/lib/tune-api";
import { fallbackAccessForMode, signedInFreeAccess } from "@/lib/tune-access";
import { getTuneApiBaseUrl } from "@/lib/tune-config";
import { discoveryId, discoveryIdentityKey, scoreStationForAvi, stationIdentityKey, trackKey } from "@/lib/tune-station";
import type {
  FavoriteStationRecord,
  TuneAccessState,
  TuneDiscoveredTrack,
  TuneFeedbackValue,
  TuneListeningEndedReason,
  TuneListeningSessionInput,
  TuneListeningSource,
  TuneStation,
  TuneStationSearchResponse,
  TuneUserSummary
} from "@/lib/tune-types";

type TuneStoreState = {
  favorites: FavoriteStationRecord[];
  recents: RecentStationRecord[];
  discoveries: TuneDiscoveredTrack[];
  stationFeedback: Record<string, LocalFeedbackRecord>;
  trackFeedback: Record<string, LocalTrackFeedbackRecord>;
  settings: TuneSettings;
  pendingSessions: TuneListeningSessionInput[];
  pendingFeedback: PendingFeedbackUpload[];
  lastSyncedAt: string | null;
  syncStatus: "idle" | "syncing" | "synced" | "conflict" | "failed";
};

type RecentStationRecord = {
  station: TuneStation;
  lastPlayedAt: string;
};

type LocalFeedbackRecord = {
  stationID: string;
  feedback: TuneFeedbackValue;
  updatedAt: string;
};

type LocalTrackFeedbackRecord = {
  trackKey: string;
  title: string;
  artist: string | null;
  stationID: string | null;
  feedback: TuneFeedbackValue;
  updatedAt: string;
};

type PendingFeedbackUpload =
  | { kind: "station"; stationID: string; feedback: TuneFeedbackValue | null; updatedAt: string }
  | { kind: "track"; trackKey: string; title: string; artist: string | null; stationID: string | null; feedback: TuneFeedbackValue | null; updatedAt: string };

type TuneSettings = {
  preferredCountryCode: string;
  preferredTag: string;
  discoveryMode: "music" | "allRadio";
  externalSearchEngine: AppsAvExternalSearchEngine;
  lastPlayedStationID: string | null;
  dailyUsage: Record<string, { day: string; count: number; keys: string[] }>;
};

type SearchState = {
  stations: TuneStation[];
  isLoading: boolean;
  isLoadingMore: boolean;
  error: string | null;
  pagination: TuneStationSearchResponse["pagination"] | null;
  source: TuneListeningSource;
};

type PlaybackState = {
  currentStation: TuneStation | null;
  status: "idle" | "loading" | "playing" | "paused" | "failed";
  error: string | null;
  queue: TuneStation[];
  queueSource: TuneListeningSource;
  startedAt: string | null;
  trackDetectedCount: number;
};

type TuneContextValue = {
  access: TuneAccessState;
  api: TuneApiClient;
  locale: AppsAvLocale;
  favorites: FavoriteStationRecord[];
  favoriteStations: TuneStation[];
  recents: RecentStationRecord[];
  recentStations: TuneStation[];
  discoveries: TuneDiscoveredTrack[];
  visibleDiscoveries: TuneDiscoveredTrack[];
  savedDiscoveries: TuneDiscoveredTrack[];
  stationFeedback: Record<string, LocalFeedbackRecord>;
  trackFeedback: Record<string, LocalTrackFeedbackRecord>;
  settings: TuneSettings;
  search: SearchState;
  playback: PlaybackState;
  userSummary: TuneUserSummary | null;
  summaryStatus: "idle" | "loading" | "ready" | "failed";
  syncStatus: TuneStoreState["syncStatus"];
  lastSyncedAt: string | null;
  canUseDailyFeature: (feature: DailyFeature, usageKey?: string) => boolean;
  recordDailyFeatureUse: (feature: DailyFeature, usageKey?: string) => boolean;
  searchStations: (input: SearchInput) => Promise<void>;
  loadMoreStations: () => Promise<void>;
  refreshPopular: () => Promise<void>;
  playStation: (station: TuneStation, source: TuneListeningSource, queue?: TuneStation[]) => Promise<void>;
  pausePlayback: (reason?: TuneListeningEndedReason) => Promise<void>;
  retryPlayback: () => Promise<void>;
  nextStation: () => Promise<void>;
  previousStation: () => Promise<void>;
  toggleFavorite: (station: TuneStation) => void;
  setStationFeedback: (station: TuneStation, feedback: TuneFeedbackValue | null) => void;
  setTrackFeedback: (discovery: TuneDiscoveredTrack, feedback: TuneFeedbackValue | null) => void;
  toggleDiscoverySaved: (discovery: TuneDiscoveredTrack) => void;
  hideDiscovery: (discovery: TuneDiscoveredTrack) => void;
  restoreDiscovery: (discovery: TuneDiscoveredTrack) => void;
  removeDiscovery: (discovery: TuneDiscoveredTrack) => void;
  clearDiscoveries: () => void;
  clearLocalData: () => void;
  setPreferredCountry: (countryCode: string) => void;
  setPreferredTag: (tag: string) => void;
  setDiscoveryMode: (mode: "music" | "allRadio") => void;
  setExternalSearchEngine: (engine: AppsAvExternalSearchEngine | string) => void;
  refreshUserSummary: () => Promise<void>;
  synchronizeLibrary: () => Promise<void>;
  recommendations: TuneStation[];
};

export type DailyFeature = "aviActionsPerDay" | "lyricsSearchesPerDay" | "webSearchesPerDay" | "youtubeSearchesPerDay" | "appleMusicSearchesPerDay" | "spotifySearchesPerDay" | "discoverySharesPerDay";

type SearchInput = {
  q?: string;
  countryCode?: string;
  tag?: string;
  mode?: "music" | "allRadio";
  reset?: boolean;
  source?: TuneListeningSource;
};

const TuneContext = createContext<TuneContextValue | null>(null);
const storageKey = "tuneav.web.store.v1";
const audioElementId = "tuneav-web-audio";

export function TuneAppProvider({ children }: { children: ReactNode }) {
  const locale = useAppsAvLocale();
  const getToken = useAccountToken();
  const appAccess = useAccountAppAccess("tuneav");
  const queryClient = useQueryClient();
  const api = useMemo(() => new TuneApiClient(getTuneApiBaseUrl(), getToken), [getToken]);
  const access = useMemo<TuneAccessState>(() => {
    const value = appAccess.data;
    if (!value || value.accessMode === "guest") return signedInFreeAccess;
    return {
      accessMode: value.accessMode,
      planTier: value.planTier,
      capabilities: value.capabilities,
      limits: value.limits
    };
  }, [appAccess.data]);

  const [store, setStore] = useState<TuneStoreState>(() => defaultStore());
  const [search, setSearch] = useState<SearchState>({ stations: [], isLoading: false, isLoadingMore: false, error: null, pagination: null, source: "search" });
  const [playback, setPlayback] = useState<PlaybackState>(() => initialPlaybackState(defaultStore()));
  const [userSummary, setUserSummary] = useState<TuneUserSummary | null>(null);
  const [summaryStatus, setSummaryStatus] = useState<TuneContextValue["summaryStatus"]>("idle");
  const [hasRestoredLocalStore, setHasRestoredLocalStore] = useState(false);
  const lastSearchRef = useRef<SearchInput>({});

  useEffect(() => {
    const restoredStore = readStore();
    setStore(restoredStore);
    setPlayback(initialPlaybackState(restoredStore));
    setHasRestoredLocalStore(true);
  }, []);

  useEffect(() => {
    if (!hasRestoredLocalStore) return;
    persistStore(store);
  }, [hasRestoredLocalStore, store]);

  useEffect(() => {
    if (!access.capabilities.canUseCloudSync) return;
    void synchronizeLibrary();
    void refreshUserSummary();
    void flushPendingFeedback();
    void flushPendingSessions();
  }, [access.accessMode]);

  useEffect(() => {
    const audio = audioElement();
    const onPlaying = () => setPlayback((current) => ({ ...current, status: "playing", error: null }));
    const onWaiting = () => setPlayback((current) => ({ ...current, status: current.currentStation ? "loading" : current.status }));
    const onError = () => setPlayback((current) => ({ ...current, status: "failed", error: "Stream playback failed." }));
    const onPause = () => setPlayback((current) => (current.status === "failed" ? current : { ...current, status: current.currentStation ? "paused" : "idle" }));
    audio.addEventListener("playing", onPlaying);
    audio.addEventListener("waiting", onWaiting);
    audio.addEventListener("error", onError);
    audio.addEventListener("pause", onPause);
    return () => {
      audio.removeEventListener("playing", onPlaying);
      audio.removeEventListener("waiting", onWaiting);
      audio.removeEventListener("error", onError);
      audio.removeEventListener("pause", onPause);
    };
  }, []);

  const favoriteStations = useMemo(() => store.favorites.filter((item) => !item.deletedAt).map((item) => item.station), [store.favorites]);
  const recentStations = useMemo(() => store.recents.map((item) => item.station), [store.recents]);
  const visibleDiscoveries = useMemo(() => store.discoveries.filter((item) => !item.hiddenAt && !item.deletedAt), [store.discoveries]);
  const savedDiscoveries = useMemo(() => visibleDiscoveries.filter((item) => item.markedInterestedAt), [visibleDiscoveries]);

  const recommendations = useMemo(() => {
    const favoriteKeys = new Set(favoriteStations.map((station) => station.id));
    const recentKeys = new Set(recentStations.map((station) => station.id));
    return [...favoriteStations, ...recentStations, ...search.stations]
      .filter(uniqueStation)
      .sort((a, b) => scoreStationForAvi(b, favoriteKeys.has(b.id), recentKeys.has(b.id), store.stationFeedback[b.id]?.feedback) - scoreStationForAvi(a, favoriteKeys.has(a.id), recentKeys.has(a.id), store.stationFeedback[a.id]?.feedback))
      .slice(0, 12);
  }, [favoriteStations, recentStations, search.stations, store.stationFeedback]);

  const searchStations = useCallback(async (input: SearchInput) => {
    const reset = input.reset !== false;
    lastSearchRef.current = { ...lastSearchRef.current, ...input, reset: false };
    setSearch((current) => ({ ...current, isLoading: reset, isLoadingMore: !reset, error: null, source: input.source ?? "search", stations: reset ? [] : current.stations }));
    try {
      const response = input.q || input.countryCode || input.tag
        ? await api.searchStations({
            q: input.q,
            countryCode: input.countryCode,
            tag: input.tag,
            mode: input.mode ?? store.settings.discoveryMode,
            locale,
            limit: 24
          })
        : await api.popularStations({
            countryCode: input.countryCode || store.settings.preferredCountryCode || undefined,
            tag: input.tag || store.settings.preferredTag || undefined,
            locale,
            surface: input.source === "avi" ? "avi" : "home",
            limit: 24
          });
      setSearch((current) => ({
        ...current,
        stations: reset ? response.stations : [...current.stations, ...response.stations].filter(uniqueStation),
        pagination: response.pagination ?? null,
        isLoading: false,
        isLoadingMore: false
      }));
    } catch (error) {
      setSearch((current) => ({ ...current, isLoading: false, isLoadingMore: false, error: error instanceof Error ? error.message : "Station search failed." }));
    }
  }, [api, locale, store.settings.discoveryMode, store.settings.preferredCountryCode, store.settings.preferredTag]);

  const loadMoreStations = useCallback(async () => {
    if (!search.pagination?.hasMore || !search.pagination.nextCursor) return;
    const last = lastSearchRef.current;
    setSearch((current) => ({ ...current, isLoadingMore: true, error: null }));
    try {
      const response = await api.searchStations({
        q: last.q,
        countryCode: last.countryCode,
        tag: last.tag,
        mode: last.mode ?? store.settings.discoveryMode,
        cursor: search.pagination.nextCursor,
        locale,
        limit: 24
      });
      setSearch((current) => ({
        ...current,
        stations: [...current.stations, ...response.stations].filter(uniqueStation),
        pagination: response.pagination ?? null,
        isLoadingMore: false
      }));
    } catch (error) {
      setSearch((current) => ({ ...current, isLoadingMore: false, error: error instanceof Error ? error.message : "Could not load more stations." }));
    }
  }, [api, locale, search.pagination?.hasMore, search.pagination?.nextCursor, store.settings.discoveryMode]);

  const refreshPopular = useCallback(() => searchStations({ reset: true, source: "home" }), [searchStations]);

  const recordRecent = useCallback((station: TuneStation) => {
    setStore((current) => {
      const key = stationIdentityKey(station);
      const recents = [{ station, lastPlayedAt: new Date().toISOString() }, ...current.recents.filter((item) => stationIdentityKey(item.station) !== key)].slice(0, access.limits.recentStations ?? 1_000);
      return { ...current, recents, settings: { ...current.settings, lastPlayedStationID: station.id } };
    });
  }, [access.limits.recentStations]);

  const playStation = useCallback(async (station: TuneStation, source: TuneListeningSource, queue?: TuneStation[]) => {
    const audio = audioElement();
    await finalizeListeningSession("station_changed");
    setPlayback({
      currentStation: station,
      status: "loading",
      error: null,
      queue: queue?.length ? queue : [station],
      queueSource: source,
      startedAt: new Date().toISOString(),
      trackDetectedCount: station.hasExtendedInfo ? 1 : 0
    });
    recordRecent(station);
    audio.src = station.streamURL;
    try {
      await audio.play();
    } catch (error) {
      setPlayback((current) => ({ ...current, status: "failed", error: error instanceof Error ? error.message : "Browser blocked playback." }));
    }
  }, [recordRecent]);

  const pausePlayback = useCallback(async (reason: TuneListeningEndedReason = "paused") => {
    audioElement().pause();
    await finalizeListeningSession(reason);
  }, []);

  const retryPlayback = useCallback(async () => {
    if (playback.currentStation) {
      await playStation(playback.currentStation, playback.queueSource, playback.queue);
    }
  }, [playStation, playback.currentStation, playback.queue, playback.queueSource]);

  const nextStation = useCallback(async () => {
    if (!playback.currentStation || playback.queue.length < 2) return;
    const index = playback.queue.findIndex((station) => station.id === playback.currentStation?.id);
    const station = playback.queue[(index + 1) % playback.queue.length];
    if (station) await playStation(station, playback.queueSource, playback.queue);
  }, [playStation, playback.currentStation, playback.queue, playback.queueSource]);

  const previousStation = useCallback(async () => {
    if (!playback.currentStation || playback.queue.length < 2) return;
    const index = playback.queue.findIndex((station) => station.id === playback.currentStation?.id);
    const station = playback.queue[(index - 1 + playback.queue.length) % playback.queue.length];
    if (station) await playStation(station, playback.queueSource, playback.queue);
  }, [playStation, playback.currentStation, playback.queue, playback.queueSource]);

  const finalizeListeningSession = useCallback(async (endedReason: TuneListeningEndedReason) => {
    const current = playbackRef.current;
    if (!current.currentStation || !current.startedAt) return;
    const endedAt = new Date();
    const startedAt = new Date(current.startedAt);
    const durationSeconds = Math.max(0, Math.round((endedAt.getTime() - startedAt.getTime()) / 1000));
    if (durationSeconds < 10) return;
    const session: TuneListeningSessionInput = {
      id: crypto.randomUUID(),
      stationId: current.currentStation.id,
      stationName: current.currentStation.name,
      startedAt: startedAt.toISOString(),
      endedAt: endedAt.toISOString(),
      durationSeconds,
      source: current.queueSource,
      endedReason,
      trackDetectedCount: current.trackDetectedCount
    };
    setStore((storeValue) => ({ ...storeValue, pendingSessions: [...storeValue.pendingSessions, session].slice(-50) }));
    if (access.capabilities.canUseCloudSync) {
      void flushPendingSessions([session]);
    }
  }, [access.capabilities.canUseCloudSync]);

  const playbackRef = useRef(playback);
  useEffect(() => {
    playbackRef.current = playback;
  }, [playback]);

  const toggleFavorite = useCallback((station: TuneStation) => {
    setStore((current) => {
      const key = stationIdentityKey(station);
      const exists = current.favorites.some((item) => !item.deletedAt && stationIdentityKey(item.station) === key);
      if (exists) {
        return { ...current, favorites: current.favorites.map((item) => stationIdentityKey(item.station) === key ? { ...item, deletedAt: new Date().toISOString() } : item) };
      }
      if (current.favorites.filter((item) => !item.deletedAt).length >= (access.limits.favoriteStations ?? 1_000)) return current;
      return { ...current, favorites: [{ station, createdAt: new Date().toISOString(), deletedAt: null }, ...current.favorites] };
    });
  }, [access.limits.favoriteStations]);

  const setStationFeedback = useCallback((station: TuneStation, feedback: TuneFeedbackValue | null) => {
    const updatedAt = new Date().toISOString();
    setStore((current) => {
      const nextFeedback = { ...current.stationFeedback };
      if (feedback) nextFeedback[station.id] = { stationID: station.id, feedback, updatedAt };
      else delete nextFeedback[station.id];
      return {
        ...current,
        stationFeedback: nextFeedback,
        pendingFeedback: [...current.pendingFeedback, { kind: "station", stationID: station.id, feedback, updatedAt }]
      };
    });
    if (access.capabilities.canUseCloudSync) void api.setStationFeedback(station.id, feedback).catch(() => undefined);
  }, [access.capabilities.canUseCloudSync, api]);

  const setTrackFeedback = useCallback((discovery: TuneDiscoveredTrack, feedback: TuneFeedbackValue | null) => {
    const key = discovery.trackKey ?? trackKey(discovery.title, discovery.artist);
    const updatedAt = new Date().toISOString();
    setStore((current) => {
      const nextFeedback = { ...current.trackFeedback };
      if (feedback) nextFeedback[key] = { trackKey: key, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID, feedback, updatedAt };
      else delete nextFeedback[key];
      return {
        ...current,
        trackFeedback: nextFeedback,
        pendingFeedback: [...current.pendingFeedback, { kind: "track", trackKey: key, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID, feedback, updatedAt }]
      };
    });
    if (access.capabilities.canUseCloudSync) void api.setTrackFeedback(key, { title: discovery.title, artist: discovery.artist, stationId: discovery.stationID, feedback }).catch(() => undefined);
  }, [access.capabilities.canUseCloudSync, api]);

  const toggleDiscoverySaved = useCallback((discovery: TuneDiscoveredTrack) => {
    setStore((current) => {
      const key = discoveryIdentityKey(discovery);
      const now = new Date().toISOString();
      const exists = current.discoveries.find((item) => discoveryIdentityKey(item) === key);
      if (!exists) {
        if (current.discoveries.filter((item) => item.markedInterestedAt && !item.deletedAt).length >= (access.limits.savedTracks ?? 1_000)) return current;
        return { ...current, discoveries: [{ ...discovery, markedInterestedAt: now, updatedAt: now }, ...current.discoveries] };
      }
      return {
        ...current,
        discoveries: current.discoveries.map((item) => discoveryIdentityKey(item) === key ? { ...item, markedInterestedAt: item.markedInterestedAt ? null : now, updatedAt: now } : item)
      };
    });
  }, [access.limits.savedTracks]);

  const hideDiscovery = useCallback((discovery: TuneDiscoveredTrack) => {
    updateDiscovery(discovery, { hiddenAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
  }, []);

  const restoreDiscovery = useCallback((discovery: TuneDiscoveredTrack) => {
    updateDiscovery(discovery, { hiddenAt: null, deletedAt: null, updatedAt: new Date().toISOString() });
  }, []);

  const removeDiscovery = useCallback((discovery: TuneDiscoveredTrack) => {
    updateDiscovery(discovery, { deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
  }, []);

  const clearDiscoveries = useCallback(() => {
    setStore((current) => ({ ...current, discoveries: current.discoveries.map((item) => ({ ...item, deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() })) }));
  }, []);

  const clearLocalData = useCallback(() => {
    setStore(defaultStore());
    setSearch({ stations: [], isLoading: false, isLoadingMore: false, error: null, pagination: null, source: "search" });
    setPlayback({ currentStation: null, status: "idle", error: null, queue: [], queueSource: "unknown", startedAt: null, trackDetectedCount: 0 });
    audioElement().pause();
    audioElement().removeAttribute("src");
  }, []);

  const updateDiscovery = useCallback((discovery: TuneDiscoveredTrack, patch: Partial<TuneDiscoveredTrack>) => {
    const key = discoveryIdentityKey(discovery);
    setStore((current) => ({ ...current, discoveries: current.discoveries.map((item) => discoveryIdentityKey(item) === key ? { ...item, ...patch } : item) }));
  }, []);

  const setPreferredCountry = useCallback((preferredCountryCode: string) => {
    setStore((current) => ({ ...current, settings: { ...current.settings, preferredCountryCode } }));
  }, []);

  const setPreferredTag = useCallback((preferredTag: string) => {
    setStore((current) => ({ ...current, settings: { ...current.settings, preferredTag } }));
  }, []);

  const setDiscoveryMode = useCallback((discoveryMode: "music" | "allRadio") => {
    setStore((current) => ({ ...current, settings: { ...current.settings, discoveryMode } }));
  }, []);

  const setExternalSearchEngine = useCallback((externalSearchEngine: AppsAvExternalSearchEngine | string) => {
    setStore((current) => ({ ...current, settings: { ...current.settings, externalSearchEngine: normalizeAppsAvExternalSearchEngine(externalSearchEngine) } }));
  }, []);

  const canUseDailyFeature = useCallback((feature: DailyFeature, usageKey: string = feature) => {
    const limit = access.limits[feature];
    if (limit === null) return true;
    const usage = dailyUsage(store.settings.dailyUsage, feature);
    if (usage.keys.includes(normalizedUsageKey(usageKey))) return true;
    return usage.count < limit;
  }, [access.limits, store.settings.dailyUsage]);

  const recordDailyFeatureUse = useCallback((feature: DailyFeature, usageKey: string = feature) => {
    if (!canUseDailyFeature(feature, usageKey)) return false;
    setStore((current) => {
      const key = normalizedUsageKey(usageKey);
      const usage = dailyUsage(current.settings.dailyUsage, feature);
      if (usage.keys.includes(key)) return current;
      return {
        ...current,
        settings: {
          ...current.settings,
          dailyUsage: {
            ...current.settings.dailyUsage,
            [feature]: { day: todayKey(), count: usage.count + 1, keys: [...usage.keys, key].slice(-200) }
          }
        }
      };
    });
    return true;
  }, [canUseDailyFeature]);

  const refreshUserSummary = useCallback(async () => {
    setSummaryStatus("loading");
    try {
      const summary = await api.fetchUserSummary(12);
      setUserSummary(summary);
      setSummaryStatus("ready");
    } catch {
      setSummaryStatus("failed");
    }
  }, [api]);

  const synchronizeLibrary = useCallback(async () => {
    if (!access.capabilities.canUseCloudSync) return;
    setStore((current) => ({ ...current, syncStatus: "syncing" }));
    try {
      const [remoteFavorites, remoteDiscoveries] = await Promise.all([
        api.pullAppData("favorites"),
        api.pullAppData("savedDiscoveries")
      ]);
      const remoteFavoriteEntries = remoteFavorites.data.entries as FavoriteStationRecord[];
      const remoteDiscoveryEntries = remoteDiscoveries.data.entries as TuneDiscoveredTrack[];
      setStore((current) => {
        const favorites = mergeFavorites(current.favorites, remoteFavoriteEntries);
        const discoveries = mergeDiscoveries(current.discoveries, remoteDiscoveryEntries);
        return { ...current, favorites, discoveries, syncStatus: "synced", lastSyncedAt: new Date().toISOString() };
      });
      const latest = readStore();
      await Promise.all([
        api.pushAppData("favorites", latest.favorites),
        api.pushAppData("savedDiscoveries", latest.discoveries.filter((item) => item.markedInterestedAt || item.deletedAt))
      ]);
      queryClient.invalidateQueries({ queryKey: ["account-av", "access", "tuneav"] }).catch(() => undefined);
    } catch (error) {
      if (error instanceof TuneApiError && error.status === 403) {
        setStore((current) => ({ ...current, syncStatus: "idle" }));
        return;
      }
      setStore((current) => ({ ...current, syncStatus: "failed" }));
    }
  }, [access.capabilities.canUseCloudSync, api, queryClient]);

  const flushPendingFeedback = useCallback(async () => {
    if (!access.capabilities.canUseCloudSync || store.pendingFeedback.length === 0) return;
    const pending = [...store.pendingFeedback];
    for (const item of pending) {
      try {
        if (item.kind === "station") await api.setStationFeedback(item.stationID, item.feedback);
        else await api.setTrackFeedback(item.trackKey, { title: item.title, artist: item.artist, stationId: item.stationID, feedback: item.feedback });
      } catch {
        return;
      }
    }
    setStore((current) => ({ ...current, pendingFeedback: current.pendingFeedback.filter((item) => !pending.includes(item)) }));
  }, [access.capabilities.canUseCloudSync, api, store.pendingFeedback]);

  const flushPendingSessions = useCallback(async (overrideSessions?: TuneListeningSessionInput[]) => {
    if (!access.capabilities.canUseCloudSync) return;
    const sessions = overrideSessions ?? store.pendingSessions.slice(0, 5);
    if (sessions.length === 0) return;
    try {
      await api.recordListeningSessions(sessions);
      setStore((current) => ({ ...current, pendingSessions: current.pendingSessions.filter((session) => !sessions.some((sent) => sent.id === session.id)) }));
    } catch {
      setStore((current) => ({ ...current, pendingSessions: [...current.pendingSessions].slice(-50) }));
    }
  }, [access.capabilities.canUseCloudSync, api, store.pendingSessions]);

  const value = useMemo<TuneContextValue>(() => ({
    access,
    api,
    locale,
    favorites: store.favorites,
    favoriteStations,
    recents: store.recents,
    recentStations,
    discoveries: store.discoveries,
    visibleDiscoveries,
    savedDiscoveries,
    stationFeedback: store.stationFeedback,
    trackFeedback: store.trackFeedback,
    settings: store.settings,
    search,
    playback,
    userSummary,
    summaryStatus,
    syncStatus: store.syncStatus,
    lastSyncedAt: store.lastSyncedAt,
    canUseDailyFeature,
    recordDailyFeatureUse,
    searchStations,
    loadMoreStations,
    refreshPopular,
    playStation,
    pausePlayback,
    retryPlayback,
    nextStation,
    previousStation,
    toggleFavorite,
    setStationFeedback,
    setTrackFeedback,
    toggleDiscoverySaved,
    hideDiscovery,
    restoreDiscovery,
    removeDiscovery,
    clearDiscoveries,
    clearLocalData,
    setPreferredCountry,
    setPreferredTag,
    setDiscoveryMode,
    setExternalSearchEngine,
    refreshUserSummary,
    synchronizeLibrary,
    recommendations
  }), [access, api, locale, store, favoriteStations, recentStations, visibleDiscoveries, savedDiscoveries, search, playback, userSummary, summaryStatus, canUseDailyFeature, recordDailyFeatureUse, searchStations, loadMoreStations, refreshPopular, playStation, pausePlayback, retryPlayback, nextStation, previousStation, toggleFavorite, setStationFeedback, setTrackFeedback, toggleDiscoverySaved, hideDiscovery, restoreDiscovery, removeDiscovery, clearDiscoveries, clearLocalData, setPreferredCountry, setPreferredTag, setDiscoveryMode, setExternalSearchEngine, refreshUserSummary, synchronizeLibrary, recommendations]);

  return <TuneContext.Provider value={value}>{children}</TuneContext.Provider>;
}

export function useTune() {
  const context = useContext(TuneContext);
  if (!context) throw new Error("useTune must be used inside TuneAppProvider.");
  return context;
}

export function discoveryFromStation(station: TuneStation, title = station.name, artist: string | null = null): TuneDiscoveredTrack {
  const playedAt = new Date().toISOString();
  return {
    discoveryID: discoveryId(title, artist, station.id),
    trackKey: trackKey(title, artist),
    title,
    artist,
    stationID: station.id,
    stationName: station.name,
    artworkURL: station.artwork?.url ?? null,
    stationArtworkURL: station.artwork?.url ?? station.faviconURL,
    playedAt,
    markedInterestedAt: null,
    hiddenAt: null,
    deletedAt: null,
    updatedAt: playedAt
  };
}

function initialStore(): TuneStoreState {
  if (typeof window === "undefined") return defaultStore();
  const raw = window.localStorage.getItem(storageKey);
  if (!raw) return defaultStore();
  try {
    const parsed = JSON.parse(raw) as Partial<TuneStoreState>;
    const defaults = defaultStore();
    return {
      ...defaults,
      ...parsed,
      settings: {
        ...defaults.settings,
        ...parsed.settings,
        externalSearchEngine: normalizeAppsAvExternalSearchEngine(parsed.settings?.externalSearchEngine)
      }
    };
  } catch {
    return defaultStore();
  }
}

function readStore() {
  return initialStore();
}

function persistStore(store: TuneStoreState) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(storageKey, JSON.stringify(store));
}

function defaultStore(): TuneStoreState {
  return {
    favorites: [],
    recents: [],
    discoveries: [],
    stationFeedback: {},
    trackFeedback: {},
    settings: {
      preferredCountryCode: "",
      preferredTag: "",
      discoveryMode: "music",
      externalSearchEngine: "duckduckgo",
      lastPlayedStationID: null,
      dailyUsage: {}
    },
    pendingSessions: [],
    pendingFeedback: [],
    lastSyncedAt: null,
    syncStatus: "idle"
  };
}

function initialPlaybackState(store: TuneStoreState): PlaybackState {
  const lastPlayedStationID = store.settings.lastPlayedStationID;
  const recentStations = store.recents.map((item) => item.station);
  const favoriteStations = store.favorites.filter((item) => !item.deletedAt).map((item) => item.station);
  const currentStation = [...recentStations, ...favoriteStations].find((station) => station.id === lastPlayedStationID) ?? null;

  return {
    currentStation,
    status: currentStation ? "paused" : "idle",
    error: null,
    queue: currentStation ? recentStations.length ? recentStations : [currentStation] : [],
    queueSource: currentStation ? "library" : "unknown",
    startedAt: null,
    trackDetectedCount: 0
  };
}

function audioElement() {
  if (typeof document === "undefined") {
    throw new Error("Audio playback is only available in the browser.");
  }
  let element = document.getElementById(audioElementId) as HTMLAudioElement | null;
  if (!element) {
    element = document.createElement("audio");
    element.id = audioElementId;
    element.preload = "none";
    element.crossOrigin = "anonymous";
    document.body.appendChild(element);
  }
  return element;
}

function uniqueStation(station: TuneStation, index: number, stations: TuneStation[]) {
  const key = stationIdentityKey(station);
  return stations.findIndex((item) => stationIdentityKey(item) === key) === index;
}

function mergeFavorites(local: FavoriteStationRecord[], remote: FavoriteStationRecord[]) {
  const byKey = new Map<string, FavoriteStationRecord>();
  for (const item of [...local, ...remote]) {
    const key = stationIdentityKey(item.station);
    const current = byKey.get(key);
    if (!current || recordDate(item.createdAt, item.deletedAt) >= recordDate(current.createdAt, current.deletedAt)) byKey.set(key, item);
  }
  return [...byKey.values()].sort((a, b) => recordDate(b.createdAt, b.deletedAt) - recordDate(a.createdAt, a.deletedAt));
}

function mergeDiscoveries(local: TuneDiscoveredTrack[], remote: TuneDiscoveredTrack[]) {
  const byKey = new Map<string, TuneDiscoveredTrack>();
  for (const item of [...local, ...remote]) {
    const key = discoveryIdentityKey(item);
    const current = byKey.get(key);
    if (!current || discoveryDate(item) >= discoveryDate(current)) byKey.set(key, item);
  }
  return [...byKey.values()].sort((a, b) => discoveryDate(b) - discoveryDate(a));
}

function recordDate(...values: Array<string | null | undefined>) {
  return Math.max(...values.filter(Boolean).map((value) => Date.parse(value as string)), 0);
}

function discoveryDate(item: TuneDiscoveredTrack) {
  return recordDate(item.updatedAt, item.markedInterestedAt, item.hiddenAt, item.deletedAt, item.playedAt);
}

function dailyUsage(usages: TuneSettings["dailyUsage"], feature: DailyFeature) {
  const current = usages[feature];
  if (!current || current.day !== todayKey()) return { day: todayKey(), count: 0, keys: [] };
  return current;
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function normalizedUsageKey(value: string) {
  return value.trim().toLowerCase().slice(0, 240);
}
