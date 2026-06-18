import { Radio, ShieldCheck, Signal, SlidersHorizontal, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { useTuneText } from "@/lib/tune-i18n";

export function TuneListen() {
  const text = useTuneText();
  const icons = [<SlidersHorizontal className="size-4" />, <Signal className="size-4" />, <Sparkles className="size-4" />];

  return (
    <section className="grid gap-6 lg:grid-cols-[1fr_22rem]">
      <Card className="tune-signal gap-0 overflow-hidden rounded-[1.5rem] border-[#234c58] bg-[#071b22] p-6 py-6 text-white shadow-lg shadow-[#071b22]/18 sm:p-8 sm:py-8">
        <div className="flex items-center gap-2 text-sm font-semibold text-[#29d3c8]">
          <Radio className="size-4" aria-hidden="true" />
          Tune AV
        </div>
        <h1 className="mt-4 max-w-2xl text-4xl font-semibold leading-tight">{text.listen.title}</h1>
        <p className="mt-4 max-w-2xl text-base leading-7 text-white/72">{text.listen.body}</p>
        <div className="mt-8 grid gap-3 sm:grid-cols-3">
          {text.listen.panels.map((panel, index) => (
            <ListenPanel key={panel.title} icon={icons[index]} title={panel.title} body={panel.body} />
          ))}
        </div>
      </Card>

      <Card className="gap-4 rounded-[1.5rem] border-[#c8ad72] bg-[#fff8df] p-6 py-6 text-[#102a33] shadow-sm shadow-[#071b22]/8">
        <div className="flex size-12 items-center justify-center rounded-2xl bg-[#d8f6ed] text-[#087f79]">
          <ShieldCheck className="size-6" aria-hidden="true" />
        </div>
        <div>
          <h2 className="text-2xl font-semibold">{text.listen.cta}</h2>
          <p className="mt-3 text-sm leading-6 text-[#445b62]">{text.listen.accountBody}</p>
        </div>
      </Card>
    </section>
  );
}

function ListenPanel({ body, icon, title }: { body: string; icon: ReactNode; title: string }) {
  return (
    <div className="min-h-40 rounded-2xl border border-white/12 bg-white/8 p-4 text-white shadow-sm shadow-black/10">
      <div className="flex items-center gap-2 text-sm font-semibold text-[#b9f4d9]">
        {icon}
        {title}
      </div>
      <p className="mt-3 text-sm leading-6 text-white/70">{body}</p>
    </div>
  );
}
