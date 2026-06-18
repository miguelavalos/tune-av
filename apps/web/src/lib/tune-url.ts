import type { AppsAvLocale } from "@avalsys/apps-av-web";

export function localizedExternalUrl(href: string | undefined, locale: AppsAvLocale) {
  if (!href || locale === "en") return href;

  try {
    const url = new URL(href);
    const path = url.pathname === "/" ? "" : url.pathname.replace(/^\/(en|es|fr|de|ca)(?=\/|$)/, "");
    url.pathname = `/${locale}${path}`;
    return url.toString().replace(/\/$/, "");
  } catch {
    return href;
  }
}
