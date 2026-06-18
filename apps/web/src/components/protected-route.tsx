import { AuthLoading, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AuthSkeleton, ProtectedAppGate, useAppsAvLocale } from "@avalsys/apps-av-web";
import type { ReactNode } from "react";
import { getLocalizedTuneProductConfig, tuneBrandAssets } from "@/lib/tune-config";
import { useTuneText } from "@/lib/tune-i18n";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const signInHref = locale === "en" ? "/sign-in" : `/sign-in?lang=${locale}`;
  const product = getLocalizedTuneProductConfig(locale);

  return (
    <>
      <AuthLoading>
        <AuthSkeleton />
      </AuthLoading>
      <SignedIn>{children}</SignedIn>
      <SignedOut>
        <ProtectedAppGate
          body={text.protected.body}
          cta={text.protected.cta}
          footerLabels={text.footer}
          logoAlt="Tune AV"
          logoSrc={tuneBrandAssets.logo}
          mascotAlt="Avi"
          mascotSrc={tuneBrandAssets.aviFullBody}
          product={product}
          signInHref={signInHref}
          title={text.protected.title}
          wrapperClassName="tune-paper"
        />
      </SignedOut>
    </>
  );
}
