import { createServerFn } from "@tanstack/react-start";
import { getTuneApiBaseUrl } from "@/lib/tune-config";
import type { TunePopularParams, TuneSearchParams, TuneStationSearchResponse } from "@/lib/tune-types";

export const searchTuneStations = createServerFn({ method: "GET" })
  .validator((data: TuneSearchParams) => data)
  .handler(async ({ data }) => fetchTuneStationFeed("/v1/tune/stations/search", data));

export const popularTuneStations = createServerFn({ method: "GET" })
  .validator((data: TunePopularParams) => data)
  .handler(async ({ data }) => fetchTuneStationFeed("/v1/tune/stations/popular", data));

async function fetchTuneStationFeed(path: string, params: TuneSearchParams | TunePopularParams): Promise<TuneStationSearchResponse> {
  const response = await fetch(`${getTuneApiBaseUrl()}${path}${queryString({ ...params })}`, {
    headers: { Accept: "application/json" }
  });

  if (!response.ok) {
    throw new Error(await errorCode(response));
  }

  return response.json() as Promise<TuneStationSearchResponse>;
}

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

async function errorCode(response: Response) {
  try {
    const payload = (await response.json()) as { code?: string; error?: string };
    return payload.code ?? payload.error ?? response.statusText;
  } catch {
    return response.statusText;
  }
}
