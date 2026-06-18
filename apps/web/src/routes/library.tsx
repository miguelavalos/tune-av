import { AccountUserButton } from "@avalsys/account-av-web";
import { AppShell } from "@avalsys/apps-av-web";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Archive, BookOpenCheck, CalendarDays, ListChecks, Radio } from "lucide-react";
import type { ReactNode } from "react";
import { ProtectedRoute } from "@/components/protected-route";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { tuneProductConfig } from "@/lib/tune-config";
import { localizedTunePath, useTuneNavLinks, useTuneShellLabels, useTuneText } from "@/lib/tune-i18n";
import { useAppsAvLocale } from "@avalsys/apps-av-web";

export const Route = createFileRoute("/library")({
  component: LibraryRoute
});

function LibraryRoute() {
  const text = useTuneText();
  const locale = useAppsAvLocale();
  const navLinks = useTuneNavLinks();
  const shellLabels = useTuneShellLabels();
  const hintIcons = [<ListChecks className="size-4" />, <CalendarDays className="size-4" />, <Archive className="size-4" />];

  return (
    <ProtectedRoute>
      <AppShell accountArea={<AccountUserButton />} footerLabels={text.footer} labels={shellLabels} navLinks={navLinks} product={tuneProductConfig}>
        <section className="grid gap-6 lg:grid-cols-[1fr_22rem]">
          <Card className="tune-paper gap-0 rounded-[1.5rem] border-[#d7c494] p-6 py-6 shadow-lg shadow-[#172f5c]/8 sm:p-8 sm:py-8">
            <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-sm font-semibold text-[#5a8f2f]">{text.library.kicker}</p>
                <h1 className="mt-2 text-4xl font-semibold leading-tight text-[#112a55]">{text.library.title}</h1>
                <p className="mt-4 max-w-2xl text-base leading-7 text-[#334766]">
                  {text.library.body}
                </p>
              </div>
              <Button asChild className="rounded-full bg-[#112a55] text-white hover:bg-[#19396f]">
                <Link to={localizedTunePath("/listen", locale)}>
                  <Radio className="size-4" aria-hidden="true" />
                  {text.library.add}
                </Link>
              </Button>
            </div>

            <div className="mt-8 flex flex-wrap gap-2">
              {text.library.filters.map((filter, index) => (
                <button
                  key={filter}
                  className={index === 0 ? "rounded-full bg-[#112a55] px-3 py-2 text-sm font-semibold text-white" : "rounded-full border border-[#d7c494] bg-[#fff8df]/80 px-3 py-2 text-sm font-semibold text-[#334766] transition hover:border-[#8bc342] hover:text-[#112a55]"}
                  type="button"
                >
                  {filter}
                </button>
              ))}
            </div>

            <div className="mt-8 rounded-2xl border border-dashed border-[#c8ad72] bg-[#fff8df]/70 p-8 text-center">
              <BookOpenCheck className="mx-auto size-10 text-[#5a8f2f]" aria-hidden="true" />
              <h2 className="mt-4 text-2xl font-semibold text-[#112a55]">{text.library.emptyTitle}</h2>
              <p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-[#53617a]">
                {text.library.emptyBody}
              </p>
            </div>
          </Card>

          <aside className="grid gap-4">
            {text.library.hints.map((hint, index) => (
              <LibraryHint key={hint.title} icon={hintIcons[index]} title={hint.title} text={hint.text} />
            ))}
          </aside>
        </section>
      </AppShell>
    </ProtectedRoute>
  );
}

function LibraryHint({ icon, text, title }: { icon: ReactNode; text: string; title: string }) {
  return (
    <Card className="gap-2 rounded-[1.25rem] border-[#d7c494] bg-[#fff8df]/88 p-5 py-5 text-[#112a55] shadow-sm shadow-[#172f5c]/6">
      <div className="flex items-center gap-2 text-sm font-semibold">
        <span className="text-[#5a8f2f]">{icon}</span>
        {title}
      </div>
      <p className="text-sm leading-6 text-[#53617a]">{text}</p>
    </Card>
  );
}
