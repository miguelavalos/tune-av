#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = dirname(dirname(fileURLToPath(import.meta.url)));
const appleLocales = ["ca", "de", "en", "es", "fr"];
const webLocales = ["es", "ca", "de", "fr"];

const identicalAllowlist = new Set([
  "AI",
  "App Store",
  "Actions",
  "Ambient",
  "Apps AV",
  "Apple",
  "Archive",
  "AV",
  "Avi",
  "Baidu",
  "Bing",
  "Brave",
  "Brave Search",
  "Browser",
  "Canada",
  "Catalan",
  "Chill",
  "Clerk",
  "Cloud Sync",
  "Code",
  "Community",
  "Country / Folk",
  "Dance",
  "Details",
  "DuckDuckGo",
  "Ecosia",
  "Feedback",
  "Filter",
  "France",
  "Free",
  "Genre",
  "Google",
  "Hip-Hop",
  "IMDb",
  "Indie",
  "Jazz",
  "Live",
  "Mock",
  "Navigation",
  "No",
  "OK",
  "Options",
  "Pause",
  "Plan",
  "Plans",
  "Pop",
  "Pro",
  "Qwant",
  "Radio",
  "Radios",
  "Rock",
  "Signal",
  "Song",
  "Songs",
  "Sports",
  "Start",
  "Station",
  "Stations",
  "Startpage",
  "System",
  "Tags",
  "Top %@",
  "Tune AV",
  "Tune AV Free",
  "Tune AV Pro",
  "Web",
  "Yahoo",
  "Yandex",
  "YouTube",
  "iTunes",
  "info",
  "%d min",
  "A-Z",
  "Attentive"
]);

const normalizedIdenticalAllowlist = new Set([...identicalAllowlist].map(normalizeText));

function normalizeText(value) {
  return String(value).replace(/\s+/g, " ").trim();
}

function parseStringsFile(filePath) {
  const source = readFileSync(filePath, "utf8");
  const entries = new Map();
  const pattern = /"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";/g;
  let match;
  while ((match = pattern.exec(source))) {
    entries.set(unescapeStringsValue(match[1]), unescapeStringsValue(match[2]));
  }
  return entries;
}

function unescapeStringsValue(value) {
  return value
    .replace(/\\"/g, "\"")
    .replace(/\\\\/g, "\\")
    .replace(/\\n/g, "\n")
    .replace(/\\r/g, "\r")
    .replace(/\\t/g, "\t");
}

function placeholders(value) {
  return normalizeText(value).match(/%(\d+\$)?[@df]|%\{[^}]+\}@/g) ?? [];
}

function compareAppleStrings() {
  const basePath = join(rootDir, "apps/ios/TuneAV/Resources/en.lproj/Localizable.strings");
  const base = parseStringsFile(basePath);
  const failures = [];

  for (const locale of appleLocales) {
    const filePath = join(rootDir, `apps/ios/TuneAV/Resources/${locale}.lproj/Localizable.strings`);
    const current = parseStringsFile(filePath);
    const missing = [...base.keys()].filter((key) => !current.has(key));
    const extra = [...current.keys()].filter((key) => !base.has(key));

    for (const key of missing) failures.push(`Apple ${locale}: missing key ${key}`);
    for (const key of extra) failures.push(`Apple ${locale}: extra key ${key}`);

    if (locale === "en") continue;

    for (const [key, englishValue] of base) {
      if (!current.has(key)) continue;
      const localizedValue = current.get(key);
      const englishPlaceholders = placeholders(englishValue).join(",");
      const localizedPlaceholders = placeholders(localizedValue).join(",");
      if (englishPlaceholders !== localizedPlaceholders) {
        failures.push(`Apple ${locale}: placeholder mismatch for ${key}`);
      }

      const normalizedEnglish = normalizeText(englishValue);
      const normalizedLocalized = normalizeText(localizedValue);
      if (
        normalizedEnglish &&
        normalizedEnglish === normalizedLocalized &&
        !normalizedIdenticalAllowlist.has(normalizedEnglish)
      ) {
        failures.push(`Apple ${locale}: identical to English for ${key}: ${normalizedEnglish}`);
      }
    }
  }

  return failures;
}

function compareWebStrings() {
  const auditSource = String.raw`
    import { tuneText } from "./src/lib/tune-i18n.ts";
    import { tuneFunctionalText } from "./src/lib/tune-functional-text.ts";
    import { tuneProfileLabels } from "./src/lib/tune-profile-labels.ts";

    const webLocales = ${JSON.stringify(webLocales)};
    const allowlist = new Set(${JSON.stringify([...normalizedIdenticalAllowlist])});
    const bundles = [
      ["tuneText", tuneText],
      ["tuneFunctionalText", tuneFunctionalText],
      ["tuneProfileLabels", tuneProfileLabels]
    ];

    function normalizeText(value) {
      return String(value).replace(/\s+/g, " ").trim();
    }

    function walk(value, path = []) {
      if (Array.isArray(value)) {
        return value.flatMap((entry, index) => walk(entry, [...path, String(index)]));
      }
      if (value && typeof value === "object") {
        return Object.entries(value).flatMap(([key, entry]) => walk(entry, [...path, key]));
      }
      return [[path.join("."), value]];
    }

    function shape(value, path = []) {
      if (Array.isArray(value)) {
        return [["array", path.join("."), value.length], ...value.flatMap((entry, index) => shape(entry, [...path, String(index)]))];
      }
      if (value && typeof value === "object") {
        const keys = Object.keys(value).sort();
        return [["object", path.join("."), keys.join(",")], ...keys.flatMap((key) => shape(value[key], [...path, key]))];
      }
      return [["leaf", path.join("."), typeof value]];
    }

    const failures = [];
    for (const [bundleName, bundle] of bundles) {
      const englishShape = JSON.stringify(shape(bundle.en));
      const englishLeaves = new Map(walk(bundle.en));
      for (const locale of webLocales) {
        const localizedShape = JSON.stringify(shape(bundle[locale]));
        if (localizedShape !== englishShape) {
          failures.push(bundleName + " " + locale + ": shape mismatch against English");
        }

        const localizedLeaves = new Map(walk(bundle[locale]));
        for (const [path, englishValue] of englishLeaves) {
          const localizedValue = localizedLeaves.get(path);
          if (typeof englishValue !== "string" || typeof localizedValue !== "string") continue;
          const normalizedEnglish = normalizeText(englishValue);
          const normalizedLocalized = normalizeText(localizedValue);
          if (normalizedEnglish && normalizedEnglish === normalizedLocalized && !allowlist.has(normalizedEnglish)) {
            failures.push(bundleName + " " + locale + ": identical to English for " + path + ": " + normalizedEnglish);
          }
        }
      }
    }

    if (failures.length > 0) {
      console.error(failures.join("\\n"));
      process.exit(1);
    }
  `;

  try {
    execFileSync("bun", ["--eval", auditSource], {
      cwd: join(rootDir, "apps/web"),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    });
    return [];
  } catch (error) {
    const stderr = typeof error.stderr === "string" ? error.stderr.trim() : "";
    const stdout = typeof error.stdout === "string" ? error.stdout.trim() : "";
    return [stderr, stdout].filter(Boolean);
  }
}

const failures = [...compareAppleStrings(), ...compareWebStrings()];

if (failures.length > 0) {
  console.error(`i18n parity audit failed with ${failures.length} issue(s):`);
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("i18n parity audit passed: Apple and web locales match English keys, shapes, placeholders, and translated text expectations.");
