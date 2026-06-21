import { AccountSignOutButton, useAccountUser } from "@avalsys/account-av-web";
import { AccountSafetySection, CloudSyncSection, PlanFeatureSection, SettingsButton, SettingsInfoRow, SettingsProfileScaffold, SettingsSectionCard, useAppsAvLocale } from "@avalsys/apps-av-web";
import { createFileRoute } from "@tanstack/react-router";
import { Mail, Sparkles, UserCircle } from "lucide-react";
import { ProtectedRoute } from "@/components/protected-route";
import { TuneAppShell } from "@/components/tune-app-shell";
import { tuneProductConfig } from "@/lib/tune-config";
import { tuneProfileLabels } from "@/lib/tune-profile-labels";
import { useTune } from "@/lib/tune-store";
import { localizedExternalUrl } from "@/lib/tune-url";

export const Route = createFileRoute("/account")({
  component: AccountRoute
});

function AccountRoute() {
  const account = useAccountUser();
  const locale = useAppsAvLocale();
  const tune = useTune();
  const labels = tuneProfileLabels[locale];
  const isPro = tune.access.accessMode === "signedInPro" || tune.access.planTier === "pro";
  const canUseCloudSync = tune.access.capabilities.canUseCloudSync === true;
  const email = account.data?.email ?? null;
  const displayName = account.data?.displayName ?? email ?? labels.account.signedIn;

  return (
    <ProtectedRoute>
      <TuneAppShell>
        <SettingsProfileScaffold title={labels.accountTitle} subtitle={labels.accountSubtitle} heroClassName="tune-paper">
          <SettingsSectionCard title={labels.account.title} subtitle={email ?? labels.account.connected}>
            <SettingsInfoRow icon={<UserCircle className="size-5" />} title={labels.account.sessionTitle} detail={displayName} />
            {email ? <SettingsInfoRow icon={<Mail className="size-5" />} title={labels.account.emailTitle} detail={email} /> : null}
            <SettingsInfoRow icon={<Sparkles className="size-5" />} title={labels.account.planTitle} detail={isPro ? labels.account.planPro : labels.account.planFree} />
            <AccountSignOutButton>
              <SettingsButton>{labels.account.signOut}</SettingsButton>
            </AccountSignOutButton>
          </SettingsSectionCard>

          <PlanFeatureSection isPro={isPro} labels={labels.pro} manageHref={localizedExternalUrl(tuneProductConfig.links.suite?.href, locale)} />

          {canUseCloudSync ? (
            <CloudSyncSection labels={labels.sync} syncState={tune.syncStatus} onRetry={() => void tune.synchronizeLibrary()} />
          ) : null}

          <AccountSafetySection labels={labels.safety} deleteHref={localizedExternalUrl(tuneProductConfig.links.deleteAccount?.href, locale)} />
        </SettingsProfileScaffold>
      </TuneAppShell>
    </ProtectedRoute>
  );
}
