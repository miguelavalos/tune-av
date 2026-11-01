import {
  HelpLegalSection,
  SettingsInfoRow,
  SettingsOptionButtonGroup,
  SettingsProfileScaffold,
  SettingsSectionCard,
  appsAvLocaleNames,
  normalizeAppsAvThemePreference,
  readAppsAvThemePreference,
  useAppsAvLocale,
  type AppsAvLocale,
  type AppsAvThemePreference
} from "@avalsys/apps-av-web";
import { createFileRoute } from "@tanstack/react-router";
import { Contrast, Globe, Languages, Moon, Smartphone, Sun } from "lucide-react";
import { useEffect, useState } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { tuneProductConfig } from "@/lib/tune-config";
import { localizedTunePath } from "@/lib/tune-i18n";
import { tuneProfileLabels } from "@/lib/tune-profile-labels";
import { localizedExternalUrl } from "@/lib/tune-url";

export const Route = createFileRoute("/settings")({
  component: SettingsRoute
});

function SettingsRoute() {
  const locale = useAppsAvLocale();
  const labels = tuneProfileLabels[locale];
  const [theme, setThemeState] = useState<AppsAvThemePreference>("system");

  useEffect(() => {
    const storedTheme = normalizeAppsAvThemePreference(readAppsAvThemePreference(themeStorageKey));
    setThemeState(storedTheme);
    applyTheme(storedTheme);
  }, []);

  const setTheme = (nextTheme: AppsAvThemePreference) => {
    setThemeState(nextTheme);
    applyTheme(nextTheme);
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

          <HelpLegalSection labels={labels.help} links={helpLegalLinks(locale)} />
        </SettingsProfileScaffold>
      </TuneAppShell>
    </ProtectedRoute>
  );
}

const locales: AppsAvLocale[] = ["en", "es", "fr", "de", "ca"];
const themeStorageKey = "tuneav.web.theme";
const themeOptions: AppsAvThemePreference[] = ["system", "light", "dark"];

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
