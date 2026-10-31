import type { AppsAvLocale } from "@avalsys/apps-av-web";

const en = {
  accountTitle: "My account",
  accountSubtitle: "Manage sign-in, access, plan, and account safety.",
  settingsTitle: "Settings",
  settingsSubtitle: "Choose language and appearance for this browser, and open help links.",
  pro: {
    accountDetail: "Pro access follows your Apps AV account on every device where you sign in.",
    accountTitle: "Pro account",
    assistantDetail: "Unlimited Avi guidance, lyrics, and public searches in the app.",
    assistantTitle: "Avi guidance",
    libraryDetail: "Favorites and saved discoveries sync across your devices with Pro.",
    libraryTitle: "Synced library",
    manage: "Manage in Account AV",
    subtitleFree: "Tune AV Free is active. Pro is purchased inside the Tune AV app on the App Store.",
    subtitlePro: "Tune AV Pro is active on this Apps AV account. Billing is managed through the App Store.",
    title: "Tune AV Pro",
    upgrade: "Get Tune AV on the App Store"
  },
  account: {
    connected: "Connected to Account AV.",
    emailTitle: "Email",
    planFree: "Tune AV Free",
    planPro: "Tune AV Pro",
    planTitle: "Plan",
    sessionTitle: "Session",
    signOut: "Sign out",
    signedIn: "Signed in",
    title: "Account"
  },
  safety: {
    deleteDetail: "Open the shared account deletion page.",
    deleteTitle: "Delete account",
    subtitle: "Sensitive account actions open the shared Account AV flow.",
    title: "Account safety"
  },
  preferences: {
    languageDetail: "Choose the language used by Tune AV.",
    languageTitle: "App language",
    subtitle: "Pick how Tune AV is shown on this device.",
    themeDetail: "Choose whether Tune AV follows the system appearance or uses a fixed theme here.",
    themeOptions: { dark: "Dark", light: "Light", system: "System" },
    themeTitle: "Appearance",
    title: "App preferences"
  },
  help: {
    deleteDetail: "Open the shared account deletion page.",
    deleteTitle: "Delete account",
    openSourceDetail: "Tune AV is maintained as an open-source product app.",
    openSourceTitle: "Open-source project",
    privacyDetail: "Review how Tune AV handles your data.",
    privacyTitle: "Privacy policy",
    sourceCodeDetail: "Open the repository, issues, and contribution context.",
    sourceCodeTitle: "Source code",
    subtitle: "Open support, privacy, terms, deletion, and source links.",
    supportDetail: "Open Tune AV support.",
    supportTitle: "Contact support",
    termsDetail: "Review the terms that apply to Tune AV.",
    termsTitle: "Terms of service",
    title: "Help and legal"
  }
};

