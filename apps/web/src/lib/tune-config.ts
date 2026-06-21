import type { AppsAvLocale, AppsAvProductConfig } from "@avalsys/apps-av-web";

const tuneCommercialWordmarkUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/tune-av-wordmark.webp";
const tuneCommercialHeroLogoUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/tune-av-hero-logo.webp";

export const tuneProductConfig: AppsAvProductConfig = {
  appId: "tuneav",
  accentColor: "#29D3C8",
  assistant: {
    href: "/avi",
    imageSrc: "/assets/avi-footer-icon.png",
    label: "Open Avi guidance",
    name: "Avi"
  },
  iconSrc: "/assets/tune-av-icon.png",
  logoSrc: tuneCommercialWordmarkUrl,
  logoDarkSrc: tuneCommercialWordmarkUrl,
  name: "Tune AV",
  links: {
    deleteAccount: externalLink(accountManagementUrl("/account/delete"), "Delete account"),
    privacy: externalLink(import.meta.env.VITE_TUNEAV_PRIVACY_URL, "Privacy"),
    suite: externalLink(import.meta.env.VITE_ACCOUNTAV_MANAGEMENT_URL, "Apps"),
    support: externalLink(supportUrl(), "Support"),
    terms: externalLink(import.meta.env.VITE_TUNEAV_TERMS_URL, "Terms"),
    website: externalLink("https://tune-av.avalsys.com", "Tune AV")
  }
};

export function getLocalizedTuneProductConfig(locale: AppsAvLocale): AppsAvProductConfig {
  const labels = productConfigLabels[locale] ?? productConfigLabels.en;

  return {
    ...tuneProductConfig,
    assistant: tuneProductConfig.assistant
      ? {
          ...tuneProductConfig.assistant,
          href: localizedAppPath("/avi", locale),
          label: labels.assistant
        }
      : undefined,
    links: {
      deleteAccount: localizeExternalLink(tuneProductConfig.links.deleteAccount, labels.deleteAccount, locale),
      privacy: localizeExternalLink(tuneProductConfig.links.privacy, labels.privacy, locale),
      suite: localizeExternalLink(tuneProductConfig.links.suite, labels.suite, locale),
      support: localizeExternalLink(tuneProductConfig.links.support, labels.support, locale),
      terms: localizeExternalLink(tuneProductConfig.links.terms, labels.terms, locale),
      website: localizeExternalLink(tuneProductConfig.links.website, labels.website, locale)
    }
  };
}

export const tuneBrandAssets = {
  aviFullBody: "/assets/avi-full-body.png",
  aviLoginPeek: "/assets/tune-av-splash.jpg",
  aviLoginSheetPeek: "/assets/avi-login-sheet-peek.png",
  aviOnboardingCta: "/assets/avi-onboarding-cta.png",
  guestHomeDial: "/assets/tune-av-guest-home-1.webp",
  guestHomeStation: "/assets/tune-av-guest-home-2.webp",
  guestHomeAvi: "/assets/tune-av-guest-home-3.webp",
  logo: tuneCommercialHeroLogoUrl,
  logoDark: "/assets/tune-av-logo-dark.png",
  onboarding: "/assets/tune-av-onboarding.jpg",
  wordmark: tuneCommercialWordmarkUrl
} as const;

export function getAccountApiBaseUrl() {
  return requiredUrl(import.meta.env.VITE_ACCOUNTAV_API_BASE_URL, "VITE_ACCOUNTAV_API_BASE_URL");
}

export function getAccountPublishableKey() {
  return import.meta.env.VITE_ACCOUNTAV_PUBLISHABLE_KEY as string | undefined;
}

export function getTuneApiBaseUrl() {
  return requiredUrl(import.meta.env.VITE_TUNEAV_API_BASE_URL, "VITE_TUNEAV_API_BASE_URL");
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

function localizedAppPath(pathname: string, locale: AppsAvLocale) {
  const path = pathname || "/";
  const separator = path.includes("?") ? "&" : "?";

  return locale === "en" ? path : `${path}${separator}lang=${locale}`;
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

const productConfigLabels: Record<AppsAvLocale, { assistant: string; deleteAccount: string; privacy: string; suite: string; support: string; terms: string; website: string }> = {
  ca: { assistant: "Obre la guia d'Avi", deleteAccount: "Eliminar compte", privacy: "Privacitat", suite: "Apps", support: "Suport", terms: "Termes", website: "Tune AV" },
  de: { assistant: "Avi-Hilfe oeffnen", deleteAccount: "Konto loeschen", privacy: "Datenschutz", suite: "Apps", support: "Hilfe", terms: "Bedingungen", website: "Tune AV" },
  en: { assistant: "Open Avi guidance", deleteAccount: "Delete account", privacy: "Privacy", suite: "Apps", support: "Support", terms: "Terms", website: "Tune AV" },
  es: { assistant: "Abrir guia de Avi", deleteAccount: "Eliminar cuenta", privacy: "Privacidad", suite: "Apps", support: "Soporte", terms: "Terminos", website: "Tune AV" },
  fr: { assistant: "Ouvrir l'aide d'Avi", deleteAccount: "Supprimer le compte", privacy: "Confidentialite", suite: "Apps", support: "Assistance", terms: "Conditions", website: "Tune AV" }
};
