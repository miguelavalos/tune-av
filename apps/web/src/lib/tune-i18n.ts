import { useAppsAvLocale, type AppsAvLocale, type AppsAvProductLink } from "@avalsys/apps-av-web";
import { caES } from "@clerk/localizations/ca-ES";
import { deDE } from "@clerk/localizations/de-DE";
import { enUS } from "@clerk/localizations/en-US";
import { esES } from "@clerk/localizations/es-ES";
import { frFR } from "@clerk/localizations/fr-FR";

const en = {
  account: {
    signInTitle: "Sign in to Tune AV",
    signInSubtitle: "Welcome back. Sign in to manage your Tune AV account, plan, and settings."
  },
  config: {
    body: "Run the web app through the Varlock wrapper so Account AV configuration is available. The public home is informational; account routes require login.",
    eyebrow: "Configuration required",
    title: "Tune AV Web needs Clerk configuration."
  },
  footer: {
    deleteAccount: "Delete account",
    language: "Language",
    privacy: "Privacy",
    support: "Support",
    terms: "Terms"
  },
  home: {
    accountBody: "Email, plan, sign out, and account deletion.",
    accountCta: "Account",
    appStoreBadgeAlt: "Download Tune AV on the App Store",
    body: "Tune AV lives in the iOS app: live radio, My Songs, and Avi guidance for iPhone and iPad. This page keeps your account, plan, and settings reachable from any browser.",
    getApp: "Get the app",
    getAppBody: "Download Tune AV for iPhone and iPad on the App Store. Tune AV Pro is purchased inside the app.",
    planFree: "Tune AV Free",
    planLoading: "Checking your plan...",
    planPro: "Tune AV Pro",
    planTitle: "Your plan",
    settingsBody: "Language, appearance, help, and legal links.",
    settingsCta: "Settings",
    title: "Your listening room is ready."
  },
  login: {
    appStoreNote: "Tune AV for iPhone and iPad is on the App Store. Sign in here to manage your account.",
    aviGuidance: "Avi guidance",
    cardBody: "Keep stations, favorites, and listening context attached to your AV account.",
    cardTitle: "Continue from your signal",
    cta: "Sign in",
    heroBody: "Sign in to manage your Tune AV account and plan. Listening happens in the Tune AV app for iPhone and iPad.",
    heroTitle: "Radio calm, account connected.",
    intro: "Tune AV keeps radio-style listening focused, private, and available from your signed-in AV account.",
    mapBody: "The web experience uses Tune AV's radio mood: dark panels, clean signal lines, and Avi close to the session.",
    mapTitle: "A listening room for focused sessions.",
    notebook: "Saved library",
    listen: "Station tuning"
  },
  meta: {
    description: "Tune AV account: manage your Apps AV sign-in, Tune AV Pro status, and settings. Listen with the Tune AV app for iPhone and iPad."
  },
  nav: {
    account: "Account",
    home: "Home",
    homeLabel: "Tune AV home",
    mobileNavigation: "Mobile navigation",
    openNavigation: "Open navigation",
    primaryNavigation: "Primary navigation",
    settings: "Settings"
  },
  signIn: {
    aviPanelBody: "Avi keeps the next station calm and intentional.",
    body: "Sign in to manage your Tune AV account, Pro status, and settings with your AV account.",
    continue: "Continue",
    signedIn: "You are signed in.",
    title: "Tune AV follows your signal."
  }
};

