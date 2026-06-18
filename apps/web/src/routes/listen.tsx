import { AccountUserButton } from "@avalsys/account-av-web";
import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { createFileRoute } from "@tanstack/react-router";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneListen } from "@/components/tune-listen";
import { getLocalizedTuneProductConfig } from "@/lib/tune-config";
import { useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/listen")({
  component: ListenRoute
});

function ListenRoute() {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const productConfig = getLocalizedTuneProductConfig(locale);

  return (
    <ProtectedRoute>
      <AppShell accountArea={<AccountUserButton />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={productConfig}>
        <TuneListen />
      </AppShell>
    </ProtectedRoute>
  );
}
