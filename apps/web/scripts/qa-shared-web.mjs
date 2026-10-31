#!/usr/bin/env node

import { runSharedWebSmokeQa } from "../../../../apps-av/web/scripts/shared-web-smoke-qa.mjs";

const result = await runSharedWebSmokeQa({
  baseUrl: process.env.TUNEAV_WEB_QA_BASE_URL ?? "http://localhost:5194",
  guestCopyPattern: /\b(guest-mode|invitado|invitada|convidat|convidada|gastmodus)\b/i,
  expectations: {
    ca: {
      protectedTitle: "Radio tranquil.la, compte connectat",
      publicCopy: "Radio tranquil.la, compte connectat",
      signInCopy: "Inicia sessio",
      signInRouteCopy: "Inicia sessio per gestionar"
    },
    de: {
      protectedTitle: "Ruhiges Radio, verbundenes Konto",
      publicCopy: "Ruhiges Radio, verbundenes Konto",
      signInCopy: "Anmelden",
      signInRouteCopy: "Melde dich an"
    },
    en: {
      protectedTitle: "Radio calm, account connected",
      publicCopy: "Radio calm, account connected",
      signInCopy: "Sign in",
      signInRouteCopy: "Sign in to manage"
    },
    es: {
      protectedTitle: "Radio tranquila, cuenta conectada",
      publicCopy: "Radio tranquila, cuenta conectada",
      signInCopy: "Iniciar sesion",
      signInRouteCopy: "Inicia sesion para gestionar"
    },
    fr: {
      protectedTitle: "Radio calme, compte connecte",
      publicCopy: "Radio calme, compte connecte",
      signInCopy: "Se connecter",
      signInRouteCopy: "Connectez-vous pour gerer"
    }
  },
  name: "Tune AV",
  ownRoutePrefixes: ["/", "/account", "/settings", "/sign-in"],
  productIdentity: "Tune AV",
  routes: ["/", "/sign-in", "/account", "/settings"],
  signInRoutes: ["/sign-in"]
});

if (!result.passed) {
  process.exit(1);
}
