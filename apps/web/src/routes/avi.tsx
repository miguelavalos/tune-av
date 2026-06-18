import { AccountUserButton } from "@avalsys/account-av-web";
import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { BookOpenCheck, CalendarDays, Compass, Radio, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { getLocalizedTuneProductConfig, tuneBrandAssets } from "@/lib/tune-config";
import { localizedTunePath, useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/avi")({
  component: AviRoute
});

function AviRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const productConfig = getLocalizedTuneProductConfig(locale);
  const cardIcons = [<BookOpenCheck className="size-4" />, <CalendarDays className="size-4" />, <Compass className="size-4" />];

  return (
    <ProtectedRoute>
      <AppShell accountArea={<AccountUserButton />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={productConfig}>
        <section className="grid gap-6 lg:grid-cols-[1.05fr_0.95fr]">
          <Card className="tune-paper gap-0 overflow-hidden rounded-[1.5rem] border-[#d7c494] p-0 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
            <div className="grid min-h-[32rem] lg:grid-cols-[0.95fr_1.05fr]">
              <div className="flex flex-col justify-between gap-8 p-6 sm:p-8">
                <div>
                  <p className="flex items-center gap-2 text-sm font-semibold text-[#5a8f2f]">
                    <Sparkles className="size-4" aria-hidden="true" />
                    Avi
                  </p>
                  <h1 className="mt-3 text-4xl font-semibold leading-tight">{text.avi.title}</h1>
                  <p className="mt-4 text-base leading-7 text-[#334766]">
                    {text.avi.body}
                  </p>
                </div>
                <div className="flex flex-wrap gap-3">
                  <Button asChild className="rounded-full bg-[#112a55] text-white hover:bg-[#19396f]">
                    <Link to={localizedTunePath("/listen", locale)}>
                      <Radio className="size-4" aria-hidden="true" />
                      {text.avi.radioCta}
                    </Link>
                  </Button>
                  <Button asChild variant="outline" className="rounded-full border-[#c8ad72] bg-[#fff8df]/76">
                    <Link to={localizedTunePath("/library", locale)}>{text.avi.libraryCta}</Link>
                  </Button>
                </div>
              </div>
              <div className="relative min-h-80 overflow-hidden bg-[#10284f]">
                <div className="absolute inset-0 bg-[linear-gradient(160deg,#17386c_0%,#10284f_56%,#07162e_100%)]" />
                <img className="relative h-full w-full object-cover object-bottom" src={tuneBrandAssets.aviLoginPeek} alt="" />
              </div>
            </div>
          </Card>

          <div className="grid gap-4">
            {text.avi.cards.map((card, index) => (
              <AviCard key={card.title} icon={cardIcons[index]} title={card.title} text={card.text} />
            ))}
          </div>
        </section>
      </AppShell>
    </ProtectedRoute>
  );
}

function AviCard({ icon, text, title }: { icon: ReactNode; text: string; title: string }) {
  return (
    <Card className="gap-2 rounded-[1.25rem] border-[#d7c494] bg-[#fff8df]/88 p-5 py-5 text-[#112a55] shadow-sm shadow-[#172f5c]/6">
      <div className="flex items-center gap-2 text-sm font-semibold">
        <span className="text-[#5a8f2f]">{icon}</span>
        {title}
      </div>
      <p className="text-sm leading-6 text-[#53617a]">{text}</p>
    </Card>
  );
}
