import { SignedIn, SignedOut } from "@avalsys/account-av-web";
import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, Library, Radio, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TuneAppShell } from "@/components/tune-app-shell";
import { TuneLoginPage } from "@/components/tune-login-page";
import { isTuneWebAppComingSoon, tuneBrandAssets } from "@/lib/tune-config";
import { localizedTunePath, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/")({
  component: IndexRoute
});

function IndexRoute() {
  if (isTuneWebAppComingSoon()) {
    return <TuneLoginPage comingSoon />;
  }

  const locale = useAppsAvLocale();
  const text = useTuneText();

  return (
    <>
      <SignedOut>
        <TuneLoginPage />
      </SignedOut>
      <SignedIn>
        <TuneAppShell>
          <HomeContent locale={locale} text={text} />
        </TuneAppShell>
      </SignedIn>
    </>
  );
}

function HomeContent({ locale, text }: { locale: ReturnType<typeof useAppsAvLocale>; text: ReturnType<typeof useTuneText> }) {
  return (
    <>
      <section className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <Card className="tune-public-hero tune-paper gap-0 overflow-hidden rounded-lg border-[#d7c494] p-0 shadow-lg shadow-[#172f5c]/8">
          <img className="tune-public-hero-image" src={tuneBrandAssets.guestHomeDial} alt="" />
          <div className="tune-public-hero-overlay" />
          <div className="relative z-10 p-6 sm:p-8">
            <img className="h-auto w-48 max-w-full sm:w-64" src={tuneBrandAssets.logo} alt="Tune AV" />
            <h1 className="mt-8 max-w-3xl text-4xl font-semibold leading-tight text-[#112a55]">{text.home.title}</h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-[#334766]">{text.home.body}</p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Button asChild className="rounded-lg bg-[#112a55] text-white hover:bg-[#19396f]">
                <Link to={localizedTunePath("/listen", locale)}>{text.home.cta} <ArrowRight className="size-4" /></Link>
              </Button>
            </div>
            <div className="mt-8 grid gap-3 sm:grid-cols-3">
              <Feature icon={<Radio className="size-4" />} title={text.home.items[0]?.label ?? "Stations"} body={text.home.items[0]?.value ?? ""} />
              <Feature icon={<Library className="size-4" />} title={text.home.items[1]?.label ?? "Library"} body={text.home.items[1]?.value ?? ""} />
              <Feature icon={<Sparkles className="size-4" />} title={text.home.items[2]?.label ?? "Avi"} body={text.home.items[2]?.value ?? ""} />
            </div>
          </div>
        </Card>
        <Card className="gap-0 overflow-hidden rounded-lg border-[#d7c494] bg-[#10284f] p-0 text-white shadow-lg shadow-[#172f5c]/14">
          <img className="h-72 w-full object-cover object-bottom" src={tuneBrandAssets.guestHomeStation} alt="" />
          <div className="p-5">
            <p className="text-sm font-semibold text-[#b6dd89]">{text.listen.cta}</p>
            <p className="mt-2 text-sm leading-6 text-white/74">{text.protected.body}</p>
          </div>
        </Card>
      </section>
      <section className="mt-6 grid gap-6 lg:grid-cols-[0.95fr_1.05fr]">
        <div className="rounded-lg border border-[#d7c494] bg-[#fff8df]/80 p-6 shadow-lg shadow-[#172f5c]/8 sm:p-8">
          <p className="max-w-xl text-sm leading-6 text-[#334766]">{text.login.intro}</p>
          <h2 className="mt-8 max-w-lg text-4xl font-semibold leading-tight text-[#112a55] sm:text-5xl">{text.login.heroTitle}</h2>
        </div>
        <div className="tune-public-scene overflow-hidden rounded-lg border border-[#d7c494] bg-[#092832] p-5 shadow-lg shadow-[#172f5c]/14">
          <img className="tune-public-scene-image" src={tuneBrandAssets.guestHomeAvi} alt="" />
          <div className="tune-public-scene-card">
            <p className="font-serif text-3xl leading-tight text-[#112a55]">{text.login.mapTitle}</p>
            <p className="mt-4 text-sm leading-6 text-[#3d4e68]">{text.login.mapBody}</p>
          </div>
        </div>
      </section>
    </>
  );
}

function Feature({ body, icon, title }: { body: string; icon: ReactNode; title: string }) {
  return (
    <div className="rounded-lg border border-[#d7c494] bg-[#fff8df]/72 p-4 text-[#112a55]">
      <div className="flex items-center gap-2 text-sm font-semibold"><span className="text-[#087f79]">{icon}</span>{title}</div>
      <p className="mt-2 text-sm leading-6 text-[#53617a]">{body}</p>
    </div>
  );
}
