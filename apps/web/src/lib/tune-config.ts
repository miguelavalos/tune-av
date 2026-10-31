import type { AppsAvLocale, AppsAvProductConfig } from "@avalsys/apps-av-web";

const tuneCommercialWordmarkUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/tune-av-wordmark.webp";
const tuneCommercialHeroLogoUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/tune-av-hero-logo.webp";

export const tuneProductConfig: AppsAvProductConfig = {
  appId: "tuneav",
  accentColor: "#29D3C8",
  iconSrc: "/assets/tune-av-icon.png",
  logoSrc: tuneCommercialWordmarkUrl,
  logoDarkSrc: tuneCommercialWordmarkUrl,
  name: "Tune AV",
  links: {
    deleteAccount: externalLink(accountManagementUrl("/account/delete"), "Delete account"),
    privacy: externalLink(import.meta.env.VITE_TUNEAV_PRIVACY_URL, "Privacy"),
    suite: externalLink(import.meta.env.VITE_ACCOUNTAV_MANAGEMENT_URL, "Apps"),
    support: externalLink(supportUrl(), "Support"),
    terms: externalLink(import.meta.env.VITE_TUNEAV_TERMS_URL, "Terms")
  }
};

export function getLocalizedTuneProductConfig(locale: AppsAvLocale): AppsAvProductConfig {
  const labels = productConfigLabels[locale] ?? productConfigLabels.en;

  return {
    ...tuneProductConfig,
    links: {
      deleteAccount: localizeExternalLink(tuneProductConfig.links.deleteAccount, labels.deleteAccount, locale),
      privacy: localizeExternalLink(tuneProductConfig.links.privacy, labels.privacy, locale),
      suite: localizeExternalLink(tuneProductConfig.links.suite, labels.suite, locale),
      support: localizeExternalLink(tuneProductConfig.links.support, labels.support, locale),
      terms: localizeExternalLink(tuneProductConfig.links.terms, labels.terms, locale)
    }
  };
}

// Same App Store listing and localized badges as the commercial site (avalsys-suite site-core marketing content).
export const tuneAppStore = {
  url: "https://apps.apple.com/us/app/tune-av/id6766301702",
  badges: {
    ca: "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/ca-es?size=250x83",
    de: "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/de-de?size=250x83",
    en: "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83",
    es: "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/es-es?size=250x83",
    fr: "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/fr-fr?size=250x83"
  }
} as const satisfies { url: string; badges: Record<AppsAvLocale, string> };

export const tuneBrandAssets = {
  aviFullBody: "/assets/avi-full-body.png",
  aviLoginSheetPeek: "/assets/avi-login-sheet-peek.png",
  guestHomeDial: "/assets/tune-av-guest-home-1.webp",
  guestHomeStation: "/assets/tune-av-guest-home-2.webp",
  logo: tuneCommercialHeroLogoUrl,
  onboarding: "/assets/tune-av-onboarding.jpg"
} as const;

export function getAccountApiBaseUrl() {
  return requiredUrl(import.meta.env.VITE_ACCOUNTAV_API_BASE_URL, "VITE_ACCOUNTAV_API_BASE_URL");
}

export function getAccountPublishableKey() {
  return import.meta.env.VITE_ACCOUNTAV_PUBLISHABLE_KEY as string | undefined;
}

export function isTuneWebAppComingSoon() {
  return import.meta.env.VITE_TUNEAV_WEBAPP_COMING_SOON === "true";
}

function requiredUrl(value: string | undefined, key: string) {
  const normalized = trimTrailingSlash(value);
  if (!normalized) {
    throw new Error(`${key} is required.`);
  }
  return normalized;
}

function accountManagementUrl(path: string) {
  const baseUrl = trimTrailingSlash(import.meta.env.VITE_ACCOUNTAV_MANAGEMENT_URL);
  return baseUrl ? `${baseUrl}${path}` : undefined;
}

function supportUrl() {
  return trimTrailingSlash(import.meta.env.VITE_SUPPORTAV_BASE_URL) || commercialSiteUrl("/support");
}

function commercialSiteUrl(path: string) {
  const privacyUrl = trimTrailingSlash(import.meta.env.VITE_TUNEAV_PRIVACY_URL);
  const url = privacyUrl ? new URL(privacyUrl) : new URL("https://tune-av.avalsys.com");
  return `${url.origin}${path}`;
}

function externalLink(href: string | undefined, label: string) {
  const normalized = normalizeHref(href);
  return normalized ? { href: normalized, label, external: true } : undefined;
}

function localizeExternalLink(link: AppsAvProductConfig["links"][keyof AppsAvProductConfig["links"]], label: string, locale: AppsAvLocale = "en") {
  return link ? { ...link, href: localizedExternalUrl(link.href, locale), label } : undefined;
}

function normalizeHref(value: string | undefined) {
  if (!value) {
    return "";
  }

  return value.startsWith("mailto:") ? value.trim() : trimTrailingSlash(value);
}

function trimTrailingSlash(value: string | undefined) {
  return value?.trim().replace(/\/+$/, "") ?? "";
}

function localizedExternalUrl(href: string, locale: AppsAvLocale) {
  if (locale === "en") return href;

  try {
    const url = new URL(href);
    const path = url.pathname === "/" ? "" : url.pathname.replace(/^\/(en|es|fr|de|ca)(?=\/|$)/, "");
    url.pathname = `/${locale}${path}`;
    return url.toString().replace(/\/$/, "");
  } catch {
    return href;
  }
}

const productConfigLabels: Record<AppsAvLocale, { deleteAccount: string; privacy: string; suite: string; support: string; terms: string; website: string }> = {
  ca: { deleteAccount: "Eliminar compte", privacy: "Privacitat", suite: "Apps", support: "Suport", terms: "Termes", website: "Tune AV" },
  de: { deleteAccount: "Konto loeschen", privacy: "Datenschutz", suite: "Apps", support: "Hilfe", terms: "Bedingungen", website: "Tune AV" },
  en: { deleteAccount: "Delete account", privacy: "Privacy", suite: "Apps", support: "Support", terms: "Terms", website: "Tune AV" },
  es: { deleteAccount: "Eliminar cuenta", privacy: "Privacidad", suite: "Apps", support: "Soporte", terms: "Terminos", website: "Tune AV" },
  fr: { deleteAccount: "Supprimer le compte", privacy: "Confidentialite", suite: "Apps", support: "Assistance", terms: "Conditions", website: "Tune AV" }
};
