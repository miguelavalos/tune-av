import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { useRouterState } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { getLocalizedTuneProductConfig } from "@/lib/tune-config";
import { useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export function TuneAppShell({ children }: { children: ReactNode }) {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const productConfig = getLocalizedTuneProductConfig(locale);
  const pathname = useRouterState({ select: (state) => state.location.pathname });

  return (
    <AppShell
      currentPath={pathname}
      footerLabels={text.footer}
      labels={shellLabels}
      navLinks={navLinks}
      product={productConfig}
    >
      {children}
    </AppShell>
  );
}
