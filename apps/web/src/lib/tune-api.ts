import type {
  TuneFeedbackSnapshot,
  TuneFeedbackValue,
  TuneListeningSessionInput,
  TuneListeningSessionsResponse,
  TuneLibrarySnapshot,
  TunePopularParams,
  TuneSearchParams,
  TuneStationSearchResponse,
  TuneUserSummary
} from "@/lib/tune-types";
import { popularTuneStations, searchTuneStations } from "@/lib/tune-public-api";

export type TuneTokenProvider = () => Promise<string | null>;

export class TuneApiClient {
  constructor(
    private readonly baseUrl: string,
    private readonly getToken: TuneTokenProvider
  ) {}

  searchStations(params: TuneSearchParams) {
    return searchTuneStations({ data: params });
  }

  popularStations(params: TunePopularParams) {
    return popularTuneStations({ data: params });
  }

  fetchUserSummary(limit = 12) {
    return this.fetchJson<TuneUserSummary>(`/v1/tune/me/summary?limit=${limit}`, { auth: true });
  }

  fetchFeedback() {
    return this.fetchJson<TuneFeedbackSnapshot>("/v1/tune/feedback", { auth: true });
  }

  setStationFeedback(stationId: string, feedback: TuneFeedbackValue | null) {
    return this.fetchJson<{ status: "saved" | "cleared"; updatedAt: string }>(`/v1/tune/feedback/stations/${encodeURIComponent(stationId)}`, {
      auth: true,
      method: "PUT",
      body: { deviceId: "tuneav-web", feedback },
      idempotencyKey: idempotencyKey(["station-feedback", stationId, feedback ?? "clear"])
    });
  }

  setTrackFeedback(trackKeyValue: string, payload: { title: string; artist?: string | null; stationId?: string | null; feedback: TuneFeedbackValue | null }) {
    return this.fetchJson<{ status: "saved" | "cleared"; updatedAt: string }>(`/v1/tune/feedback/tracks/${encodeURIComponent(trackKeyValue)}`, {
      auth: true,
      method: "PUT",
      body: { deviceId: "tuneav-web", ...payload },
      idempotencyKey: idempotencyKey(["track-feedback", trackKeyValue, payload.stationId ?? "unknown-station", payload.feedback ?? "clear"])
    });
  }

  recordListeningSessions(sessions: TuneListeningSessionInput[]) {
    return this.fetchJson<TuneListeningSessionsResponse>("/v1/tune/analytics/listening-sessions", {
      auth: true,
      method: "POST",
      body: { deviceId: "tuneav-web", sessions },
      idempotencyKey: idempotencyKey(["listening-sessions", ...sessions.map((session) => session.id)])
    });
  }

  pullAppData(resource: "favorites" | "savedDiscoveries") {
    return this.fetchJson<AppDataResponse>(`/v1/apps/tuneav/data/${resource}`, { auth: true });
  }

  pushAppData(resource: "favorites" | "savedDiscoveries", entries: TuneLibrarySnapshot["favorites"] | TuneLibrarySnapshot["savedDiscoveries"], etag?: string | null) {
    return this.fetchJson<AppDataResponse>(`/v1/apps/tuneav/data/${resource}`, {
      auth: true,
      method: "PUT",
      body: {
        appId: "tuneav",
        resource,
        deviceId: "tuneav-web",
        sentAt: new Date().toISOString(),
        entries
      },
      headers: etag ? { "If-Match": etag } : undefined
    });
  }

  private async fetchJson<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const token = options.auth ? await this.getToken() : null;
    if (options.auth && !token) {
      throw new TuneApiError(401, "missing_token");
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      method: options.method ?? "GET",
      headers: {
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(options.idempotencyKey ? { "Idempotency-Key": options.idempotencyKey } : {}),
        ...options.headers
      },
      body: options.body ? JSON.stringify(options.body) : undefined
    });

    if (!response.ok) {
      throw new TuneApiError(response.status, await errorCode(response));
    }

    return response.json() as Promise<T>;
  }
}

export class TuneApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string
  ) {
    super(`Tune API request failed: ${status} ${code}`);
  }
}

type AppDataResponse = {
  data: {
    appId: string;
    resource: string;
    deviceId: string;
    sentAt: string;
    entries: unknown[];
  };
  updatedAt: string;
  revision?: number | null;
  etag?: string | null;
};

type RequestOptions = {
  auth?: boolean;
  method?: "GET" | "PUT" | "POST";
  body?: unknown;
  headers?: Record<string, string>;
  idempotencyKey?: string;
};

function queryString(params: Record<string, string | number | null | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      search.set(key, String(value));
    }
  }
  const value = search.toString();
  return value ? `?${value}` : "";
}

function idempotencyKey(parts: string[]) {
  return parts
    .map((part) => part.trim().normalize("NFD").replace(/\p{Diacritic}/gu, "").replace(/\s+/g, "-").replace(/[^a-zA-Z0-9._:-]/g, "-").toLowerCase())
    .filter(Boolean)
    .join(":");
}

async function errorCode(response: Response) {
  try {
    const payload = (await response.json()) as { error?: { code?: string } };
    return payload.error?.code ?? "request_failed";
  } catch {
    return "request_failed";
  }
}
