import { Link } from "@tanstack/react-router";
import { ArrowRight, BookOpenCheck, ListChecks, Radio, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { AvAppFooter, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { getLocalizedTuneProductConfig, tuneBrandAssets } from "@/lib/tune-config";
import { localizedTunePath, useTuneText } from "@/lib/tune-i18n";

export function TuneLoginPage({ comingSoon = false, compact = false }: { comingSoon?: boolean; compact?: boolean }) {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const product = getLocalizedTuneProductConfig(locale);
  const guestHomeScenes = [
    {
      alt: "",
      className: "tune-guest-scene-card tune-guest-scene-card--left",
      src: tuneBrandAssets.guestHomeStation
    },
    {
      alt: "",
      className: "tune-guest-scene-card tune-guest-scene-card--right",
      src: tuneBrandAssets.guestHomeAvi
    }
  ];

  if (compact) {
    return (
      <div className="overflow-hidden">
        <LoginContent comingSoon={comingSoon} compact locale={locale} text={text} />
      </div>
    );
  }

  return (
    <div className="tune-paper min-h-screen overflow-hidden px-4 pt-4 sm:px-6">
      <main className="tune-guest-shell mx-auto min-h-[calc(100vh-2rem)] w-full max-w-7xl overflow-hidden rounded-[1.75rem] border border-[#d7c494] bg-[#fff6da]/88 shadow-2xl shadow-[#172f5c]/16 backdrop-blur">
        <img className="tune-guest-backdrop" src={tuneBrandAssets.guestHomeDial} alt="" />
        <div className="tune-guest-overlay" />

        <section className="relative z-10 grid min-h-[calc(100vh-2rem)] min-w-0 gap-8 p-4 sm:p-8 lg:grid-cols-[0.84fr_1.16fr] lg:p-10 xl:p-12">
          <div className="tune-guest-copy flex min-w-0 flex-col justify-between gap-10 rounded-[1.35rem] border border-[#d7c494]/82 bg-[#fff8df]/86 p-5 shadow-xl shadow-[#172f5c]/12 backdrop-blur-md sm:p-8 lg:p-10">
            <LoginCopy comingSoon={comingSoon} locale={locale} text={text} />
          </div>

          <div className="tune-guest-gallery relative min-h-[32rem] min-w-0 overflow-hidden rounded-[1.35rem] border border-white/22 bg-[#092832]/35 shadow-2xl shadow-[#172f5c]/20">
            {guestHomeScenes.map((scene) => (
              <img key={scene.src} className={scene.className} src={scene.src} alt={scene.alt} />
            ))}
            <Card className="tune-guest-note relative z-10 mt-auto max-w-sm gap-2 rounded-2xl border-[#d4bf88] bg-[#fff8df]/90 p-5 py-5 text-[#112a55] shadow-xl shadow-[#112a55]/14 backdrop-blur-md">
              <p className="flex items-center gap-2 text-sm font-semibold">
                <ListChecks className="size-4 text-[#087f79]" aria-hidden="true" />
                {text.login.cardTitle}
              </p>
              <p className="mt-2 text-sm leading-6 text-[#47566f]">
                {text.login.cardBody}
              </p>
            </Card>
            <div className="tune-guest-caption relative z-10 max-w-sm rounded-2xl border border-[#d7c494]/82 bg-[#fff8df]/86 p-5 text-[#112a55] shadow-xl shadow-[#112a55]/12 backdrop-blur-md">
              <p className="font-serif text-3xl leading-tight">{text.login.mapTitle}</p>
              <p className="mt-4 text-sm leading-6 text-[#3d4e68]">{text.login.mapBody}</p>
            </div>
          </div>
        </section>
      </main>
      <AvAppFooter className="mt-4 border-transparent bg-transparent px-0 pb-4 pt-2" labels={text.footer} product={product} />
    </div>
  );
}

function LoginContent({ comingSoon, compact, locale, text }: { comingSoon: boolean; compact: boolean; locale: ReturnType<typeof useAppsAvLocale>; text: ReturnType<typeof useTuneText> }) {
  return (
    <main className={compact ? "mx-auto grid max-w-6xl overflow-hidden rounded-lg border border-[#d7c494] bg-[#fff6da]/88 shadow-lg shadow-[#172f5c]/10 md:grid-cols-[0.95fr_1.05fr]" : "mx-auto grid min-h-[calc(100vh-6rem)] max-w-6xl overflow-hidden rounded-[1.75rem] border border-[#d7c494] bg-[#fff6da]/88 shadow-2xl shadow-[#172f5c]/16 backdrop-blur md:grid-cols-[0.95fr_1.05fr]"}>
      <section className="flex flex-col justify-between gap-10 p-7 sm:p-10 lg:p-12">
        <LoginCopy comingSoon={comingSoon} locale={locale} text={text} />
      </section>

      <section className="relative min-h-[32rem] overflow-hidden bg-[#10284f] p-6 text-white lg:min-h-full">
        <div className="absolute inset-0 bg-[linear-gradient(135deg,rgba(41,211,200,0.18)_0%,rgba(41,211,200,0)_42%),linear-gradient(160deg,#092832_0%,#071b22_50%,#0f2b28_100%)]" />
        <div className="relative flex h-full flex-col justify-between gap-6 overflow-hidden rounded-[1.4rem] border border-white/14 bg-[#fff0c7] p-5 text-[#112a55] shadow-2xl shadow-black/24">
          <img className="absolute inset-y-0 right-0 h-full w-[58%] object-cover object-bottom opacity-20 sm:w-[56%] md:opacity-95" src={tuneBrandAssets.onboarding} alt="" />
          <div className="relative max-w-xs">
            <p className="font-serif text-3xl leading-tight text-[#112a55]">{text.login.mapTitle}</p>
            <p className="mt-4 text-sm leading-6 text-[#3d4e68]">
              {text.login.mapBody}
            </p>
          </div>
          <Card className="relative mt-auto max-w-sm gap-2 rounded-2xl border-[#d4bf88] bg-[#fff8df]/88 p-5 py-5 text-[#112a55] shadow-xl shadow-[#112a55]/12">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <ListChecks className="size-4 text-[#087f79]" aria-hidden="true" />
              {text.login.cardTitle}
            </p>
            <p className="mt-2 text-sm leading-6 text-[#47566f]">
              {text.login.cardBody}
            </p>
          </Card>
          <img
            className="absolute bottom-0 right-4 hidden w-44 translate-y-8 drop-shadow-2xl md:block sm:right-8 sm:w-52 lg:w-60"
            src={tuneBrandAssets.aviLoginSheetPeek}
            alt="Avi"
          />
        </div>
      </section>
    </main>
  );
}

function LoginCopy({ comingSoon, locale, text }: { comingSoon: boolean; locale: ReturnType<typeof useAppsAvLocale>; text: ReturnType<typeof useTuneText> }) {
  return (
    <>
      <div>
        <img className="h-auto w-48 sm:w-64" src={tuneBrandAssets.logo} alt="Tune AV" />
        <p className="mt-4 max-w-sm text-sm leading-6 text-[#314568]">
          {text.login.intro}
        </p>
      </div>

      <div className="max-w-xl">
        <h1 className="tune-guest-title max-w-full text-[2.35rem] font-semibold leading-[1.03] text-[#112a55] sm:text-5xl xl:text-6xl">
          {text.login.heroTitle}
        </h1>
        <p className="tune-guest-body mt-6 text-base leading-7 text-[#334766]">
          {text.login.heroBody}
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          {comingSoon ? (
            <Button disabled className="h-12 rounded-full bg-[#112a55] px-5 text-white shadow-lg shadow-[#112a55]/18 disabled:opacity-100">
              {comingSoonLabel(locale)}
            </Button>
          ) : (
            <Button asChild className="h-12 rounded-full bg-[#112a55] px-5 text-white shadow-lg shadow-[#112a55]/18 hover:bg-[#19396f]">
              <Link to={localizedTunePath("/sign-in", locale)}>
                {text.login.cta}
                <ArrowRight className="size-4" aria-hidden="true" />
              </Link>
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-3 text-sm text-[#334766] sm:grid-cols-3 lg:grid-cols-1 xl:grid-cols-3">
        <LoginMetric icon={<Radio className="size-4" aria-hidden="true" />} label={text.login.listen} />
        <LoginMetric icon={<Sparkles className="size-4" aria-hidden="true" />} label={text.login.aviGuidance} />
        <LoginMetric icon={<BookOpenCheck className="size-4" aria-hidden="true" />} label={text.login.notebook} />
      </div>
    </>
  );
}

function comingSoonLabel(locale: ReturnType<typeof useAppsAvLocale>) {
  return ({ ca: "Properament", de: "Demnächst", en: "Coming soon", es: "Próximamente", fr: "Prochainement" } as const)[locale] ?? "Coming soon";
}

function LoginMetric({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <div className="flex min-h-12 items-center gap-2 rounded-xl border border-[#d7c494] bg-[#fff8df]/72 px-3 shadow-sm shadow-[#172f5c]/5">
      <span className="text-[#087f79]">{icon}</span>
      <span className="font-medium text-[#334766]">{label}</span>
    </div>
  );
}
