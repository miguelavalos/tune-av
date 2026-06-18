import { AccountAvProvider } from "@avalsys/account-av-web";
import { AppsAvWebProvider, getAppsAvLocaleFromSearch, useAppsAvLocale } from "@avalsys/apps-av-web";
import { createIsomorphicFn } from "@tanstack/react-start";
import { HeadContent, Outlet, Scripts, createRootRoute } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { getAccountApiBaseUrl, getAccountPublishableKey } from "@/lib/tune-config";
import { getRequestSearch } from "@/lib/tune-request.server";
import { TunePlayer } from "@/components/tune-player";
import { TuneAppProvider } from "@/lib/tune-store";
import { localizedTunePath, useTuneAccountLocalization, useTuneText } from "@/lib/tune-i18n";
import "../styles.css";

export const Route = createRootRoute({
  component: RootComponent,
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Tune AV" }
    ]
  })
});

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
      <TuneAppProvider>
        {children}
        <TunePlayer />
      </TuneAppProvider>
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
