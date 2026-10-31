import { SignedIn, SignedOut, useAccountAppAccess } from "@avalsys/account-av-web";
import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, Settings, Sparkles, UserCircle } from "lucide-react";
import type { ReactNode } from "react";
import { TuneAppShell } from "@/components/tune-app-shell";
import { TuneAppStoreBadge } from "@/components/tune-app-store-link";
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

  return (
    <>
      <SignedOut>
        <TuneLoginPage />
      </SignedOut>
      <SignedIn>
        <TuneAppShell>
          <HomeContent />
        </TuneAppShell>
      </SignedIn>
    </>
  );
}

function HomeContent() {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const access = useAccountAppAccess("tuneav");
  const planLabel = !access.data ? text.home.planLoading : access.data.planTier === "pro" || access.data.accessMode === "signedInPro" ? text.home.planPro : text.home.planFree;

  return (
    <>
      <section className="tune-public-hero tune-paper overflow-hidden rounded-[1.5rem] border border-[#d7c494] shadow-xl shadow-[#172f5c]/10">
        <img className="tune-public-hero-image" src={tuneBrandAssets.guestHomeDial} alt="" />
        <div className="tune-public-hero-overlay" />
        <div className="relative z-10 flex flex-col gap-8 p-6 sm:p-8 lg:w-[62%]">
          <div>
            <img className="h-auto w-48 max-w-full sm:w-64" src={tuneBrandAssets.logo} alt="Tune AV" />
            <h1 className="mt-8 max-w-3xl text-4xl font-semibold leading-tight text-[#112a55] sm:text-5xl">{text.home.title}</h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-[#334766]">{text.home.body}</p>
          </div>
          <div className="rounded-[1rem] border border-[#d7c494] bg-[#fff8df]/80 p-5 text-[#112a55] backdrop-blur">
            <p className="text-sm font-semibold">{text.home.getApp}</p>
            <p className="mt-2 text-sm leading-6 text-[#53617a]">{text.home.getAppBody}</p>
            <TuneAppStoreBadge className="mt-4" />
          </div>
        </div>
      </section>
      <section className="mt-6 grid gap-4 sm:grid-cols-3">
        <HomeCard icon={<Sparkles className="size-4" />} title={text.home.planTitle} body={planLabel} />
        <HomeLink href={localizedTunePath("/account", locale)} icon={<UserCircle className="size-4" />} title={text.home.accountCta} body={text.home.accountBody} />
        <HomeLink href={localizedTunePath("/settings", locale)} icon={<Settings className="size-4" />} title={text.home.settingsCta} body={text.home.settingsBody} />
      </section>
    </>
  );
}

function HomeCard({ body, icon, title }: { body: string; icon: ReactNode; title: string }) {
  return (
    <div className="tune-paper rounded-[1rem] border border-[#d7c494] p-5 text-[#112a55] shadow-lg shadow-[#172f5c]/8">
      <div className="flex items-center gap-2 text-sm font-semibold"><span className="text-[#087f79]">{icon}</span>{title}</div>
      <p className="mt-2 text-sm leading-6 text-[#53617a]">{body}</p>
    </div>
  );
}

function HomeLink({ body, href, icon, title }: { body: string; href: string; icon: ReactNode; title: string }) {
  return (
    <Link className="tune-paper group flex flex-col rounded-[1rem] border border-[#d7c494] p-5 text-[#112a55] shadow-lg shadow-[#172f5c]/8 transition hover:border-[#112a55]" to={href}>
      <div className="flex items-center justify-between gap-2 text-sm font-semibold">
        <span className="flex items-center gap-2"><span className="text-[#087f79]">{icon}</span>{title}</span>
        <ArrowRight className="size-4 text-[#53617a] transition group-hover:text-[#112a55]" aria-hidden="true" />
      </div>
      <p className="mt-2 text-sm leading-6 text-[#53617a]">{body}</p>
    </Link>
  );
}