const es: typeof en = {
  account: {
    signInTitle: "Inicia sesión en Tune AV",
    signInSubtitle: "Vuelve a entrar para gestionar tu cuenta, plan y ajustes de Tune AV."
  },
  config: {
    body: "Ejecuta la web con el wrapper de Varlock para que la configuración de Account AV esté disponible. La home pública es informativa; las rutas de cuenta requieren login.",
    eyebrow: "Configuración requerida",
    title: "Tune AV Web necesita la configuración de Clerk."
  },
  footer: {
    deleteAccount: "Eliminar cuenta",
    language: "Idioma",
    privacy: "Privacidad",
    support: "Soporte",
    terms: "Términos"
  },
  home: {
    accountBody: "Correo, plan, cierre de sesión y eliminación de cuenta.",
    accountCta: "Cuenta",
    appStoreBadgeAlt: "Descargar Tune AV en App Store",
    body: "Tune AV vive en la app de iOS: radio en directo, Mis canciones y guía de Avi para iPhone y iPad. Esta página mantiene tu cuenta, plan y ajustes accesibles desde cualquier navegador.",
    getApp: "Descarga la app",
    getAppBody: "Descarga Tune AV para iPhone y iPad en App Store. Tune AV Pro se compra dentro de la app.",
    planFree: "Tune AV Free",
    planLoading: "Comprobando tu plan...",
    planPro: "Tune AV Pro",
    planTitle: "Tu plan",
    settingsBody: "Idioma, apariencia, ayuda y enlaces legales.",
    settingsCta: "Ajustes",
    title: "Tu sala de escucha está lista."
  },
  login: {
    appStoreNote: "Tune AV para iPhone y iPad está en App Store. Inicia sesión aquí para gestionar tu cuenta.",
    aviGuidance: "Guía de Avi",
    cardBody: "Mantén emisoras, favoritos y contexto de escucha unidos a tu cuenta AV.",
    cardTitle: "Continúa desde tu señal",
    cta: "Iniciar sesión",
    heroBody: "Inicia sesión para gestionar tu cuenta y plan de Tune AV. La escucha ocurre en la app de Tune AV para iPhone y iPad.",
    heroTitle: "Radio tranquila, cuenta conectada.",
    intro: "Tune AV mantiene la escucha tipo radio enfocada, privada y disponible desde tu cuenta AV.",
    mapBody: "La web usa el tono de radio de Tune AV: paneles oscuros, líneas limpias y Avi cerca de la sesión.",
    mapTitle: "Una sala de escucha para sesiones enfocadas.",
    notebook: "Biblioteca guardada",
    listen: "Sintonización"
  },
  meta: {
    description: "Cuenta de Tune AV: gestiona tu acceso Apps AV, el estado de Tune AV Pro y los ajustes. Escucha con la app de Tune AV para iPhone y iPad."
  },
  nav: {
    account: "Cuenta",
    home: "Inicio",
    homeLabel: "Inicio de Tune AV",
    mobileNavigation: "Navegación móvil",
    openNavigation: "Abrir navegación",
    primaryNavigation: "Navegación principal",
    settings: "Ajustes"
  },
  signIn: {
    aviPanelBody: "Avi mantiene la próxima emisora tranquila e intencional.",
    body: "Inicia sesión para gestionar tu cuenta de Tune AV, el estado Pro y los ajustes con tu cuenta AV.",
    continue: "Continuar",
    signedIn: "Has iniciado sesión.",
    title: "Tune AV sigue tu señal."
  }
};

const ca: typeof en = {
  account: { signInTitle: "Inicia sessio a Tune AV", signInSubtitle: "Torna-hi per gestionar el compte, el pla i els ajustos de Tune AV." },
  config: {
    body: "Executa la web amb el wrapper de Varlock perque la configuracio d'Account AV estigui disponible. La home publica es informativa; les rutes de compte requereixen login.",
    eyebrow: "Configuracio requerida",
    title: "Tune AV Web necessita la configuracio de Clerk."
  },
  footer: { deleteAccount: "Eliminar compte", language: "Idioma", privacy: "Privacitat", support: "Suport", terms: "Termes" },
  home: {
    accountBody: "Correu, pla, tancament de sessio i eliminacio del compte.",
    accountCta: "Compte",
    appStoreBadgeAlt: "Descarrega Tune AV a l'App Store",
    body: "Tune AV viu a l'app d'iOS: radio en directe, Les meves cancons i guia d'Avi per a iPhone i iPad. Aquesta pagina mante el compte, el pla i els ajustos accessibles des de qualsevol navegador.",
    getApp: "Descarrega l'app",
    getAppBody: "Descarrega Tune AV per a iPhone i iPad a l'App Store. Tune AV Pro es compra dins de l'app.",
    planFree: "Tune AV Free",
    planLoading: "Comprovant el teu pla...",
    planPro: "Tune AV Pro",
    planTitle: "El teu pla",
    settingsBody: "Idioma, aparenca, ajuda i enllacos legals.",
    settingsCta: "Ajustos",
    title: "La teva sala d'escolta esta a punt."
  },
  login: {
    appStoreNote: "Tune AV per a iPhone i iPad es a l'App Store. Inicia sessio aqui per gestionar el compte.",
    aviGuidance: "Guia d'Avi",
    cardBody: "Mantingues emissores, favorits i context d'escolta units al teu compte AV.",
    cardTitle: "Continua des de la teva senyal",
    cta: "Inicia sessio",
    heroBody: "Inicia sessio per gestionar el compte i el pla de Tune AV. L'escolta passa a l'app de Tune AV per a iPhone i iPad.",
    heroTitle: "Radio tranquil.la, compte connectat.",
    intro: "Tune AV mante l'escolta tipus radio enfocada, privada i disponible des del teu compte AV.",
    mapBody: "La web usa el to de radio de Tune AV: panells foscos, linies netes i Avi a prop de la sessio.",
    mapTitle: "Una sala d'escolta per a sessions enfocades.",
    notebook: "Biblioteca desada",
    listen: "Sintonitzacio"
  },
  meta: {
    description: "Compte de Tune AV: gestiona l'acces Apps AV, l'estat de Tune AV Pro i els ajustos. Escolta amb l'app de Tune AV per a iPhone i iPad."
  },
  nav: { account: "Compte", home: "Inici", homeLabel: "Inici de Tune AV", mobileNavigation: "Navegacio mobil", openNavigation: "Obre la navegacio", primaryNavigation: "Navegacio principal", settings: "Ajustos" },
  signIn: {
    aviPanelBody: "Avi mante la propera emissora tranquil.la i intencional.",
    body: "Inicia sessio per gestionar el compte de Tune AV, l'estat Pro i els ajustos amb el teu compte AV.",
    continue: "Continua",
    signedIn: "Has iniciat sessio.",
    title: "Tune AV segueix la teva senyal."
  }
};

