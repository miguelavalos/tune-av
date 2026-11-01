import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { tuneAppStore } from "@/lib/tune-config";
import { useTuneText } from "@/lib/tune-i18n";

export function TuneAppStoreBadge({ className = "" }: { className?: string }) {
  const locale = useAppsAvLocale();
  const text = useTuneText();

  return (
    <a className={`inline-flex ${className}`.trim()} href={tuneAppStore.url} rel="noreferrer" target="_blank">
      <img alt={text.home.appStoreBadgeAlt} className="h-[50px] w-auto" height={50} src={tuneAppStore.badges[locale]} width={150} />
    </a>
  );
}
