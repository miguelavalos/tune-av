import { useAccountUser } from "@avalsys/account-av-web";
import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Cloud, ExternalLink, LogOut, ShieldCheck, User } from "lucide-react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAccountArea } from "@/components/tune-account-area";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { getLocalizedTuneProductConfig, tuneProductConfig } from "@/lib/tune-config";
import { tuneFunctionalText } from "@/lib/tune-functional-text";
import { useTune } from "@/lib/tune-store";
import { localizedTunePath, useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/settings")({
  component: SettingsRoute
});

function SettingsRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const labels = tuneFunctionalText[locale].settings;
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const productConfig = getLocalizedTuneProductConfig(locale);
  const tune = useTune();
  const account = useAccountUser();
  const planLabel = tune.access.accessMode === "signedInPro" ? "Tune AV Pro" : "Tune AV Free";
  const managementHref = tuneProductConfig.links.suite?.href;

  return (
    <ProtectedRoute>
      <AppShell accountArea={<TuneAccountArea />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={productConfig}>
        <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
          <section className="grid gap-4">
            <Card className="tune-paper rounded-lg border-[#d7c494] p-5 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
              <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><User className="size-4" /> {labels.account}</p>
              <h1 className="mt-2 text-3xl font-semibold">{account.data?.displayName ?? labels.accountFallback}</h1>
              <p className="mt-2 text-sm text-[#53617a]">{account.data?.email ?? labels.emailFallback}</p>
            </Card>

            <Card className="rounded-lg border-[#d7c494] bg-white/82 p-5 text-[#112a55]">
              <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><ShieldCheck className="size-4" /> {labels.plan}</p>
              <h2 className="mt-2 text-2xl font-semibold">{planLabel}</h2>
              <p className="mt-2 text-sm leading-6 text-[#53617a]">{labels.planBody}</p>
              {managementHref ? <ExternalButton href={localizedExternalHref(managementHref, locale)}>{labels.manage}</ExternalButton> : null}
            </Card>

            <Card className="rounded-lg border-[#d7c494] bg-white/82 p-5 text-[#112a55]">
              <p className="flex items-center gap-2 text-sm font-semibold text-[#087f79]"><Cloud className="size-4" /> {labels.sync}</p>
              <h2 className="mt-2 text-2xl font-semibold">{tune.access.capabilities.canUseCloudSync ? labels.syncAvailable : labels.localSync}</h2>
              <p className="mt-2 text-sm leading-6 text-[#53617a]">{labels.status}: {tune.syncStatus}. {tune.lastSyncedAt ? new Date(tune.lastSyncedAt).toLocaleString() : labels.noCloud}</p>
              <Button className="mt-4 rounded-lg" disabled={!tune.access.capabilities.canUseCloudSync || tune.syncStatus === "syncing"} onClick={() => void tune.synchronizeLibrary()}>{labels.syncNow}</Button>
            </Card>
          </section>

          <aside className="grid content-start gap-4">
            <Card className="rounded-lg border-[#d7c494] bg-[#fff8df]/88 p-5 text-[#112a55]">
              <h2 className="font-semibold">{labels.supportLegal}</h2>
              <div className="mt-3 grid gap-2 text-sm">
                {tuneProductConfig.links.support ? <ExternalText href={localizedExternalHref(tuneProductConfig.links.support.href, locale)}>{labels.support}</ExternalText> : null}
                {tuneProductConfig.links.privacy ? <ExternalText href={localizedExternalHref(tuneProductConfig.links.privacy.href, locale)}>{labels.privacy}</ExternalText> : null}
                {tuneProductConfig.links.terms ? <ExternalText href={localizedExternalHref(tuneProductConfig.links.terms.href, locale)}>{labels.terms}</ExternalText> : null}
                {tuneProductConfig.links.deleteAccount ? <ExternalText href={localizedExternalHref(tuneProductConfig.links.deleteAccount.href, locale)}>{labels.deleteAccount}</ExternalText> : null}
              </div>
            </Card>
            <Card className="rounded-lg border-[#d7c494] bg-[#fff8df]/88 p-5 text-[#112a55]">
              <h2 className="font-semibold">{labels.navigation}</h2>
              <Button asChild className="mt-3 w-full rounded-lg" variant="outline"><Link to={localizedTunePath("/library", locale)}>{labels.library}</Link></Button>
              <Button asChild className="mt-2 w-full rounded-lg" variant="outline"><Link to={localizedTunePath("/listen", locale)}>{labels.radio}</Link></Button>
              <p className="mt-4 flex items-center gap-2 text-xs text-[#53617a]"><LogOut className="size-3" /> {labels.signOut}</p>
            </Card>
          </aside>
        </div>
      </AppShell>
    </ProtectedRoute>
  );
}

function ExternalButton({ children, href }: { children: string; href: string }) {
  return <a className="mt-4 inline-flex items-center gap-2 rounded-lg bg-[#112a55] px-4 py-2 text-sm font-semibold text-white hover:bg-[#19396f]" href={href} rel="noreferrer" target="_blank">{children}<ExternalLink className="size-4" /></a>;
}

function ExternalText({ children, href }: { children: string; href: string }) {
  return <a className="inline-flex items-center gap-2 text-[#112a55] underline decoration-[#087f79]/40 underline-offset-4 hover:text-[#087f79]" href={href} rel="noreferrer" target="_blank">{children}<ExternalLink className="size-3" /></a>;
}

function localizedExternalHref(href: string, locale: string) {
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
