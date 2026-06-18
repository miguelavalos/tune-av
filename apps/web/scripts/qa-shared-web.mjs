#!/usr/bin/env node

import { runSharedWebSmokeQa } from "../../../../apps-av/web/scripts/shared-web-smoke-qa.mjs";

const result = await runSharedWebSmokeQa({
  baseUrl: process.env.TUNEAV_WEB_QA_BASE_URL ?? "http://localhost:5194",
  expectations: {
    ca: {
      protectedTitle: "La teva escolta queda darrere del compte AV",
      publicCopy: "La teva sala d'escolta esta a punt",
      signInCopy: "Inicia sessio",
      signInRouteCopy: "Inicia sessio per connectar"
    },
    de: {
      protectedTitle: "Dein Hoeren bleibt hinter deinem AV-Konto",
      publicCopy: "Dein Hoerraum ist bereit",
      signInCopy: "Anmelden",
      signInRouteCopy: "Melde dich an"
    },
    en: {
      protectedTitle: "Your listening stays behind your AV account",
      publicCopy: "Your listening room is ready",
      signInCopy: "Sign in",
      signInRouteCopy: "Sign in to connect"
    },
    es: {
      protectedTitle: "Tu escucha queda detras de tu cuenta AV",
      publicCopy: "Tu sala de escucha esta lista",
      signInCopy: "Iniciar sesion",
      signInRouteCopy: "Inicia sesion para conectar"
    },
    fr: {
      protectedTitle: "Votre ecoute reste derriere votre compte AV",
      publicCopy: "Votre salle d'ecoute est prete",
      signInCopy: "Se connecter",
      signInRouteCopy: "Connectez-vous pour relier"
    }
  },
  name: "Tune AV",
  ownRoutePrefixes: ["/", "/listen", "/library", "/music", "/avi", "/account", "/settings", "/sign-in"],
  productIdentity: "Tune AV",
  routes: ["/", "/sign-in", "/listen", "/library", "/music", "/avi", "/account", "/settings"],
  signInRoutes: ["/sign-in"]
});

if (!result.passed) {
  process.exit(1);
}
