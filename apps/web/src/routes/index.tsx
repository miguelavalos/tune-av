import { AccountUserButton, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AppShell, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, BookOpenCheck, CalendarDays, Radio, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TuneLoginPage } from "@/components/tune-login-page";
import { tuneBrandAssets, tuneProductConfig } from "@/lib/tune-config";
import { localizedTunePath, useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/")({
  component: IndexRoute
});

function IndexRoute() {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const homeIcons = [<Radio className="size-4" />, <BookOpenCheck className="size-4" />, <CalendarDays className="size-4" />];

  return (
    <>
      <SignedOut>
        <TuneLoginPage />
      </SignedOut>
      <SignedIn>
        <AppShell accountArea={<AccountUserButton />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={tuneProductConfig}>
          <section className="grid gap-6 lg:grid-cols-[1fr_22rem]">
            <Card className="tune-paper gap-0 overflow-hidden rounded-[1.5rem] border-[#d7c494] p-6 py-6 shadow-lg shadow-[#172f5c]/8 sm:p-8 sm:py-8">
              <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <h1 className="max-w-2xl text-4xl font-semibold leading-tight text-[#112a55]">{text.home.title}</h1>
                  <p className="mt-4 max-w-2xl text-base leading-7 text-[#334766]">
                    {text.home.body}
                  </p>
                </div>
                <Link to={localizedTunePath("/listen", locale)}>
                  {text.home.cta}
                  <ArrowRight className="size-4" aria-hidden="true" />
                </Link>
              </div>
              <div className="mt-8 grid gap-3 sm:grid-cols-3">
                {text.home.items.map((item, index) => (
                  <NotebookItem key={item.label} icon={homeIcons[index]} label={item.label} value={item.value} />
                ))}
              </div>
            </Card>
            <Card className="gap-0 overflow-hidden rounded-[1.5rem] border-[#d7c494] bg-[#10284f] p-0 text-white shadow-lg shadow-[#172f5c]/14">
              <div className="p-5">
                <div className="flex items-center gap-2 text-sm font-semibold text-[#b6dd89]">
                  <Sparkles className="size-4" aria-hidden="true" />
                  {text.home.aviTitle}
                </div>
                <ul className="mt-4 flex flex-col gap-3 text-sm leading-6 text-white/74">
                  {text.home.aviBody.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </div>
              <img className="mt-auto h-56 w-full object-cover object-bottom" src={tuneBrandAssets.onboarding} alt="" />
            </Card>
          </section>
        </AppShell>
      </SignedIn>
    </>
  );
}

function NotebookItem({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-[#d7c494] bg-[#fff8df]/72 p-4 text-[#112a55]">
      <div className="flex items-center gap-2 text-sm font-semibold">
        <span className="text-[#5a8f2f]">{icon}</span>
        {label}
      </div>
      <p className="mt-2 text-sm text-[#53617a]">{value}</p>
    </div>
  );
}
