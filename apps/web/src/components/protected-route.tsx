import { AuthLoading, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AuthSkeleton, useAppsAvLocale } from "@avalsys/apps-av-web";
import { useEffect } from "react";
import type { ReactNode } from "react";
import { localizedTunePath } from "@/lib/tune-i18n";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const locale = useAppsAvLocale();
  const homeHref = localizedTunePath("/", locale);

  return (
    <>
      <AuthLoading>
        <AuthSkeleton />
      </AuthLoading>
      <SignedIn>{children}</SignedIn>
      <SignedOut>
        <RedirectHome href={homeHref} />
      </SignedOut>
    </>
  );
}

function RedirectHome({ href }: { href: string }) {
  useEffect(() => {
    window.location.replace(href);
  }, [href]);

  return <AuthSkeleton />;
}
