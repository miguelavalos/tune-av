import type { TuneDiscoveredTrack, TuneStation } from "@/lib/tune-types";

export const musicGenreTags = ["pop", "rock", "jazz", "classical", "electronic", "latin", "indie", "soul", "ambient", "dance"];
export const allRadioTags = [...musicGenreTags, "news", "sports", "talk", "culture", "local", "public", "religion"];

export function stationIdentityKey(station: TuneStation) {
  const streamKey = normalizedIdentityValue(station.streamURL);
  if (streamKey) return `stream:${streamKey}`;

  const homepageKey = normalizedIdentityValue(station.homepageURL);
  const nameKey = normalizedIdentityValue(station.name);
  if (homepageKey && nameKey) return `homepage-name:${homepageKey}:${nameKey}`;

  return `id:${station.id}`;
}

export function trackKey(title: string, artist?: string | null) {
  return [title, artist ?? ""]
    .map((value) => value.trim().normalize("NFD").replace(/\p{Diacritic}/gu, "").replace(/\s+/g, " ").toLowerCase())
    .join("::");
}

export function discoveryId(title: string, artist: string | null | undefined, stationId: string) {
  return `${trackKey(title, artist)}::${stationId}`.replace(/[^a-z0-9:._-]+/g, "-");
}

export function discoveryIdentityKey(discovery: TuneDiscoveredTrack) {
  return `track:${normalizedIdentityValue(discovery.trackKey) ?? trackKey(discovery.title, discovery.artist)}`;
}

export function stationArtworkUrl(station: TuneStation) {
  return station.artwork?.url ?? station.faviconURL;
}

export function stationFallbackArtworkUrl(station: TuneStation) {
  const category = fallbackArtworkCategory(station);
  const variants = fallbackArtworkVariants[category] ?? fallbackArtworkVariants.genericUnknown;
  const asset = variants[stableHash(station.id || station.name) % variants.length] ?? "fallback-generic-unknown.jpg";
  return `/assets/station-fallbacks/${asset}`;
}

export function stationInitials(station: TuneStation) {
  return station.name
    .replace(/[^\p{L}\p{N}\s!&+.-]/gu, " ")
    .split(/\s+/)
    .filter((part) => part && !["radio", "fm", "am", "hd"].includes(part.toLowerCase()))
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("") || "TV";
}

export function stationDetailText(station: TuneStation) {
  return [station.country, station.language, station.codec, station.bitrate ? `${station.bitrate} kbps` : null]
    .filter(Boolean)
    .join(" · ");
}

export function stationTags(station: TuneStation) {
  return (station.tags ?? "")
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 4);
}

export function hasMusicSignal(station: TuneStation) {
  if (station.category === "music") return true;
  if (station.editorial?.primaryFormat === "music") return true;
  if (station.editorial?.discoveryProfile?.musicDiscoveryScore && station.editorial.discoveryProfile.musicDiscoveryScore >= 50) return true;
  const haystack = `${station.name} ${station.tags ?? ""}`.toLowerCase();
  return musicGenreTags.some((tag) => haystack.includes(tag));
}

export function scoreStationForAvi(station: TuneStation, favorite: boolean, recent: boolean, feedback?: string) {
  let score = station.qualityScore ?? 40;
  if (favorite) score += 35;
  if (recent) score += 18;
  if (feedback === "liked") score += 30;
  if (feedback === "not_for_me") score -= 25;
  if (feedback === "disliked") score -= 45;
  if (station.hasSSLError) score -= 20;
  if (station.editorial?.discoveryProfile?.musicDiscoveryScore) score += Math.round(station.editorial.discoveryProfile.musicDiscoveryScore / 8);
  return score;
}

function normalizedIdentityValue(value: string | null | undefined) {
  const normalized = value?.trim().toLowerCase();
  return normalized || null;
}

type FallbackArtworkCategory = "popHits" | "rockAlternative" | "electronicDance" | "jazzBluesSoul" | "chillAmbient" | "latinWorld" | "decadesOldies" | "classicalInstrumental" | "countryFolk" | "genericUnknown";

const fallbackArtworkVariants: Record<FallbackArtworkCategory, string[]> = {
  popHits: ["fallback-pop-hits-a.jpg", "fallback-pop-hits-b.jpg"],
  rockAlternative: ["fallback-rock-alternative-a.jpg", "fallback-rock-alternative-b.jpg"],
  electronicDance: ["fallback-electronic-dance.jpg"],
  jazzBluesSoul: ["fallback-jazz-blues-soul.jpg"],
  chillAmbient: ["fallback-chill-ambient.jpg"],
  latinWorld: ["fallback-latin-world.jpg"],
  decadesOldies: ["fallback-decades-oldies.jpg"],
  classicalInstrumental: ["fallback-classical-instrumental.jpg"],
  countryFolk: ["fallback-country-folk.jpg"],
  genericUnknown: ["fallback-generic-unknown.jpg"]
};

function fallbackArtworkCategory(station: TuneStation): FallbackArtworkCategory {
  const tags = `${station.name} ${station.tags ?? ""} ${station.editorial?.primaryFormat ?? ""} ${station.editorial?.secondaryFormats?.join(" ") ?? ""}`
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[-_]/g, " ")
    .toLowerCase();

  if (hasAny(tags, ["rock", "metal", "alternative", "indie"])) return "rockAlternative";
  if (hasAny(tags, ["pop", "hits", "top 40", "adult contemporary"])) return "popHits";
  if (hasAny(tags, ["electronic", "dance", "house", "techno", "disco"])) return "electronicDance";
  if (hasAny(tags, ["jazz", "blues", "soul"])) return "jazzBluesSoul";
  if (hasAny(tags, ["ambient", "chill", "lounge", "relax"])) return "chillAmbient";
  if (hasAny(tags, ["latin", "latino", "salsa", "reggaeton", "world"])) return "latinWorld";
  if (hasAny(tags, ["oldies", "80s", "90s", "70s", "60s", "classic hits"])) return "decadesOldies";
  if (hasAny(tags, ["classical", "instrumental", "orchestra", "piano"])) return "classicalInstrumental";
  if (hasAny(tags, ["country", "folk", "americana"])) return "countryFolk";
  return "genericUnknown";
}

function hasAny(value: string, needles: string[]) {
  return needles.some((needle) => value.includes(needle));
}

function stableHash(value: string) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash;
}
