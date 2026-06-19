import type { AppsAvLocale } from "@avalsys/apps-av-web";

const en = {
  accountTitle: "My account",
  accountSubtitle: "Manage sign-in, access, plan, and account safety.",
  settingsTitle: "Settings",
  settingsSubtitle: "Tune the app, manage this browser, and open help links.",
  pro: {
    accountDetail: "Keep Pro access linked to your Apps AV account.",
    accountTitle: "Pro account",
    assistantDetail: "Use Avi guidance from favorites, recents, discoveries, and feedback.",
    assistantTitle: "Avi guidance",
    libraryDetail: "Cloud sync favorites and saved discoveries when Tune AV Pro is active.",
    libraryTitle: "Synced library",
    manage: "Manage in Account AV",
    subtitleFree: "Tune AV Free keeps listening local-first. Pro management opens Account AV.",
    subtitlePro: "Tune AV Pro is active. Billing and account management stay in Account AV.",
    title: "Tune AV Pro",
    upgrade: "View Pro in Account AV"
  },
  sync: {
    detailDisabled: "Cloud sync turns on with Tune AV Pro.",
    detailFailed: "Tune AV could not update your account library. Try again when you are online.",
    detailSynced: "Favorites and saved discoveries are up to date.",
    detailSyncing: "Tune AV is updating your account library.",
    headlineDisabled: "Sync unavailable",
    headlineFailed: "Sync needs attention",
    headlineSynced: "Library synced",
    headlineSyncing: "Syncing library",
    retry: "Sync now",
    retrySyncing: "Syncing...",
    subtitle: "Pro favorites and saved discoveries follow your Apps AV account.",
    title: "Cloud sync"
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
  tune: {
    countryDetail: "Preferred country is used as the default station feed when available.",
    countryTitle: "Station country",
    discoveryDetail: "Music mode prioritizes stations with track metadata; all radio keeps the feed broader.",
    discoveryOptions: { allRadio: "All radio", music: "Music" },
    discoveryTitle: "Discovery mode",
    externalSearchDetail: "Choose the search engine used for public info and lyrics links.",
    externalSearchOptions: { bing: "Bing", duckduckgo: "DuckDuckGo", google: "Google" },
    externalSearchTitle: "Search engine",
    genreDetail: "Preferred genre is used as a starting point for station browsing.",
    genreTitle: "Preferred genre",
    subtitle: "Tune AV keeps these preferences local to this browser.",
    title: "Listening preferences"
  },
  local: {
    delete: {
      confirmDetail: "Favorites, recents, discoveries, feedback, pending sessions, and Tune AV preferences saved in this browser will be deleted. This does not delete your Apps AV account.",
      confirmTitle: "Delete local Tune AV data",
      detail: (count: number) => `Deletes ${count} local items from this browser.`,
      empty: "There is no local Tune AV data to delete.",
      title: "Delete local data"
    },
    libraryDetail: "Free keeps favorites, recents, discoveries, and feedback in this browser when cloud sync is not active.",
    libraryTitle: "Local library",
    subtitle: "Local Tune AV data stays on this browser unless Pro sync is available.",
    syncDetail: "Pro cloud sync covers favorites and saved discoveries only under the existing app-data contract.",
    syncTitle: "Sync boundary",
    title: "On this device"
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
    settingsSubtitle: "Ajusta la app, gestiona este navegador y abre enlaces de ayuda.",
    pro: { ...en.pro, accountDetail: "Mantén el acceso Pro vinculado a tu cuenta de Apps AV.", assistantDetail: "Usa guia de Avi desde favoritos, recientes, descubrimientos y feedback.", assistantTitle: "Guia de Avi", libraryDetail: "Sincroniza favoritos y descubrimientos guardados cuando Tune AV Pro esta activo.", libraryTitle: "Biblioteca sincronizada", manage: "Gestionar en Account AV", subtitleFree: "Tune AV Free mantiene la escucha local-first. La gestion Pro abre Account AV.", subtitlePro: "Tune AV Pro esta activo. Billing y cuenta siguen en Account AV.", upgrade: "Ver Pro en Account AV" },
    sync: { ...en.sync, detailDisabled: "La sincronizacion cloud se activa con Tune AV Pro.", detailFailed: "Tune AV no ha podido actualizar tu biblioteca de cuenta. Intentalo cuando tengas conexion.", detailSynced: "Favoritos y descubrimientos guardados estan al dia.", detailSyncing: "Tune AV esta actualizando tu biblioteca de cuenta.", headlineDisabled: "Sync no disponible", headlineFailed: "La sync necesita atencion", headlineSynced: "Biblioteca sincronizada", headlineSyncing: "Sincronizando biblioteca", retry: "Sincronizar ahora", retrySyncing: "Sincronizando...", subtitle: "Favoritos y descubrimientos Pro siguen tu cuenta de Apps AV.", title: "Sincronizacion cloud" },
    account: { ...en.account, connected: "Conectado a Account AV.", planFree: "Tune AV Free", planPro: "Tune AV Pro", planTitle: "Plan", sessionTitle: "Sesion", signOut: "Cerrar sesion", signedIn: "Sesion iniciada", title: "Cuenta" },
    safety: { deleteDetail: "Abre la pagina compartida de eliminacion de cuenta.", deleteTitle: "Eliminar cuenta", subtitle: "Las acciones sensibles abren el flujo compartido de Account AV.", title: "Seguridad de cuenta" },
    preferences: { ...en.preferences, languageDetail: "Elige el idioma usado por Tune AV.", languageTitle: "Idioma de la app", subtitle: "Elige como se muestra Tune AV en este dispositivo.", themeDetail: "Elige si Tune AV sigue el sistema o usa un tema fijo aqui.", themeOptions: { dark: "Oscuro", light: "Claro", system: "Sistema" }, themeTitle: "Apariencia", title: "Preferencias de la app" },
    tune: { ...en.tune, countryDetail: "El pais preferido se usa como feed inicial cuando esta disponible.", countryTitle: "Pais de emisoras", discoveryDetail: "Musica prioriza emisoras con metadata de pistas; toda la radio mantiene el feed mas amplio.", discoveryOptions: { allRadio: "Toda la radio", music: "Musica" }, discoveryTitle: "Modo de descubrimiento", externalSearchDetail: "Elige el motor usado para enlaces de informacion publica y letras.", externalSearchOptions: { bing: "Bing", duckduckgo: "DuckDuckGo", google: "Google" }, externalSearchTitle: "Motor de busqueda", genreDetail: "El genero preferido se usa como punto de partida.", genreTitle: "Genero preferido", subtitle: "Tune AV mantiene estas preferencias locales en este navegador.", title: "Preferencias de escucha" },
    local: { ...en.local, delete: { confirmDetail: "Se borraran favoritos, recientes, descubrimientos, feedback, sesiones pendientes y preferencias de Tune AV guardadas en este navegador. Esto no elimina tu cuenta Apps AV.", confirmTitle: "Eliminar datos locales de Tune AV", detail: (count: number) => `Elimina ${count} elementos locales de este navegador.`, empty: "No hay datos locales de Tune AV para eliminar.", title: "Eliminar datos locales" }, libraryDetail: "Free guarda favoritos, recientes, descubrimientos y feedback en este navegador cuando cloud sync no esta activo.", libraryTitle: "Biblioteca local", subtitle: "Los datos locales de Tune AV quedan en este navegador salvo que Pro sync este disponible.", syncDetail: "Pro cloud sync cubre favoritos y descubrimientos guardados bajo el contrato app-data existente.", syncTitle: "Limite de sync", title: "En este dispositivo" },
    help: { ...en.help, deleteDetail: "Abre la pagina compartida de eliminacion de cuenta.", deleteTitle: "Eliminar cuenta", openSourceDetail: "Tune AV se mantiene como app de producto open-source.", openSourceTitle: "Proyecto open-source", privacyDetail: "Revisa como Tune AV gestiona tus datos.", privacyTitle: "Politica de privacidad", sourceCodeDetail: "Abre repositorio, incidencias y contexto de contribucion.", sourceCodeTitle: "Codigo fuente", subtitle: "Abre soporte, privacidad, terminos, eliminacion y codigo fuente.", supportDetail: "Abre soporte de Tune AV.", supportTitle: "Contactar soporte", termsDetail: "Revisa los terminos aplicables a Tune AV.", termsTitle: "Terminos de servicio", title: "Ayuda y legal" }
  },
  ca: {
    ...en,
    accountTitle: "El meu compte",
    accountSubtitle: "Gestiona inici de sessio, acces, pla i seguretat del compte.",
    settingsTitle: "Ajustos",
    settingsSubtitle: "Ajusta l'app, gestiona aquest navegador i obre enllacos d'ajuda.",
    pro: { ...en.pro, accountDetail: "Mantingues l'acces Pro vinculat al teu compte Apps AV.", assistantDetail: "Fes servir la guia d'Avi amb favorits, recents, descobriments i feedback.", assistantTitle: "Guia d'Avi", libraryDetail: "Sincronitza favorits i descobriments desats quan Tune AV Pro esta actiu.", libraryTitle: "Biblioteca sincronitzada", manage: "Gestiona a Account AV", subtitleFree: "Tune AV Free mante l'escolta local-first. La gestio Pro obre Account AV.", subtitlePro: "Tune AV Pro esta actiu. Facturacio i compte es gestionen a Account AV.", upgrade: "Veure Pro a Account AV" },
    sync: { ...en.sync, detailDisabled: "La sincronitzacio cloud s'activa amb Tune AV Pro.", detailFailed: "Tune AV no ha pogut actualitzar la biblioteca del compte. Torna-ho a provar amb connexio.", detailSynced: "Favorits i descobriments desats estan al dia.", detailSyncing: "Tune AV esta actualitzant la biblioteca del compte.", headlineDisabled: "Sync no disponible", headlineFailed: "La sync necessita atencio", headlineSynced: "Biblioteca sincronitzada", headlineSyncing: "Sincronitzant biblioteca", retry: "Sincronitzar ara", retrySyncing: "Sincronitzant...", subtitle: "Favorits i descobriments Pro segueixen el teu compte Apps AV.", title: "Sincronitzacio cloud" },
    account: { ...en.account, connected: "Connectat a Account AV.", emailTitle: "Correu electronic", planTitle: "Pla", sessionTitle: "Sessio", signOut: "Tancar sessio", signedIn: "Sessio iniciada", title: "Compte" },
    safety: { deleteDetail: "Obre la pagina compartida d'eliminacio de compte.", deleteTitle: "Eliminar compte", subtitle: "Les accions sensibles obren el flux compartit d'Account AV.", title: "Seguretat del compte" },
    preferences: { ...en.preferences, languageDetail: "Tria l'idioma que fa servir Tune AV.", languageTitle: "Idioma de l'app", subtitle: "Tria com es mostra Tune AV en aquest dispositiu.", themeDetail: "Tria si Tune AV segueix el sistema o usa un tema fix aqui.", themeOptions: { dark: "Fosc", light: "Clar", system: "Sistema" }, themeTitle: "Aparenca", title: "Preferencies de l'app" },
    tune: { ...en.tune, countryDetail: "El pais preferit s'usa com a feed inicial quan esta disponible.", countryTitle: "Pais d'emissores", discoveryDetail: "Musica prioritza emissores amb metadata de pistes; tota la radio mante el feed mes ampli.", discoveryOptions: { allRadio: "Tota la radio", music: "Musica" }, discoveryTitle: "Mode de descobriment", externalSearchDetail: "Tria el motor per als enllacos d'informacio publica i lletres.", externalSearchOptions: { bing: "Bing", duckduckgo: "DuckDuckGo", google: "Google" }, externalSearchTitle: "Motor de cerca", genreDetail: "El genere preferit s'usa com a punt de partida.", genreTitle: "Genere preferit", subtitle: "Tune AV mante aquestes preferencies locals en aquest navegador.", title: "Preferencies d'escolta" },
    local: { ...en.local, delete: { confirmDetail: "S'esborraran favorits, recents, descobriments, feedback, sessions pendents i preferencies de Tune AV d'aquest navegador. Aixo no elimina el teu compte Apps AV.", confirmTitle: "Eliminar dades locals de Tune AV", detail: (count: number) => `Elimina ${count} elements locals d'aquest navegador.`, empty: "No hi ha dades locals de Tune AV per eliminar.", title: "Eliminar dades locals" }, libraryDetail: "Free guarda favorits, recents, descobriments i feedback en aquest navegador quan cloud sync no esta actiu.", libraryTitle: "Biblioteca local", subtitle: "Les dades locals de Tune AV queden en aquest navegador tret que Pro sync estigui disponible.", syncDetail: "Pro cloud sync cobreix favorits i descobriments desats sota el contracte app-data existent.", syncTitle: "Limit de sync", title: "En aquest dispositiu" },
    help: { ...en.help, deleteDetail: "Obre la pagina compartida d'eliminacio de compte.", deleteTitle: "Eliminar compte", openSourceDetail: "Tune AV es mante com una app de producte open-source.", openSourceTitle: "Projecte open-source", privacyDetail: "Revisa com Tune AV gestiona les teves dades.", privacyTitle: "Politica de privacitat", sourceCodeDetail: "Obre repositori, incidencies i context de contribucio.", sourceCodeTitle: "Codi font", subtitle: "Obre suport, privacitat, termes, eliminacio i codi font.", supportDetail: "Obre suport de Tune AV.", supportTitle: "Contactar suport", termsDetail: "Revisa els termes aplicables a Tune AV.", termsTitle: "Termes del servei", title: "Ajuda i legal" }
  },
  de: {
    ...en,
    accountTitle: "Mein Konto",
    accountSubtitle: "Anmeldung, Zugriff, Plan und Kontosicherheit verwalten.",
    settingsTitle: "Einstellungen",
    settingsSubtitle: "App anpassen, diesen Browser verwalten und Hilfelinks oeffnen.",
    pro: { ...en.pro, accountDetail: "Pro-Zugriff mit deinem Apps AV Konto verknuepft halten.", assistantDetail: "Avi-Hilfe aus Favoriten, letzten Sendern, Entdeckungen und Feedback nutzen.", assistantTitle: "Avi-Hilfe", libraryDetail: "Favoriten und gespeicherte Entdeckungen synchronisieren, wenn Tune AV Pro aktiv ist.", libraryTitle: "Synchronisierte Bibliothek", manage: "In Account AV verwalten", subtitleFree: "Tune AV Free bleibt local-first. Pro-Verwaltung oeffnet Account AV.", subtitlePro: "Tune AV Pro ist aktiv. Abrechnung und Konto bleiben in Account AV.", upgrade: "Pro in Account AV ansehen" },
    sync: { ...en.sync, detailDisabled: "Cloud-Sync wird mit Tune AV Pro aktiviert.", detailFailed: "Tune AV konnte deine Kontobibliothek nicht aktualisieren. Versuche es erneut, wenn du online bist.", detailSynced: "Favoriten und gespeicherte Entdeckungen sind aktuell.", detailSyncing: "Tune AV aktualisiert deine Kontobibliothek.", headlineDisabled: "Sync nicht verfuegbar", headlineFailed: "Sync braucht Aufmerksamkeit", headlineSynced: "Bibliothek synchronisiert", headlineSyncing: "Bibliothek wird synchronisiert", retry: "Jetzt synchronisieren", retrySyncing: "Synchronisiert...", subtitle: "Pro-Favoriten und Entdeckungen folgen deinem Apps AV Konto.", title: "Cloud-Sync" },
    account: { ...en.account, connected: "Verbunden mit Account AV.", emailTitle: "E-Mail", planTitle: "Plan", sessionTitle: "Sitzung", signOut: "Abmelden", signedIn: "Angemeldet", title: "Konto" },
    safety: { deleteDetail: "Oeffne die gemeinsame Seite zur Kontoloeschung.", deleteTitle: "Konto loeschen", subtitle: "Sensible Kontoaktionen oeffnen den gemeinsamen Account AV Ablauf.", title: "Kontosicherheit" },
    preferences: { ...en.preferences, languageDetail: "Waehle die Sprache von Tune AV.", languageTitle: "App-Sprache", subtitle: "Lege fest, wie Tune AV auf diesem Geraet angezeigt wird.", themeDetail: "Waehle, ob Tune AV dem System folgt oder hier ein festes Theme nutzt.", themeOptions: { dark: "Dunkel", light: "Hell", system: "System" }, themeTitle: "Darstellung", title: "App-Einstellungen" },
    tune: { ...en.tune, countryDetail: "Das bevorzugte Land wird als Startfeed genutzt, wenn verfuegbar.", countryTitle: "Senderland", discoveryDetail: "Musik priorisiert Sender mit Track-Metadaten; alle Radios halten den Feed breiter.", discoveryOptions: { allRadio: "Alle Radios", music: "Musik" }, discoveryTitle: "Entdeckungsmodus", externalSearchDetail: "Waehle die Suchmaschine fuer Info- und Songtext-Links.", externalSearchOptions: { bing: "Bing", duckduckgo: "DuckDuckGo", google: "Google" }, externalSearchTitle: "Suchmaschine", genreDetail: "Das bevorzugte Genre wird als Startpunkt genutzt.", genreTitle: "Bevorzugtes Genre", subtitle: "Tune AV haelt diese Einstellungen lokal in diesem Browser.", title: "Hoer-Einstellungen" },
    local: { ...en.local, delete: { confirmDetail: "Favoriten, letzte Sender, Entdeckungen, Feedback, ausstehende Sitzungen und Tune AV Einstellungen in diesem Browser werden geloescht. Dein Apps AV Konto wird nicht geloescht.", confirmTitle: "Lokale Tune AV Daten loeschen", detail: (count: number) => `Loescht ${count} lokale Elemente aus diesem Browser.`, empty: "Es gibt keine lokalen Tune AV Daten zum Loeschen.", title: "Lokale Daten loeschen" }, libraryDetail: "Free speichert Favoriten, letzte Sender, Entdeckungen und Feedback in diesem Browser, wenn Cloud-Sync nicht aktiv ist.", libraryTitle: "Lokale Bibliothek", subtitle: "Lokale Tune AV Daten bleiben in diesem Browser, ausser Pro-Sync ist verfuegbar.", syncDetail: "Pro Cloud-Sync umfasst Favoriten und gespeicherte Entdeckungen im bestehenden app-data Vertrag.", syncTitle: "Sync-Grenze", title: "Auf diesem Geraet" },
    help: { ...en.help, deleteDetail: "Oeffne die gemeinsame Seite zur Kontoloeschung.", deleteTitle: "Konto loeschen", openSourceDetail: "Tune AV wird als Open-Source-Produkt-App gepflegt.", openSourceTitle: "Open-Source-Projekt", privacyDetail: "Pruefe, wie Tune AV mit deinen Daten umgeht.", privacyTitle: "Datenschutz", sourceCodeDetail: "Oeffne Repository, Issues und Beitragskontext.", sourceCodeTitle: "Quellcode", subtitle: "Oeffne Support, Datenschutz, Bedingungen, Loeschung und Quellcode.", supportDetail: "Tune AV Support oeffnen.", supportTitle: "Support kontaktieren", termsDetail: "Pruefe die fuer Tune AV geltenden Bedingungen.", termsTitle: "Nutzungsbedingungen", title: "Hilfe und Rechtliches" }
  },
  fr: {
    ...en,
    accountTitle: "Mon compte",
    accountSubtitle: "Gerez connexion, acces, plan et securite du compte.",
    settingsTitle: "Reglages",
    settingsSubtitle: "Ajustez l'app, gerez ce navigateur et ouvrez les liens d'aide.",
    pro: { ...en.pro, accountDetail: "Gardez l'acces Pro lie a votre compte Apps AV.", assistantDetail: "Utilisez l'aide d'Avi depuis favoris, recents, decouvertes et feedback.", assistantTitle: "Aide d'Avi", libraryDetail: "Synchronisez favoris et decouvertes enregistrees quand Tune AV Pro est actif.", libraryTitle: "Bibliotheque synchronisee", manage: "Gerer dans Account AV", subtitleFree: "Tune AV Free garde l'ecoute local-first. La gestion Pro ouvre Account AV.", subtitlePro: "Tune AV Pro est actif. Facturation et compte restent dans Account AV.", upgrade: "Voir Pro dans Account AV" },
    sync: { ...en.sync, detailDisabled: "La sync cloud s'active avec Tune AV Pro.", detailFailed: "Tune AV n'a pas pu mettre a jour votre bibliotheque de compte. Reessayez en ligne.", detailSynced: "Favoris et decouvertes enregistrees sont a jour.", detailSyncing: "Tune AV met a jour votre bibliotheque de compte.", headlineDisabled: "Sync indisponible", headlineFailed: "La sync demande attention", headlineSynced: "Bibliotheque synchronisee", headlineSyncing: "Synchronisation de la bibliotheque", retry: "Synchroniser maintenant", retrySyncing: "Synchronisation...", subtitle: "Les favoris et decouvertes Pro suivent votre compte Apps AV.", title: "Sync cloud" },
    account: { ...en.account, connected: "Connecte a Account AV.", emailTitle: "E-mail", planTitle: "Plan", sessionTitle: "Session", signOut: "Se deconnecter", signedIn: "Connecte", title: "Compte" },
    safety: { deleteDetail: "Ouvrir la page partagee de suppression du compte.", deleteTitle: "Supprimer le compte", subtitle: "Les actions sensibles ouvrent le flux Account AV partage.", title: "Securite du compte" },
    preferences: { ...en.preferences, languageDetail: "Choisissez la langue utilisee par Tune AV.", languageTitle: "Langue de l'app", subtitle: "Choisissez comment Tune AV s'affiche sur cet appareil.", themeDetail: "Choisissez si Tune AV suit le systeme ou utilise un theme fixe ici.", themeOptions: { dark: "Sombre", light: "Clair", system: "Systeme" }, themeTitle: "Apparence", title: "Preferences de l'app" },
    tune: { ...en.tune, countryDetail: "Le pays prefere sert de flux initial quand il est disponible.", countryTitle: "Pays des stations", discoveryDetail: "Musique priorise les stations avec metadonnees de titres; toute la radio garde un flux plus large.", discoveryOptions: { allRadio: "Toute la radio", music: "Musique" }, discoveryTitle: "Mode de decouverte", externalSearchDetail: "Choisissez le moteur pour les liens d'info publique et de paroles.", externalSearchOptions: { bing: "Bing", duckduckgo: "DuckDuckGo", google: "Google" }, externalSearchTitle: "Moteur de recherche", genreDetail: "Le genre prefere sert de point de depart.", genreTitle: "Genre prefere", subtitle: "Tune AV garde ces preferences localement dans ce navigateur.", title: "Preferences d'ecoute" },
    local: { ...en.local, delete: { confirmDetail: "Favoris, recents, decouvertes, feedback, sessions en attente et preferences Tune AV de ce navigateur seront supprimes. Cela ne supprime pas votre compte Apps AV.", confirmTitle: "Supprimer les donnees locales Tune AV", detail: (count: number) => `Supprime ${count} elements locaux de ce navigateur.`, empty: "Il n'y a aucune donnee locale Tune AV a supprimer.", title: "Supprimer les donnees locales" }, libraryDetail: "Free garde favoris, recents, decouvertes et feedback dans ce navigateur quand la sync cloud n'est pas active.", libraryTitle: "Bibliotheque locale", subtitle: "Les donnees locales Tune AV restent dans ce navigateur sauf si Pro sync est disponible.", syncDetail: "Pro cloud sync couvre favoris et decouvertes enregistrees avec le contrat app-data existant.", syncTitle: "Limite de sync", title: "Sur cet appareil" },
    help: { ...en.help, deleteDetail: "Ouvrir la page partagee de suppression du compte.", deleteTitle: "Supprimer le compte", openSourceDetail: "Tune AV est maintenue comme app produit open-source.", openSourceTitle: "Projet open-source", privacyDetail: "Consultez comment Tune AV gere vos donnees.", privacyTitle: "Politique de confidentialite", sourceCodeDetail: "Ouvrez le depot, les issues et le contexte de contribution.", sourceCodeTitle: "Code source", subtitle: "Ouvrez support, confidentialite, termes, suppression et code source.", supportDetail: "Ouvrir le support Tune AV.", supportTitle: "Contacter le support", termsDetail: "Consultez les termes applicables a Tune AV.", termsTitle: "Conditions du service", title: "Aide et legal" }
  }
};
