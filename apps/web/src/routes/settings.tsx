import {
  SettingsActionRow,
  HelpLegalSection,
  SettingsInfoRow,
  SettingsOptionButtonGroup,
  SettingsProfileScaffold,
  SettingsSectionCard,
  appsAvExternalSearchEngines,
  appsAvLocaleNames,
  normalizeAppsAvThemePreference,
  readAppsAvThemePreference,
  useAppsAvLocale,
  type AppsAvExternalSearchEngine,
  type AppsAvLocale,
  type AppsAvThemePreference
} from "@avalsys/apps-av-web";
import { createFileRoute } from "@tanstack/react-router";
import { Contrast, Globe, HardDrive, Languages, ListMusic, Moon, Music, Radio, Search, Smartphone, Sun, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { tuneProductConfig } from "@/lib/tune-config";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { localizedTunePath } from "@/lib/tune-i18n";
import { tuneProfileLabels } from "@/lib/tune-profile-labels";
import { useTune } from "@/lib/tune-store";
import { localizedExternalUrl } from "@/lib/tune-url";

export const Route = createFileRoute("/settings")({
  component: SettingsRoute
});

function SettingsRoute() {
  const locale = useAppsAvLocale();
  const tune = useTune();
  const labels = tuneProfileLabels[locale];
  const functionalLabels = tuneFunctionalText[locale].listen;
  const [theme, setThemeState] = useState<AppsAvThemePreference>("system");
  const localItemCount = tune.favoriteStations.length + tune.recentStations.length + tune.discoveries.length + Object.keys(tune.stationFeedback).length + Object.keys(tune.trackFeedback).length;

  useEffect(() => {
    const storedTheme = normalizeAppsAvThemePreference(readAppsAvThemePreference(themeStorageKey));
    setThemeState(storedTheme);
    applyTheme(storedTheme);
  }, []);

  const setTheme = (nextTheme: AppsAvThemePreference) => {
    setThemeState(nextTheme);
    applyTheme(nextTheme);
  };

  const clearLocalData = () => {
    const detail = localItemCount === 0 ? labels.local.delete.empty : labels.local.delete.detail(localItemCount);
    if (window.confirm(`${labels.local.delete.confirmTitle}\n\n${labels.local.delete.confirmDetail}\n\n${detail}`)) {
      tune.clearLocalData();
    }
  };

  return (
    <ProtectedRoute>
      <TuneAppShell>
        <SettingsProfileScaffold title={labels.settingsTitle} subtitle={labels.settingsSubtitle} heroClassName="tune-paper">
          <SettingsSectionCard title={labels.preferences.title} subtitle={labels.preferences.subtitle}>
            <SettingsInfoRow icon={<Globe className="size-5" />} title={labels.preferences.languageTitle} detail={labels.preferences.languageDetail} />
            <SettingsOptionButtonGroup
              selectedId={locale}
              onSelect={(id) => {
                window.location.href = localizedTunePath("/settings", id as AppsAvLocale);
              }}
              options={locales.map((item) => ({
                id: item,
                icon: item === locale ? <Languages className="size-4" /> : undefined,
                label: `${languageDisplayNames[locale][item]} (${appsAvLocaleNames[item]})`
              }))}
            />
            <SettingsInfoRow icon={<Contrast className="size-5" />} title={labels.preferences.themeTitle} detail={labels.preferences.themeDetail} />
            <SettingsOptionButtonGroup
              selectedId={theme}
              onSelect={(id) => setTheme(id as AppsAvThemePreference)}
              options={themeOptions.map((item) => ({
                id: item,
                icon: themeIcon(item),
                label: labels.preferences.themeOptions[item]
              }))}
            />
          </SettingsSectionCard>

          <SettingsSectionCard title={labels.tune.title} subtitle={labels.tune.subtitle}>
            <SettingsInfoRow icon={<Radio className="size-5" />} title={labels.tune.countryTitle} detail={labels.tune.countryDetail} />
            <SettingsOptionButtonGroup
              selectedId={tune.settings.preferredCountryCode || "worldwide"}
              onSelect={(id) => tune.setPreferredCountry(id === "worldwide" ? "" : id)}
              options={countryOptions.map((item) => ({ id: item, label: functionalLabels.countries[item as keyof typeof functionalLabels.countries] ?? item }))}
            />
            <SettingsInfoRow icon={<ListMusic className="size-5" />} title={labels.tune.discoveryTitle} detail={labels.tune.discoveryDetail} />
            <SettingsOptionButtonGroup
              selectedId={tune.settings.discoveryMode}
              onSelect={(id) => tune.setDiscoveryMode(id as "music" | "allRadio")}
              options={[
                { id: "music", icon: <Music className="size-4" />, label: labels.tune.discoveryOptions.music },
                { id: "allRadio", icon: <Radio className="size-4" />, label: labels.tune.discoveryOptions.allRadio }
              ]}
            />
            <SettingsInfoRow icon={<Search className="size-5" />} title={labels.tune.externalSearchTitle} detail={labels.tune.externalSearchDetail} />
            <label className="grid gap-2">
              <span className="sr-only">{labels.tune.externalSearchTitle}</span>
              <select
                className="h-12 w-full rounded-lg border border-[#d7dfd2] bg-[#f7faf5] px-4 text-sm font-semibold text-[#283a2d] outline-none transition focus:border-[#68b957] focus:ring-2 focus:ring-[#68b957]/25 dark:border-white/12 dark:bg-white/8 dark:text-white"
                value={tune.settings.externalSearchEngine}
                onChange={(event) => tune.setExternalSearchEngine(event.target.value as AppsAvExternalSearchEngine)}
              >
                {appsAvExternalSearchEngines.map((engine) => (
                  <option key={engine} value={engine}>
                    {labels.tune.externalSearchOptions[engine]}
                  </option>
                ))}
              </select>
            </label>
          </SettingsSectionCard>

          <SettingsSectionCard title={labels.local.title} subtitle={labels.local.subtitle}>
            <SettingsInfoRow icon={<Smartphone className="size-5" />} title={labels.local.libraryTitle} detail={labels.local.libraryDetail} />
            <SettingsInfoRow icon={<HardDrive className="size-5" />} title={labels.local.syncTitle} detail={labels.local.syncDetail} />
            <SettingsActionRow
              icon={<Trash2 className="size-5" />}
              title={labels.local.delete.title}
              detail={localItemCount === 0 ? labels.local.delete.empty : labels.local.delete.detail(localItemCount)}
              disabled={localItemCount === 0}
              onAction={clearLocalData}
            />
          </SettingsSectionCard>

          <HelpLegalSection labels={labels.help} links={helpLegalLinks(locale)} />
        </SettingsProfileScaffold>
      </TuneAppShell>
    </ProtectedRoute>
  );
}

const locales: AppsAvLocale[] = ["en", "es", "fr", "de", "ca"];
const themeStorageKey = "tuneav.web.theme";
const themeOptions: AppsAvThemePreference[] = ["system", "light", "dark"];
const countryOptions = ["worldwide", "US", "ES", "GB", "DE", "FR", "CA"];

function themeIcon(theme: AppsAvThemePreference) {
  if (theme === "light") return <Sun className="size-4" />;
  if (theme === "dark") return <Moon className="size-4" />;
  return <Smartphone className="size-4" />;
}

function helpLegalLinks(locale: AppsAvLocale) {
  return {
    deleteAccount: localizedExternalUrl(tuneProductConfig.links.deleteAccount?.href, locale),
    openSource: localizedExternalUrl(openSourceUrl(), locale),
    privacy: localizedExternalUrl(tuneProductConfig.links.privacy?.href, locale),
    support: localizedExternalUrl(tuneProductConfig.links.support?.href, locale),
    terms: localizedExternalUrl(tuneProductConfig.links.terms?.href, locale)
  };
}

function openSourceUrl() {
  return import.meta.env.VITE_TUNEAV_OPEN_SOURCE_URL || "https://github.com/avalsys/tune-av";
}

function applyTheme(theme: AppsAvThemePreference) {
  const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const dark = theme === "dark" || (theme === "system" && systemDark);
  document.documentElement.classList.toggle("dark", dark);
  if (theme === "system") {
    window.localStorage.removeItem(themeStorageKey);
  } else {
    window.localStorage.setItem(themeStorageKey, theme);
  }
}

const languageDisplayNames: Record<AppsAvLocale, Record<AppsAvLocale, string>> = {
  ca: { ca: "Catala", de: "Alemany", en: "Angles", es: "Espanyol", fr: "Frances" },
  de: { ca: "Katalanisch", de: "Deutsch", en: "Englisch", es: "Spanisch", fr: "Franzoesisch" },
  en: { ca: "Catalan", de: "German", en: "English", es: "Spanish", fr: "French" },
  es: { ca: "Catalan", de: "Aleman", en: "Ingles", es: "Espanol", fr: "Frances" },
  fr: { ca: "Catalan", de: "Allemand", en: "Anglais", es: "Espagnol", fr: "Francais" }
};