const de: typeof en = {
  account: { signInTitle: "Bei Tune AV anmelden", signInSubtitle: "Melde dich an, um Konto, Tarif und Einstellungen von Tune AV zu verwalten." },
  config: {
    body: "Starte die Web-App ueber den Varlock-Wrapper, damit die Account AV Konfiguration verfuegbar ist. Die oeffentliche Startseite ist informativ; Kontorouten erfordern Anmeldung.",
    eyebrow: "Konfiguration erforderlich",
    title: "Tune AV Web braucht Clerk-Konfiguration."
  },
  footer: { deleteAccount: "Konto loeschen", language: "Sprache", privacy: "Datenschutz", support: "Hilfe", terms: "Bedingungen" },
  home: {
    accountBody: "E-Mail, Tarif, Abmelden und Kontoloeschung.",
    accountCta: "Konto",
    appStoreBadgeAlt: "Tune AV im App Store laden",
    body: "Tune AV lebt in der iOS-App: Live-Radio, Meine Songs und Avi-Hilfe fuer iPhone und iPad. Diese Seite haelt Konto, Tarif und Einstellungen in jedem Browser erreichbar.",
    getApp: "App laden",
    getAppBody: "Lade Tune AV fuer iPhone und iPad im App Store. Tune AV Pro wird in der App gekauft.",
    planFree: "Tune AV Free",
    planLoading: "Tarif wird geprueft...",
    planPro: "Tune AV Pro",
    planTitle: "Dein Tarif",
    settingsBody: "Sprache, Darstellung, Hilfe und rechtliche Links.",
    settingsCta: "Einstellungen",
    title: "Dein Hoerraum ist bereit."
  },
  login: {
    appStoreNote: "Tune AV fuer iPhone und iPad gibt es im App Store. Melde dich hier an, um dein Konto zu verwalten.",
    aviGuidance: "Avi-Hilfe",
    cardBody: "Halte Sender, Favoriten und Hoerkontext mit deinem AV-Konto verbunden.",
    cardTitle: "Weiter von deinem Signal",
    cta: "Anmelden",
    heroBody: "Melde dich an, um Konto und Tarif von Tune AV zu verwalten. Gehoert wird in der Tune AV App fuer iPhone und iPad.",
    heroTitle: "Ruhiges Radio, verbundenes Konto.",
    intro: "Tune AV haelt radioartiges Hoeren fokussiert, privat und in deinem AV-Konto verfuegbar.",
    mapBody: "Die Web-Erfahrung nutzt Tune AVs Radiostimmung: dunkle Flaechen, klare Signallinien und Avi nah an der Sitzung.",
    mapTitle: "Ein Hoerraum fuer fokussierte Sitzungen.",
    notebook: "Gespeicherte Bibliothek",
    listen: "Senderabstimmung"
  },
  meta: {
    description: "Tune AV Konto: verwalte deine Apps AV Anmeldung, den Tune AV Pro Status und Einstellungen. Hoere mit der Tune AV App fuer iPhone und iPad."
  },
  nav: { account: "Konto", home: "Start", homeLabel: "Tune AV Start", mobileNavigation: "Mobile Navigation", openNavigation: "Navigation oeffnen", primaryNavigation: "Hauptnavigation", settings: "Einstellungen" },
  signIn: {
    aviPanelBody: "Avi haelt den naechsten Sender ruhig und bewusst.",
    body: "Melde dich an, um Tune AV Konto, Pro-Status und Einstellungen mit deinem AV-Konto zu verwalten.",
    continue: "Weiter",
    signedIn: "Du bist angemeldet.",
    title: "Tune AV folgt deinem Signal."
  }
};

