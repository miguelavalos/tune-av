import { AccountSignIn, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AvAppFooter, useAppsAvLocale } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { getLocalizedTuneProductConfig, tuneBrandAssets } from "@/lib/tune-config";
import { localizedTunePath, useTuneText } from "@/lib/tune-i18n";

export const Route = createFileRoute("/sign-in")({
  component: SignInRoute
});

function SignInRoute() {
  const locale = useAppsAvLocale();
  const text = useTuneText();
  const product = getLocalizedTuneProductConfig(locale);

  return (
    <div className="tune-paper flex min-h-screen flex-col bg-[#fff3cf]">
      <main className="grid flex-1 lg:grid-cols-[0.92fr_1.08fr]">
        <section className="relative hidden min-h-screen overflow-hidden bg-[#10284f] p-10 text-white lg:flex lg:flex-col lg:justify-between">
          <div className="absolute inset-0 bg-[linear-gradient(135deg,rgba(41,211,200,0.18)_0%,rgba(41,211,200,0)_42%),linear-gradient(160deg,#092832_0%,#071b22_54%,#0f2b28_100%)]" />
          <Link className="relative inline-flex items-center gap-2 text-sm font-medium text-white/76 transition hover:text-white" to={localizedTunePath("/", locale)}>
            <ArrowLeft className="size-4" aria-hidden="true" />
            Tune AV
          </Link>
          <div className="relative max-w-md">
            <img className="mb-10 h-auto w-64 brightness-0 invert" src={tuneBrandAssets.logo} alt="Tune AV" />
            <h1 className="text-4xl font-semibold leading-tight">{text.signIn.title}</h1>
            <p className="mt-5 text-base leading-7 text-white/70">
              {text.signIn.body}
            </p>
          </div>
          <div className="relative overflow-hidden rounded-[1.5rem] border border-white/12 bg-[#fff0c7] p-5 pb-0 text-[#112a55] shadow-2xl shadow-black/22">
            <div className="relative z-10 max-w-xs pb-28">
              <p className="text-sm font-semibold text-[#5a8f2f]">Avi</p>
              <p className="mt-2 font-serif text-3xl leading-tight">{text.signIn.aviPanelBody}</p>
            </div>
            <img
              className="absolute bottom-0 right-6 w-52 translate-y-8 drop-shadow-2xl"
              src={tuneBrandAssets.aviLoginSheetPeek}
              alt="Avi"
            />
          </div>
        </section>

        <section className="flex min-h-screen items-center justify-center px-5 py-10">
          <div className="w-full max-w-md">
            <Link className="mb-8 inline-flex items-center gap-2 text-sm font-medium text-[#334766] transition hover:text-[#112a55] lg:hidden" to={localizedTunePath("/", locale)}>
              <ArrowLeft className="size-4" aria-hidden="true" />
              Tune AV
            </Link>
            <img className="mb-8 h-auto w-64 lg:hidden" src={tuneBrandAssets.logo} alt="Tune AV" />
            <div className="mb-5 flex items-center gap-3 rounded-2xl border border-[#d7c494] bg-[#fff8df]/82 p-3 shadow-sm shadow-[#172f5c]/8 lg:hidden">
              <img className="h-16 w-16 object-contain" src={tuneBrandAssets.aviFullBody} alt="Avi" />
              <p className="text-sm font-medium leading-5 text-[#334766]">{text.signIn.aviPanelBody}</p>
            </div>
            <SignedIn>
              <div className="rounded-2xl border border-[#d7c494] bg-[#fff8df] p-6 text-center shadow-lg shadow-[#172f5c]/10">
                <p className="text-sm font-semibold text-[#112a55]">{text.signIn.signedIn}</p>
                <Link className="mt-4 inline-flex h-10 items-center justify-center rounded-full bg-[#112a55] px-4 text-sm font-semibold text-white" to={localizedTunePath("/", locale)}>
                  {text.signIn.continue}
                </Link>
              </div>
            </SignedIn>
            <SignedOut>
              <AccountSignIn fallbackRedirectUrl={localizedTunePath("/", locale)} path="/sign-in" />
            </SignedOut>
          </div>
        </section>
      </main>
      <AvAppFooter labels={text.footer} product={product} />
    </div>
  );
}
