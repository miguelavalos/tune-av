import { useAppsAvLocale } from "@avalsys/apps-av-web";
import { Moon, Sun } from "lucide-react";
import { useEffect, useState } from "react";

const themeKey = "tuneav.web.theme";

export function TuneAccountArea() {
  const locale = useAppsAvLocale();
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const label = theme === "dark" ? themeLabels[locale].light : themeLabels[locale].dark;

  useEffect(() => {
    const stored = window.localStorage.getItem(themeKey);
    const initial = stored === "dark" || stored === "light" ? stored : window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    applyTheme(initial);
    setTheme(initial);
  }, []);

  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    window.localStorage.setItem(themeKey, next);
    applyTheme(next);
    setTheme(next);
  }

  return (
    <div className="flex items-center gap-2">
      <button
        aria-label={label}
        className="inline-flex size-9 items-center justify-center rounded-md border border-border bg-background/70 text-foreground transition hover:bg-accent/20"
        title={label}
        type="button"
        onClick={toggleTheme}
      >
        {theme === "dark" ? <Sun className="size-4" /> : <Moon className="size-4" />}
      </button>
    </div>
  );
}

function applyTheme(theme: "light" | "dark") {
  document.documentElement.classList.toggle("dark", theme === "dark");
}

const themeLabels = {
  ca: { dark: "Mode fosc", light: "Mode clar" },
  de: { dark: "Dunkler Modus", light: "Heller Modus" },
  en: { dark: "Dark mode", light: "Light mode" },
  es: { dark: "Modo oscuro", light: "Modo claro" },
  fr: { dark: "Mode sombre", light: "Mode clair" }
};
