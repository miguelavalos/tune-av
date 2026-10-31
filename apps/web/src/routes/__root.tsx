import { AccountAvProvider } from "@avalsys/account-av-web";
import { AppsAvWebProvider, getAppsAvLocaleFromSearch, useAppsAvLocale } from "@avalsys/apps-av-web";
import { createIsomorphicFn } from "@tanstack/react-start";
import { HeadContent, Outlet, Scripts, createRootRoute, redirect, useRouterState } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { useEffect } from "react";
import { getAccountApiBaseUrl, getAccountPublishableKey, isTuneWebAppComingSoon, tuneBrandAssets } from "@/lib/tune-config";
import { getRequestSearch } from "@/lib/tune-request.server";
import { localizedTunePath, tuneText, useTuneAccountLocalization, useTuneText } from "@/lib/tune-i18n";
import "../styles.css";

const faviconUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/favicon-32x32.png?v=20260619c";
const appleTouchIconUrl = "https://cdn.avalsys.com/apps-av/tune-av/web-v2/apple-touch-icon.png?v=20260619c";
const siteUrl = "https://app.tune-av.avalsys.com";

export const Route = createRootRoute({
  beforeLoad: ({ location }) => {
    if (isTuneWebAppComingSoon() && location.pathname !== "/") {
      throw redirect({ href: comingSoonHomeHref(location.searchStr) });
    }
  },
  component: RootComponent,
  head: ({ match }) => {
    const lang = (match.search as { lang?: unknown }).lang;
    const locale = getAppsAvLocaleFromSearch(typeof lang === "string" ? `?lang=${encodeURIComponent(lang)}` : "");
    const description = tuneText[locale].meta.description;

    return {
      meta: [
        { charSet: "utf-8" },
        { name: "viewport", content: "width=device-width, initial-scale=1" },
        { title: "Tune AV" },
        { name: "description", content: description },
        { property: "og:type", content: "website" },
        { property: "og:site_name", content: "Tune AV" },
        { property: "og:title", content: "Tune AV" },
        { property: "og:description", content: description },
        { property: "og:url", content: siteUrl },
        { property: "og:image", content: tuneBrandAssets.logo },
        { name: "twitter:card", content: "summary" }
      ],
      links: [
        { rel: "icon", type: "image/png", sizes: "32x32", href: faviconUrl },
        { rel: "apple-touch-icon", href: appleTouchIconUrl }
      ]
    };
  }
});

function comingSoonHomeHref(searchStr: string) {
  const lang = new URLSearchParams(searchStr).get("lang");
  return lang ? `/?lang=${encodeURIComponent(lang)}` : "/";
}

function RootComponent() {
  return (
    <RootDocument>
      <Outlet />
    </RootDocument>
  );
}

function RootDocument({ children }: Readonly<{ children: ReactNode }>) {
  const search = getInitialSearch();
  const initialLocale = getAppsAvLocaleFromSearch(search);

  return (
    <html lang={initialLocale}>
      <head>
        <HeadContent />
      </head>
      <body>
        <AppsAvWebProvider initialLocale={initialLocale}>
          <ComingSoonRouteGate />
          <AccountBoundary>{children}</AccountBoundary>
        </AppsAvWebProvider>
        <Scripts />
      </body>
    </html>
  );
}

const getInitialSearch = createIsomorphicFn()
  .client(() => window.location.search)
  .server(() => getRequestSearch());

function ComingSoonRouteGate() {
  const locale = useAppsAvLocale();
  const pathname = useRouterState({ select: (state) => state.location.pathname });

  useEffect(() => {
    if (isTuneWebAppComingSoon() && pathname !== "/") {
      window.location.replace(localizedTunePath("/", locale));
    }
  }, [locale, pathname]);

  return null;
}

function AccountBoundary({ children }: Readonly<{ children: ReactNode }>) {
  const publishableKey = getAccountPublishableKey();
  const locale = useAppsAvLocale();
  const localization = useTuneAccountLocalization();

  if (!publishableKey) {
    return <MissingAuthConfiguration />;
  }

  return (
    <AccountAvProvider
      accountApiBaseUrl={getAccountApiBaseUrl()}
      afterSignOutUrl={localizedTunePath("/sign-in", locale)}
      appDisplayName="Tune AV"
      appId="tuneav"
      localization={localization}
      publishableKey={publishableKey}
      signInUrl={localizedTunePath("/sign-in", locale)}
      signUpUrl={localizedTunePath("/sign-in", locale)}
    >
      {children}
    </AccountAvProvider>
  );
}

function MissingAuthConfiguration() {
  const text = useTuneText();

  return (
    <main className="mx-auto flex min-h-screen max-w-3xl flex-col justify-center px-6">
      <div className="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-muted-foreground">{text.config.eyebrow}</p>
        <h1 className="mt-4 text-3xl font-semibold text-foreground">{text.config.title}</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">{text.config.body}</p>
      </div>
    </main>
  );
}
