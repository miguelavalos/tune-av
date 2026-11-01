import { AuthLoading, SignedIn, SignedOut } from "@avalsys/account-av-web";
import { AuthSkeleton } from "@avalsys/apps-av-web";
import type { ReactNode } from "react";
import { TuneLoginPage } from "@/components/tune-login-page";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  return (
    <>
      <AuthLoading>
        <AuthSkeleton />
      </AuthLoading>
      <SignedIn>{children}</SignedIn>
      <SignedOut>
        <TuneLoginPage />
      </SignedOut>
    </>
  );
}