export const tuneProfileLabels: Record<AppsAvLocale, typeof en> = {
  en,
  es: {
    ...en,
    accountTitle: "Mi cuenta",
    accountSubtitle: "Gestiona inicio de sesion, acceso, plan y seguridad de cuenta.",
    settingsTitle: "Ajustes",
    settingsSubtitle: "Elige idioma y apariencia para este navegador y abre enlaces de ayuda.",
    pro: { accountDetail: "El acceso Pro sigue tu cuenta de Apps AV en cada dispositivo donde inicies sesion.", accountTitle: "Cuenta Pro", assistantDetail: "Guia de Avi, letras y busquedas publicas sin limite en la app.", assistantTitle: "Guia de Avi", libraryDetail: "Favoritos y descubrimientos guardados se sincronizan entre tus dispositivos con Pro.", libraryTitle: "Biblioteca sincronizada", manage: "Gestionar en Account AV", subtitleFree: "Tune AV Free esta activo. Pro se compra dentro de la app de Tune AV en App Store.", subtitlePro: "Tune AV Pro esta activo en esta cuenta de Apps AV. La facturacion se gestiona en App Store.", title: "Tune AV Pro", upgrade: "Descargar Tune AV en App Store" },
    account: { ...en.account, connected: "Conectado a Account AV.", emailTitle: "Correo", planFree: "Tune AV Free", planPro: "Tune AV Pro", planTitle: "Tipo de cuenta", sessionTitle: "Sesion", signOut: "Cerrar sesion", signedIn: "Sesion iniciada", title: "Cuenta" },
    safety: { deleteDetail: "Abre la pagina compartida de eliminacion de cuenta.", deleteTitle: "Eliminar cuenta", subtitle: "Las acciones sensibles abren el flujo compartido de Account AV.", title: "Seguridad de cuenta" },
    preferences: { ...en.preferences, languageDetail: "Elige el idioma usado por Tune AV.", languageTitle: "Idioma de la app", subtitle: "Elige como se muestra Tune AV en este dispositivo.", themeDetail: "Elige si Tune AV sigue el sistema o usa un tema fijo aqui.", themeOptions: { dark: "Oscuro", light: "Claro", system: "Sistema" }, themeTitle: "Apariencia", title: "Preferencias de la app" },
    help: { ...en.help, deleteDetail: "Abre la pagina compartida de eliminacion de cuenta.", deleteTitle: "Eliminar cuenta", openSourceDetail: "Tune AV se mantiene como app de producto open-source.", openSourceTitle: "Proyecto open-source", privacyDetail: "Revisa como Tune AV gestiona tus datos.", privacyTitle: "Politica de privacidad", sourceCodeDetail: "Abre repositorio, incidencias y contexto de contribucion.", sourceCodeTitle: "Codigo fuente", subtitle: "Abre soporte, privacidad, terminos, eliminacion y codigo fuente.", supportDetail: "Abre soporte de Tune AV.", supportTitle: "Contactar soporte", termsDetail: "Revisa los terminos aplicables a Tune AV.", termsTitle: "Terminos de servicio", title: "Ayuda y legal" }
  },
  ca: {
    ...en,
    accountTitle: "El meu compte",
    accountSubtitle: "Gestiona inici de sessio, acces, pla i seguretat del compte.",
    settingsTitle: "Ajustos",
    settingsSubtitle: "Tria idioma i aparenca per a aquest navegador i obre enllacos d'ajuda.",
    pro: { accountDetail: "L'acces Pro segueix el teu compte Apps AV a cada dispositiu on inicies sessio.", accountTitle: "Compte Pro", assistantDetail: "Guia d'Avi, lletres i cerques publiques sense limit a l'app.", assistantTitle: "Guia d'Avi", libraryDetail: "Favorits i descobriments desats es sincronitzen entre dispositius amb Pro.", libraryTitle: "Biblioteca sincronitzada", manage: "Gestiona a Account AV", subtitleFree: "Tune AV Free esta actiu. Pro es compra dins de l'app de Tune AV a l'App Store.", subtitlePro: "Tune AV Pro esta actiu en aquest compte Apps AV. La facturacio es gestiona a l'App Store.", title: "Tune AV Pro", upgrade: "Descarrega Tune AV a l'App Store" },
    account: { ...en.account, connected: "Connectat a Account AV.", emailTitle: "Correu electronic", planFree: "Tune AV Free", planPro: "Tune AV Pro", planTitle: "Pla", sessionTitle: "Sessio", signOut: "Tancar sessio", signedIn: "Sessio iniciada", title: "Compte" },
    safety: { deleteDetail: "Obre la pagina compartida d'eliminacio de compte.", deleteTitle: "Eliminar compte", subtitle: "Les accions sensibles obren el flux compartit d'Account AV.", title: "Seguretat del compte" },
    preferences: { ...en.preferences, languageDetail: "Tria l'idioma que fa servir Tune AV.", languageTitle: "Idioma de l'app", subtitle: "Tria com es mostra Tune AV en aquest dispositiu.", themeDetail: "Tria si Tune AV segueix el sistema o usa un tema fix aqui.", themeOptions: { dark: "Fosc", light: "Clar", system: "Sistema" }, themeTitle: "Aparenca", title: "Preferencies de l'app" },
    help: { ...en.help, deleteDetail: "Obre la pagina compartida d'eliminacio de compte.", deleteTitle: "Eliminar compte", openSourceDetail: "Tune AV es mante com una app de producte open-source.", openSourceTitle: "Projecte open-source", privacyDetail: "Revisa com Tune AV gestiona les teves dades.", privacyTitle: "Politica de privacitat", sourceCodeDetail: "Obre repositori, incidencies i context de contribucio.", sourceCodeTitle: "Codi font", subtitle: "Obre suport, privacitat, termes, eliminacio i codi font.", supportDetail: "Obre suport de Tune AV.", supportTitle: "Contactar suport", termsDetail: "Revisa els termes aplicables a Tune AV.", termsTitle: "Termes del servei", title: "Ajuda i legal" }
  },
  de: {
    ...en,
    accountTitle: "Mein Konto",
    accountSubtitle: "Anmeldung, Zugriff, Plan und Kontosicherheit verwalten.",
    settingsTitle: "Einstellungen",
    settingsSubtitle: "Sprache und Darstellung fuer diesen Browser waehlen und Hilfelinks oeffnen.",
    pro: { accountDetail: "Pro-Zugriff folgt deinem Apps AV Konto auf jedem Geraet, auf dem du dich anmeldest.", accountTitle: "Pro-Konto", assistantDetail: "Unbegrenzte Avi-Hilfe, Songtexte und oeffentliche Suchen in der App.", assistantTitle: "Avi-Hilfe", libraryDetail: "Favoriten und gespeicherte Entdeckungen synchronisieren sich mit Pro ueber deine Geraete.", libraryTitle: "Synchronisierte Bibliothek", manage: "In Account AV verwalten", subtitleFree: "Tune AV Free ist aktiv. Pro wird in der Tune AV App im App Store gekauft.", subtitlePro: "Tune AV Pro ist auf diesem Apps AV Konto aktiv. Die Abrechnung laeuft ueber den App Store.", title: "Tune AV Pro", upgrade: "Tune AV im App Store laden" },
    account: { ...en.account, connected: "Verbunden mit Account AV.", emailTitle: "E-Mail", planFree: "Tune AV Free", planPro: "Tune AV Pro", planTitle: "Tarif", sessionTitle: "Sitzung", signOut: "Abmelden", signedIn: "Angemeldet", title: "Konto" },
    safety: { deleteDetail: "Oeffne die gemeinsame Seite zur Kontoloeschung.", deleteTitle: "Konto loeschen", subtitle: "Sensible Kontoaktionen oeffnen den gemeinsamen Account AV Ablauf.", title: "Kontosicherheit" },
    preferences: { ...en.preferences, languageDetail: "Waehle die Sprache von Tune AV.", languageTitle: "App-Sprache", subtitle: "Lege fest, wie Tune AV auf diesem Geraet angezeigt wird.", themeDetail: "Waehle, ob Tune AV dem System folgt oder hier ein festes Theme nutzt.", themeOptions: { dark: "Dunkel", light: "Hell", system: "System" }, themeTitle: "Darstellung", title: "App-Einstellungen" },
    help: { ...en.help, deleteDetail: "Oeffne die gemeinsame Seite zur Kontoloeschung.", deleteTitle: "Konto loeschen", openSourceDetail: "Tune AV wird als Open-Source-Produkt-App gepflegt.", openSourceTitle: "Open-Source-Projekt", privacyDetail: "Pruefe, wie Tune AV mit deinen Daten umgeht.", privacyTitle: "Datenschutz", sourceCodeDetail: "Oeffne Repository, Issues und Beitragskontext.", sourceCodeTitle: "Quellcode", subtitle: "Oeffne Support, Datenschutz, Bedingungen, Loeschung und Quellcode.", supportDetail: "Tune AV Support oeffnen.", supportTitle: "Support kontaktieren", termsDetail: "Pruefe die fuer Tune AV geltenden Bedingungen.", termsTitle: "Nutzungsbedingungen", title: "Hilfe und Rechtliches" }
  },
  fr: {
    ...en,
    accountTitle: "Mon compte",
    accountSubtitle: "Gerez connexion, acces, plan et securite du compte.",
    settingsTitle: "Reglages",
    settingsSubtitle: "Choisissez langue et apparence pour ce navigateur et ouvrez les liens d'aide.",
    pro: { accountDetail: "L'acces Pro suit votre compte Apps AV sur chaque appareil ou vous vous connectez.", accountTitle: "Compte Pro", assistantDetail: "Aide d'Avi, paroles et recherches publiques sans limite dans l'app.", assistantTitle: "Aide d'Avi", libraryDetail: "Favoris et decouvertes enregistrees se synchronisent entre vos appareils avec Pro.", libraryTitle: "Bibliotheque synchronisee", manage: "Gerer dans Account AV", subtitleFree: "Tune AV Free est actif. Pro s'achete dans l'app Tune AV sur l'App Store.", subtitlePro: "Tune AV Pro est actif sur ce compte Apps AV. La facturation passe par l'App Store.", title: "Tune AV Pro", upgrade: "Telecharger Tune AV sur l'App Store" },
    account: { ...en.account, connected: "Connecte a Account AV.", emailTitle: "E-mail", planFree: "Tune AV Free", planPro: "Tune AV Pro", planTitle: "Formule", sessionTitle: "Session active", signOut: "Se deconnecter", signedIn: "Connecte", title: "Compte" },
    safety: { deleteDetail: "Ouvrir la page partagee de suppression du compte.", deleteTitle: "Supprimer le compte", subtitle: "Les actions sensibles ouvrent le flux Account AV partage.", title: "Securite du compte" },
    preferences: { ...en.preferences, languageDetail: "Choisissez la langue utilisee par Tune AV.", languageTitle: "Langue de l'app", subtitle: "Choisissez comment Tune AV s'affiche sur cet appareil.", themeDetail: "Choisissez si Tune AV suit le systeme ou utilise un theme fixe ici.", themeOptions: { dark: "Sombre", light: "Clair", system: "Systeme" }, themeTitle: "Apparence", title: "Preferences de l'app" },
    help: { ...en.help, deleteDetail: "Ouvrir la page partagee de suppression du compte.", deleteTitle: "Supprimer le compte", openSourceDetail: "Tune AV est maintenue comme app produit open-source.", openSourceTitle: "Projet open-source", privacyDetail: "Consultez comment Tune AV gere vos donnees.", privacyTitle: "Politique de confidentialite", sourceCodeDetail: "Ouvrez le depot, les issues et le contexte de contribution.", sourceCodeTitle: "Code source", subtitle: "Ouvrez support, confidentialite, termes, suppression et code source.", supportDetail: "Ouvrir le support Tune AV.", supportTitle: "Contacter le support", termsDetail: "Consultez les termes applicables a Tune AV.", termsTitle: "Conditions du service", title: "Aide et legal" }
  }
};
