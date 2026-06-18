import type { AppsAvLocale, AppsAvProductConfig } from "@avalsys/apps-av-web";

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
  logoSrc: "/assets/tune-av-logo.png",
  logoDarkSrc: "/assets/tune-av-logo-dark.png",
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
  return {
    ...tuneProductConfig,
    assistant: tuneProductConfig.assistant
      ? {
          ...tuneProductConfig.assistant,
          href: localizedAppPath("/avi", locale)
        }
      : undefined
  };
}

export const tuneBrandAssets = {
  aviFullBody: "/assets/avi-full-body.png",
  aviLoginPeek: "/assets/tune-av-splash.jpg",
  aviLoginSheetPeek: "/assets/avi-login-sheet-peek.png",
  aviOnboardingCta: "/assets/avi-onboarding-cta.png",
  logo: "/assets/tune-av-logo.png",
  logoDark: "/assets/tune-av-logo-dark.png",
  onboarding: "/assets/tune-av-onboarding.jpg",
  wordmark: "/assets/tune-av-logo.png"
} as const;

export function getAccountApiBaseUrl() {
  return requiredUrl(import.meta.env.VITE_ACCOUNTAV_API_BASE_URL, "VITE_ACCOUNTAV_API_BASE_URL");
}

export function getAccountPublishableKey() {
  return import.meta.env.VITE_ACCOUNTAV_PUBLISHABLE_KEY as string | undefined;
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
