import { AuthLoading, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AuthSkeleton, AvAppFooter, useAppsAvLocale } from "@avalsys/apps-av-web";
import type { ReactNode } from "react";
import { tuneBrandAssets, tuneProductConfig } from "@/lib/tune-config";
import { useTuneText } from "@/lib/tune-i18n";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const signInHref = locale === "en" ? "/sign-in" : `/sign-in?lang=${locale}`;

  return (
    <>
      <AuthLoading>
        <AuthSkeleton />
      </AuthLoading>
      <SignedIn>{children}</SignedIn>
      <SignedOut>
        <div className="tune-paper flex min-h-screen flex-col">
          <main className="flex flex-1 items-center justify-center px-6 py-10 text-center">
            <div className="relative max-w-3xl overflow-hidden rounded-[1.75rem] border border-[#d7c494] bg-[#fff8df]/88 p-8 pb-28 shadow-2xl shadow-[#172f5c]/12 sm:p-10 sm:pb-10">
              <img className="mx-auto h-auto w-64" src={tuneBrandAssets.logo} alt="Tune AV" />
              <h1 className="mt-8 text-4xl font-semibold text-[#112a55]">{text.protected.title}</h1>
              <p className="mx-auto mt-4 max-w-xl text-base leading-7 text-[#334766]">
                {text.protected.body}
              </p>
              <a
                className="mt-8 inline-flex h-11 items-center justify-center rounded-full bg-[#112a55] px-5 text-sm font-semibold text-white shadow-lg shadow-[#112a55]/18 transition hover:bg-[#19396f]"
                href={signInHref}
              >
                {text.protected.cta}
              </a>
              <img className="absolute bottom-0 right-5 w-28 translate-y-6 sm:hidden" src={tuneBrandAssets.aviFullBody} alt="Avi" />
            </div>
          </main>
          <AvAppFooter className="border-transparent bg-transparent" labels={text.footer} product={tuneProductConfig} />
        </div>
      </SignedOut>
    </>
  );
}
