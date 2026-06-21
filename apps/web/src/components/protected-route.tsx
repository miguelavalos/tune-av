import { AuthLoading, SignedIn, SignedOut, useAccountSession } from "@avalsys/account-av-web";
import { AuthSkeleton, useAppsAvLocale } from "@avalsys/apps-av-web";
import { useEffect } from "react";
import type { ReactNode } from "react";
import { localizedTunePath } from "@/lib/tune-i18n";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const locale = useAppsAvLocale();
  const homeHref = localizedTunePath("/", locale);
  const session = useAccountSession();

  useEffect(() => {
    if (session.isLoaded && !session.isSignedIn && window.location.pathname !== "/sign-in") {
      window.location.replace(homeHref);
    }
  }, [homeHref, session.isLoaded, session.isSignedIn]);

  return (
    <>
      <AuthLoading>
        <AuthSkeleton />
      </AuthLoading>
      <SignedIn>{children}</SignedIn>
      <SignedOut>
        <AuthSkeleton />
      </SignedOut>
    </>
  );
}
