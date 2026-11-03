#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
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
  "Spotify",
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

function shortcutPlaceholders(value) {
  return (normalizeText(value).match(/\$\{[A-Za-z]+\}/g) ?? []).sort();
}

function compareAppleShortcutPhrases() {
  const basePath = join(rootDir, "apps/ios/TuneAV/Resources/en.lproj/AppShortcuts.strings");
  const base = parseStringsFile(basePath);
  const failures = [];

  if (base.size === 0) failures.push("Apple App Shortcuts en: no phrases");

  const providerPath = join(rootDir, "apps/ios/TuneAV/Core/Siri/TuneAVAppShortcuts.swift");
  const providerSource = readFileSync(providerPath, "utf8");
  const codePhrases = [...providerSource.matchAll(/"((?:\\.|[^"\\])*\\\(\.applicationName\)(?:\\.|[^"\\])*)"/g)].map((match) =>
    match[1].replace(/\\\(\.applicationName\)/g, "${applicationName}").replace(/\\\(\\\.\$([A-Za-z]+)\)/g, "${$1}")
  );
  if (codePhrases.length === 0) failures.push("Apple App Shortcuts: no phrases found in TuneAVAppShortcuts.swift");
  for (const phrase of codePhrases) {
    if (!base.has(phrase)) failures.push(`Apple App Shortcuts en: code phrase without a localized entry ${phrase}`);
  }
  for (const key of base.keys()) {
    if (!codePhrases.includes(key)) failures.push(`Apple App Shortcuts en: phrase not used in code ${key}`);
  }

  for (const locale of appleLocales) {
    const filePath = join(rootDir, `apps/ios/TuneAV/Resources/${locale}.lproj/AppShortcuts.strings`);
    let current;
    try {
      current = parseStringsFile(filePath);
    } catch {
      failures.push(`Apple App Shortcuts ${locale}: missing AppShortcuts.strings`);
      continue;
    }
    const missing = [...base.keys()].filter((key) => !current.has(key));
    const extra = [...current.keys()].filter((key) => !base.has(key));

    for (const key of missing) failures.push(`Apple App Shortcuts ${locale}: missing phrase ${key}`);
    for (const key of extra) failures.push(`Apple App Shortcuts ${locale}: extra phrase ${key}`);

    for (const [key, value] of current) {
      if (!base.has(key)) continue;
      if (!value.includes("${applicationName}")) {
        failures.push(`Apple App Shortcuts ${locale}: phrase without \${applicationName} for ${key}`);
      }
      if (shortcutPlaceholders(key).join(",") !== shortcutPlaceholders(value).join(",")) {
        failures.push(`Apple App Shortcuts ${locale}: parameter mismatch for ${key}`);
      }
      if (locale === "en") {
        if (normalizeText(key) !== normalizeText(value)) {
          failures.push(`Apple App Shortcuts en: phrase differs from its key ${key}`);
        }
      } else if (normalizeText(key) === normalizeText(value)) {
        failures.push(`Apple App Shortcuts ${locale}: identical to English for ${key}`);
      }
    }
  }

  return failures;
}

function compareWebStrings() {
  const appWebDir = join(rootDir, "apps/web");
  const auditFilePath = join(appWebDir, ".i18n-parity-audit.test.ts");
  const auditSource = String.raw`
    import { describe, it } from "vite-plus/test";
    import { tuneText } from "./src/lib/tune-i18n.ts";
    import { tuneProfileLabels } from "./src/lib/tune-profile-labels.ts";

    const webLocales = ${JSON.stringify(webLocales)};
    const allowlist = new Set(${JSON.stringify([...normalizedIdenticalAllowlist])});
    const bundles = [
      ["tuneText", tuneText],
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

    describe("Tune AV web i18n parity", () => {
      it("matches English keys, shapes, and translated text expectations", () => {
        if (failures.length > 0) {
          throw new Error(failures.join("\\n"));
        }
      });
    });
  `;

  try {
    writeFileSync(auditFilePath, auditSource);
    execFileSync("vp", ["test", ".i18n-parity-audit.test.ts"], {
      cwd: appWebDir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    });
    return [];
  } catch (error) {
    const stderr = typeof error.stderr === "string" ? error.stderr.trim() : "";
    const stdout = typeof error.stdout === "string" ? error.stdout.trim() : "";
    return [stderr, stdout].filter(Boolean);
  } finally {
    try {
      unlinkSync(auditFilePath);
    } catch {
      // The file may not have been written if process startup failed early.
    }
  }
}

const failures = [...compareAppleStrings(), ...compareAppleShortcutPhrases(), ...compareWebStrings()];

if (failures.length > 0) {
  console.error(`i18n parity audit failed with ${failures.length} issue(s):`);
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("i18n parity audit passed: Apple strings, App Shortcut phrases and web locales match English keys, shapes, placeholders, and translated text expectations.");