const fr: typeof en = {
  account: { signInTitle: "Connexion a Tune AV", signInSubtitle: "Connectez-vous pour gerer votre compte, votre formule et vos reglages Tune AV." },
  config: {
    body: "Lancez l'app web avec le wrapper Varlock pour rendre la configuration Account AV disponible. L'accueil public est informatif; les routes de compte demandent une connexion.",
    eyebrow: "Configuration requise",
    title: "Tune AV Web a besoin de la configuration Clerk."
  },
  footer: { deleteAccount: "Supprimer le compte", language: "Langue", privacy: "Confidentialite", support: "Assistance", terms: "Conditions" },
  home: {
    accountBody: "E-mail, formule, deconnexion et suppression du compte.",
    accountCta: "Compte",
    appStoreBadgeAlt: "Telecharger Tune AV sur l'App Store",
    body: "Tune AV vit dans l'app iOS : radio en direct, Mes titres et aide d'Avi pour iPhone et iPad. Cette page garde votre compte, votre formule et vos reglages accessibles depuis tout navigateur.",
    getApp: "Telecharger l'app",
    getAppBody: "Telechargez Tune AV pour iPhone et iPad sur l'App Store. Tune AV Pro s'achete dans l'app.",
    planFree: "Tune AV Free",
    planLoading: "Verification de votre formule...",
    planPro: "Tune AV Pro",
    planTitle: "Votre formule",
    settingsBody: "Langue, apparence, aide et liens legaux.",
    settingsCta: "Reglages",
    title: "Votre salle d'ecoute est prete."
  },
  login: {
    appStoreNote: "Tune AV pour iPhone et iPad est sur l'App Store. Connectez-vous ici pour gerer votre compte.",
    aviGuidance: "Aide d'Avi",
    cardBody: "Gardez stations, favoris et contexte d'ecoute lies a votre compte AV.",
    cardTitle: "Continuer depuis votre signal",
    cta: "Se connecter",
    heroBody: "Connectez-vous pour gerer votre compte et votre formule Tune AV. L'ecoute se fait dans l'app Tune AV pour iPhone et iPad.",
    heroTitle: "Radio calme, compte connecte.",
    intro: "Tune AV garde l'ecoute type radio concentree, privee et disponible depuis votre compte AV.",
    mapBody: "L'experience web reprend l'ambiance radio de Tune AV : panneaux sombres, lignes de signal nettes et Avi proche de la session.",
    mapTitle: "Une salle d'ecoute pour les sessions focalisees.",
    notebook: "Bibliotheque enregistree",
    listen: "Accord de station"
  },
  meta: {
    description: "Compte Tune AV : gerez votre connexion Apps AV, le statut Tune AV Pro et vos reglages. Ecoutez avec l'app Tune AV pour iPhone et iPad."
  },
  nav: { account: "Compte", home: "Accueil", homeLabel: "Accueil Tune AV", mobileNavigation: "Navigation mobile", openNavigation: "Ouvrir la navigation", primaryNavigation: "Navigation principale", settings: "Reglages" },
  signIn: {
    aviPanelBody: "Avi garde la prochaine station calme et intentionnelle.",
    body: "Connectez-vous pour gerer votre compte Tune AV, le statut Pro et vos reglages avec votre compte AV.",
    continue: "Continuer",
    signedIn: "Vous etes connecte.",
    title: "Tune AV suit votre signal."
  }
};

export const tuneText: Record<AppsAvLocale, typeof en> = {
  ca,
  de,
  en,
  es,
  fr
};

export function useTuneText() {
  return tuneText[useAppsAvLocale()];
}

export function useTuneNavLinks(): AppsAvProductLink[] {
  const locale = useAppsAvLocale();
  const text = useTuneText();

  return [
    { href: localizedTunePath("/", locale), label: text.nav.home },
    { href: localizedTunePath("/account", locale), label: text.nav.account },
    { href: localizedTunePath("/settings", locale), label: text.nav.settings }
  ];
}

export function useTuneShellLabels() {
  const text = useTuneText();

  return {
    home: text.nav.homeLabel,
    mobileNavigation: text.nav.mobileNavigation,
    openNavigation: text.nav.openNavigation,
    primaryNavigation: text.nav.primaryNavigation
  };
}

export function useTuneAccountLocalization() {
  const text = useTuneText();
  const baseLocalization = {
    ca: caES,
    de: deDE,
    en: enUS,
    es: esES,
    fr: frFR
  }[useAppsAvLocale()];

  return {
    ...baseLocalization,
    signIn: {
      ...baseLocalization.signIn,
      start: {
        ...baseLocalization.signIn?.start,
        title: text.account.signInTitle,
        subtitle: text.account.signInSubtitle
      }
    }
  };
}

export function localizedTunePath(path: string, locale: AppsAvLocale): string {
  if (locale === "en") {
    return path;
  }

  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}lang=${locale}`;
}
