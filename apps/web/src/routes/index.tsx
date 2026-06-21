import { SignedIn, SignedOut } from "@avalsys/account-av-web";
import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, Library, Radio, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
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
      <section className="tune-public-hero tune-paper overflow-hidden rounded-[1.5rem] border border-[#d7c494] shadow-xl shadow-[#172f5c]/10">
        <img className="tune-public-hero-image" src={tuneBrandAssets.guestHomeDial} alt="" />
        <div className="tune-public-hero-overlay" />
        <div className="relative z-10 flex min-h-[31rem] flex-col justify-between gap-8 p-6 sm:p-8 lg:w-[58%]">
          <div>
            <img className="h-auto w-48 max-w-full sm:w-64" src={tuneBrandAssets.logo} alt="Tune AV" />
            <h1 className="mt-8 max-w-3xl text-5xl font-semibold leading-tight text-[#112a55] sm:text-6xl">{text.home.title}</h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-[#334766]">{text.home.body}</p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Button asChild className="h-11 rounded-full bg-[#112a55] px-5 text-white hover:bg-[#19396f]">
                <Link to={localizedTunePath("/listen", locale)}>{text.home.cta} <ArrowRight className="size-4" /></Link>
              </Button>
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <Feature icon={<Radio className="size-4" />} title={text.home.items[0]?.label ?? "Stations"} body={text.home.items[0]?.value ?? ""} />
            <Feature icon={<Library className="size-4" />} title={text.home.items[1]?.label ?? "Library"} body={text.home.items[1]?.value ?? ""} />
            <Feature icon={<Sparkles className="size-4" />} title={text.home.items[2]?.label ?? "Avi"} body={text.home.items[2]?.value ?? ""} />
          </div>
        </div>
        <div className="absolute bottom-5 right-5 z-10 hidden max-w-sm rounded-[1rem] border border-[#d7c494]/80 bg-[#fff8df]/90 p-5 shadow-xl shadow-[#172f5c]/18 backdrop-blur lg:block">
          <p className="text-sm font-semibold text-[#087f79]">{text.listen.cta}</p>
          <p className="mt-2 text-sm leading-6 text-[#3d4e68]">{text.protected.body}</p>
        </div>
      </section>
      <section className="mt-6 grid gap-5 lg:grid-cols-[0.92fr_1.08fr]">
        <div className="tune-paper rounded-[1.25rem] border border-[#d7c494] p-6 shadow-lg shadow-[#172f5c]/8 sm:p-8">
          <p className="max-w-xl text-sm leading-6 text-[#334766]">{text.login.intro}</p>
          <h2 className="mt-8 max-w-lg text-4xl font-semibold leading-tight text-[#112a55] sm:text-5xl">{text.login.heroTitle}</h2>
        </div>
        <div className="tune-public-scene overflow-hidden rounded-[1.25rem] border border-[#d7c494] bg-[#092832] shadow-lg shadow-[#172f5c]/14">
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
    <div className="rounded-[1rem] border border-[#d7c494] bg-[#fff8df]/62 p-4 text-[#112a55] backdrop-blur">
      <div className="flex items-center gap-2 text-sm font-semibold"><span className="text-[#087f79]">{icon}</span>{title}</div>
      <p className="mt-2 text-sm leading-6 text-[#53617a]">{body}</p>
    </div>
  );
}
