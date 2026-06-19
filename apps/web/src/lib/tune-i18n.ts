import { useAppsAvLocale, type AppsAvLocale, type AppsAvProductLink } from "@avalsys/apps-av-web";
import { caES } from "@clerk/localizations/ca-ES";
import { deDE } from "@clerk/localizations/de-DE";
import { enUS } from "@clerk/localizations/en-US";
import { esES } from "@clerk/localizations/es-ES";
import { frFR } from "@clerk/localizations/fr-FR";

const en = {
  account: {
    signInTitle: "Sign in to Tune AV",
    signInSubtitle: "Welcome back. Sign in to keep your stations, library, and Avi guidance connected."
  },
  avi: {
    body: "Avi helps keep listening choices calm: tune a station, save what fits, and return to the right mood without rebuilding the queue.",
    cards: [
      { text: "Turn a broad mood into a focused listening direction before you press play.", title: "Shape the session" },
      { text: "Keep stations and saved picks readable, so the next listen stays close.", title: "Keep context" },
      { text: "Use taste signals from your real listening instead of starting from a blank list.", title: "Tune with memory" }
    ],
    libraryCta: "Open library",
    radioCta: "Start listening",
    title: "A calm guide for the next station."
  },
  config: {
    body: "Run the web app through the Varlock wrapper so Account AV configuration is available. The public home is informational; product routes require login.",
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
    aviBody: [
      "Start from a mood, station, or saved favorite.",
      "Keep listening history and library actions behind your AV account.",
      "Let Avi keep the next session focused instead of noisy."
    ],
    aviTitle: "Avi keeps the signal clear",
    body: "Tune into stations, keep a lightweight library, and let Avi help shape the next listening session.",
    cta: "Start listening",
    items: [
      { label: "Stations", value: "Find a listening lane" },
      { label: "Library", value: "Save what fits" },
      { label: "Avi", value: "Get calm listening guidance" }
    ],
    title: "Your listening room is ready."
  },
  library: {
    add: "Add station",
    body: "Saved stations and favorites will live here once you start listening on the signed-in web app.",
    emptyBody: "Open Radio, choose a direction, and Tune AV will keep the useful stations and favorites in your library.",
    emptyTitle: "Start by saving a station.",
    filters: ["All", "Stations", "Favorites", "Recent", "Archived"],
    hints: [
      { text: "Keep the stations that work for focus, rest, and discovery.", title: "Stations" },
      { text: "Save tracks or moments that should be easy to find again.", title: "Favorites" },
      { text: "Move old sessions out of view without losing context.", title: "Archive" }
    ],
    kicker: "Library",
    title: "Saved listening, ready for the next session."
  },
  listen: {
    accountBody: "Listening, library, and Avi guidance stay connected to your AV account while Tune AV services come online.",
    body: "The web port starts with protected listening surfaces. Streaming and station sync stay behind the account boundary.",
    cta: "Protected by AV account",
    title: "Tune a station from your signed-in account.",
    panels: [
      { body: "Pick a focus before playback so recommendations stay useful.", title: "Session mood" },
      { body: "Stations are prepared for signed-in sync rather than anonymous state.", title: "Station queue" },
      { body: "Avi can guide the next station from saved context once services are connected.", title: "Avi guidance" }
    ]
  },
  login: {
    aviGuidance: "Avi guidance",
    cardBody: "Keep stations, favorites, and listening context attached to your AV account.",
    cardTitle: "Continue from your signal",
    cta: "Sign in",
    heroBody: "Sign in to keep listening history, saved stations, and Avi guidance connected wherever Tune AV is available.",
    heroTitle: "Radio calm, account connected.",
    intro: "Tune AV keeps radio-style listening focused, private, and available from your signed-in AV account.",
    mapBody: "The web experience uses Tune AV's radio mood: dark panels, clean signal lines, and Avi close to the session.",
    mapTitle: "A listening room for focused sessions.",
    notebook: "Saved library",
    listen: "Station tuning"
  },
  nav: {
    avi: "Avi",
    aviLabel: "Open Avi guidance",
    home: "Home",
    homeLabel: "Tune AV home",
    library: "Library",
    listen: "Radio",
    mobileNavigation: "Mobile navigation",
    music: "Music",
    openNavigation: "Open navigation",
    primaryNavigation: "Primary navigation",
    settings: "Settings"
  },
  protected: {
    body: "Sign in to open listening, library, and Avi routes. Tune AV web keeps product functionality behind your AV account.",
    cta: "Sign in",
    title: "Your listening stays behind your AV account."
  },
  signIn: {
    aviPanelBody: "Avi keeps the next station calm and intentional.",
    body: "Sign in to connect Tune AV listening, saved stations, and Avi recommendations with your AV account.",
    continue: "Continue",
    signedIn: "You are signed in.",
    title: "Tune AV follows your signal."
  }
};

const es: typeof en = {
  account: {
    signInTitle: "Inicia sesión en Tune AV",
    signInSubtitle: "Vuelve a entrar para mantener conectadas tus emisoras, biblioteca y guía de Avi."
  },
  avi: {
    body: "Avi ayuda a mantener la escucha tranquila: sintoniza una emisora, guarda lo que encaja y vuelve al ambiente adecuado sin rehacer la cola.",
    cards: [
      { text: "Convierte un estado de ánimo amplio en una dirección clara antes de reproducir.", title: "Define la sesión" },
      { text: "Mantén emisoras y elementos guardados legibles para que la próxima escucha quede cerca.", title: "Mantén contexto" },
      { text: "Usa señales de tu escucha real en vez de empezar desde una lista vacía.", title: "Sintoniza con memoria" }
    ],
    libraryCta: "Abrir biblioteca",
    radioCta: "Empezar a escuchar",
    title: "Una guía tranquila para la próxima emisora."
  },
  config: {
    body: "Ejecuta la web con el wrapper de Varlock para que la configuración de Account AV esté disponible. La home pública es informativa; las rutas de producto requieren login.",
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
    aviBody: ["Empieza desde un ambiente, emisora o favorito.", "Mantén historial y biblioteca detrás de tu cuenta AV.", "Deja que Avi enfoque la siguiente sesión."],
    aviTitle: "Avi mantiene clara la señal",
    body: "Sintoniza emisoras, mantén una biblioteca ligera y deja que Avi ayude a preparar la próxima sesión.",
    cta: "Empezar a escuchar",
    items: [
      { label: "Emisoras", value: "Encuentra una línea de escucha" },
      { label: "Biblioteca", value: "Guarda lo que encaja" },
      { label: "Avi", value: "Recibe guía tranquila" }
    ],
    title: "Tu sala de escucha está lista."
  },
  library: {
    add: "Añadir emisora",
    body: "Las emisoras y favoritos guardados vivirán aquí cuando empieces a escuchar con sesión iniciada.",
    emptyBody: "Abre Escuchar, elige una dirección y Tune AV guardará las emisoras útiles en tu biblioteca.",
    emptyTitle: "Empieza guardando una emisora.",
    filters: ["Todo", "Emisoras", "Favoritos", "Reciente", "Archivado"],
    hints: [
      { text: "Conserva emisoras para concentración, descanso y descubrimiento.", title: "Emisoras" },
      { text: "Guarda pistas o momentos que quieras encontrar de nuevo.", title: "Favoritos" },
      { text: "Aparta sesiones antiguas sin perder contexto.", title: "Archivo" }
    ],
    kicker: "Biblioteca",
    title: "Escucha guardada para la próxima sesión."
  },
  listen: {
    accountBody: "Escucha, biblioteca y guía de Avi permanecen conectadas a tu cuenta AV mientras los servicios de Tune AV se activan.",
    body: "El port web empieza con superficies protegidas de escucha. Streaming y sincronización quedan detrás de la cuenta.",
    cta: "Protegido por cuenta AV",
    title: "Sintoniza una emisora desde tu cuenta iniciada.",
    panels: [
      { body: "Elige enfoque antes de reproducir para que las recomendaciones sigan siendo útiles.", title: "Ambiente" },
      { body: "Las emisoras se preparan para sincronización con sesión, no para estado anónimo.", title: "Cola de emisoras" },
      { body: "Avi podrá guiar la próxima emisora desde contexto guardado cuando los servicios estén conectados.", title: "Guía de Avi" }
    ]
  },
  login: {
    aviGuidance: "Guía de Avi",
    cardBody: "Mantén emisoras, favoritos y contexto de escucha unidos a tu cuenta AV.",
    cardTitle: "Continúa desde tu señal",
    cta: "Iniciar sesión",
    heroBody: "Inicia sesión para mantener historial, emisoras guardadas y guía de Avi conectados.",
    heroTitle: "Radio tranquila, cuenta conectada.",
    intro: "Tune AV mantiene la escucha tipo radio enfocada, privada y disponible desde tu cuenta AV.",
    mapBody: "La web usa el tono de radio de Tune AV: paneles oscuros, líneas limpias y Avi cerca de la sesión.",
    mapTitle: "Una sala de escucha para sesiones enfocadas.",
    notebook: "Biblioteca guardada",
    listen: "Sintonización"
  },
  nav: {
    avi: "Avi",
    aviLabel: "Abrir guía de Avi",
    home: "Inicio",
    homeLabel: "Inicio de Tune AV",
    library: "Biblioteca",
    listen: "Escuchar",
    mobileNavigation: "Navegación móvil",
    music: "Música",
    openNavigation: "Abrir navegación",
    primaryNavigation: "Navegación principal",
    settings: "Ajustes"
  },
  protected: {
    body: "Inicia sesión para abrir escucha, biblioteca y Avi. Tune AV web mantiene la funcionalidad de producto detrás de tu cuenta AV.",
    cta: "Iniciar sesión",
    title: "Tu escucha queda detrás de tu cuenta AV."
  },
  signIn: {
    aviPanelBody: "Avi mantiene la próxima emisora tranquila e intencional.",
    body: "Inicia sesión para conectar escucha, emisoras guardadas y recomendaciones de Avi con tu cuenta AV.",
    continue: "Continuar",
    signedIn: "Has iniciado sesión.",
    title: "Tune AV sigue tu señal."
  }
};

const ca: typeof en = {
  ...es,
  account: { signInTitle: "Inicia sessio a Tune AV", signInSubtitle: "Torna-hi per mantenir connectades les emissores, la biblioteca i la guia d'Avi." },
  avi: {
    body: "Avi ajuda a mantenir l'escolta tranquil.la: sintonitza una emissora, desa el que encaixa i torna a l'ambient adequat sense refer la cua.",
    cards: [
      { text: "Converteix un estat d'anim ampli en una direccio clara abans de reproduir.", title: "Defineix la sessio" },
      { text: "Mantingues emissores i elements desats llegibles per tenir a prop la propera escolta.", title: "Mantingues context" },
      { text: "Fes servir senyals de la teva escolta real en lloc de comencar des d'una llista buida.", title: "Sintonitza amb memoria" }
    ],
    libraryCta: "Obre la biblioteca",
    radioCta: "Comenca a escoltar",
    title: "Una guia tranquil.la per a la propera emissora."
  },
  footer: { deleteAccount: "Eliminar compte", language: "Idioma", privacy: "Privacitat", support: "Suport", terms: "Termes" },
  home: {
    aviBody: ["Comenca des d'un ambient, emissora o favorit.", "Mantingues historial i biblioteca darrere del teu compte AV.", "Deixa que Avi enfoqui la propera sessio."],
    aviTitle: "Avi mante clara la senyal",
    body: "Sintonitza emissores, mantingues una biblioteca lleugera i deixa que Avi ajudi a preparar la propera sessio.",
    cta: "Comenca a escoltar",
    items: [
      { label: "Emissores", value: "Troba una linia d'escolta" },
      { label: "Biblioteca", value: "Desa el que encaixa" },
      { label: "Avi", value: "Rep guia tranquil.la" }
    ],
    title: "La teva sala d'escolta esta a punt."
  },
  library: {
    ...es.library,
    add: "Afegeix emissora",
    body: "Les emissores i favorits desats viuran aqui quan comencis a escoltar amb sessio iniciada.",
    emptyBody: "Obre Escoltar, tria una direccio i Tune AV desara les emissores utils a la biblioteca.",
    emptyTitle: "Comenca desant una emissora.",
    filters: ["Tot", "Emissores", "Favorits", "Recents", "Arxivat"],
    hints: [
      { text: "Conserva emissores per a concentracio, descans i descobriment.", title: "Emissores" },
      { text: "Desa pistes o moments que vulguis trobar de nou.", title: "Favorits" },
      { text: "Aparta sessions antigues sense perdre context.", title: "Arxiu" }
    ],
    kicker: "Biblioteca",
    title: "Escolta desada per a la propera sessio."
  },
  listen: {
    accountBody: "Escolta, biblioteca i guia d'Avi romanen connectades al teu compte AV mentre els serveis de Tune AV s'activen.",
    body: "El port web comenca amb superficies protegides d'escolta. Streaming i sincronitzacio queden darrere del compte.",
    cta: "Protegit pel compte AV",
    title: "Sintonitza una emissora des del teu compte iniciat.",
    panels: [
      { body: "Tria enfocament abans de reproduir per mantenir recomanacions utils.", title: "Ambient" },
      { body: "Les emissores es preparen per sincronitzacio amb sessio, no per estat anonim.", title: "Cua d'emissores" },
      { body: "Avi podra guiar la propera emissora des del context desat quan els serveis estiguin connectats.", title: "Guia d'Avi" }
    ]
  },
  login: {
    aviGuidance: "Guia d'Avi",
    cardBody: "Mantingues emissores, favorits i context d'escolta units al teu compte AV.",
    cardTitle: "Continua des de la teva senyal",
    cta: "Inicia sessio",
    heroBody: "Inicia sessio per mantenir historial, emissores desades i guia d'Avi connectats.",
    heroTitle: "Radio tranquil.la, compte connectat.",
    intro: "Tune AV mante l'escolta tipus radio enfocada, privada i disponible des del teu compte AV.",
    mapBody: "La web usa el to de radio de Tune AV: panells foscos, linies netes i Avi a prop de la sessio.",
    mapTitle: "Una sala d'escolta per a sessions enfocades.",
    notebook: "Biblioteca desada",
    listen: "Sintonitzacio"
  },
  nav: { ...es.nav, home: "Inici", listen: "Escoltar", music: "Musica", openNavigation: "Obre la navegacio", primaryNavigation: "Navegacio principal", mobileNavigation: "Navegacio mobil", settings: "Ajustos" },
  protected: { body: "Inicia sessio per obrir escolta, biblioteca i Avi. Tune AV web mante la funcionalitat de producte darrere del teu compte AV.", cta: "Inicia sessio", title: "La teva escolta queda darrere del compte AV." },
  signIn: { aviPanelBody: "Avi mante la propera emissora tranquil.la i intencional.", body: "Inicia sessio per connectar escolta, emissores desades i recomanacions d'Avi amb el teu compte AV.", continue: "Continua", signedIn: "Has iniciat sessio.", title: "Tune AV segueix la teva senyal." }
};

const de: typeof en = {
  ...en,
  account: { signInTitle: "Bei Tune AV anmelden", signInSubtitle: "Melde dich an, damit Sender, Bibliothek und Avi-Hilfe verbunden bleiben." },
  avi: {
    body: "Avi haelt Hoerentscheidungen ruhig: Sender waehlen, Passendes speichern und ohne neue Warteschlange zur richtigen Stimmung zurueckkehren.",
    cards: [
      { text: "Forme eine breite Stimmung zu einer klaren Hoerrichtung, bevor du abspielst.", title: "Sitzung formen" },
      { text: "Halte Sender und gespeicherte Auswahl lesbar, damit die naechste Wiedergabe nah bleibt.", title: "Kontext behalten" },
      { text: "Nutze Geschmackssignale aus deinem echten Hoeren statt einer leeren Liste.", title: "Mit Gedaechtnis stimmen" }
    ],
    libraryCta: "Bibliothek oeffnen",
    radioCta: "Hoeren starten",
    title: "Eine ruhige Hilfe fuer den naechsten Sender."
  },
  config: { body: "Starte die Web-App ueber den Varlock-Wrapper, damit die Account AV Konfiguration verfuegbar ist. Die oeffentliche Startseite ist informativ; Produktrouten erfordern Anmeldung.", eyebrow: "Konfiguration erforderlich", title: "Tune AV Web braucht Clerk-Konfiguration." },
  footer: { deleteAccount: "Konto loeschen", language: "Sprache", privacy: "Datenschutz", support: "Hilfe", terms: "Bedingungen" },
  home: { aviBody: ["Beginne mit Stimmung, Sender oder gespeichertem Favoriten.", "Halte Hoerverlauf und Bibliotheksaktionen hinter deinem AV-Konto.", "Lass Avi die naechste Sitzung fokussiert statt laut halten."], aviTitle: "Avi haelt das Signal klar", body: "Stimme Sender ab, fuehre eine leichte Bibliothek und lass Avi die naechste Hoersitzung vorbereiten.", cta: "Hoeren starten", items: [{ label: "Sender", value: "Eine Hoerrichtung finden" }, { label: "Bibliothek", value: "Passendes speichern" }, { label: "Avi", value: "Ruhige Hoerhilfe erhalten" }], title: "Dein Hoerraum ist bereit." },
  library: {
    add: "Sender hinzufuegen",
    body: "Gespeicherte Sender und Favoriten erscheinen hier, sobald du angemeldet hoerst.",
    emptyBody: "Oeffne Hoeren, waehle eine Richtung, und Tune AV haelt die passenden Sender und Favoriten in deiner Bibliothek.",
    emptyTitle: "Beginne mit einem gespeicherten Sender.",
    filters: ["Alle", "Sender", "Favoriten", "Zuletzt", "Archiviert"],
    hints: [
      { text: "Bewahre Sender fuer Fokus, Ruhe und Entdeckung auf.", title: "Sender" },
      { text: "Speichere Titel oder Momente, die leicht wiederzufinden sein sollen.", title: "Favoriten" },
      { text: "Verschiebe alte Sitzungen aus dem Blick, ohne Kontext zu verlieren.", title: "Archiv" }
    ],
    kicker: "Bibliothek",
    title: "Gespeichertes Hoeren fuer die naechste Sitzung."
  },
  listen: {
    accountBody: "Hoeren, Bibliothek und Avi-Hilfe bleiben mit deinem AV-Konto verbunden, waehrend Tune AV Dienste online gehen.",
    body: "Der Web-Port startet mit geschuetzten Hoerflaechen. Streaming und Sendersync bleiben hinter dem Konto.",
    cta: "Durch AV-Konto geschuetzt",
    title: "Stimme einen Sender mit deinem angemeldeten Konto ab.",
    panels: [
      { body: "Waehle vor der Wiedergabe einen Fokus, damit Empfehlungen nuetzlich bleiben.", title: "Sitzungsstimmung" },
      { body: "Sender werden fuer angemeldete Synchronisierung vorbereitet, nicht fuer anonymen Zustand.", title: "Senderliste" },
      { body: "Avi kann den naechsten Sender aus gespeichertem Kontext fuehren, sobald die Dienste verbunden sind.", title: "Avi-Hilfe" }
    ]
  },
  login: { aviGuidance: "Avi-Hilfe", cardBody: "Halte Sender, Favoriten und Hoerkontext mit deinem AV-Konto verbunden.", cardTitle: "Weiter von deinem Signal", cta: "Anmelden", heroBody: "Melde dich an, damit Hoerverlauf, gespeicherte Sender und Avi-Hilfe verbunden bleiben.", heroTitle: "Ruhiges Radio, verbundenes Konto.", intro: "Tune AV haelt radioartiges Hoeren fokussiert, privat und in deinem AV-Konto verfuegbar.", mapBody: "Die Web-Erfahrung nutzt Tune AVs Radiostimmung: dunkle Flaechen, klare Signallinien und Avi nah an der Sitzung.", mapTitle: "Ein Hoerraum fuer fokussierte Sitzungen.", notebook: "Gespeicherte Bibliothek", listen: "Senderabstimmung" },
  nav: { ...en.nav, aviLabel: "Avi-Hilfe oeffnen", home: "Start", homeLabel: "Tune AV Start", library: "Bibliothek", listen: "Hoeren", music: "Musik", openNavigation: "Navigation oeffnen", primaryNavigation: "Hauptnavigation", mobileNavigation: "Mobile Navigation", settings: "Einstellungen" },
  protected: { body: "Melde dich an, um Hoeren, Bibliothek und Avi zu oeffnen. Tune AV Web haelt Produktfunktionen hinter deinem AV-Konto.", cta: "Anmelden", title: "Dein Hoeren bleibt hinter deinem AV-Konto." },
  signIn: { aviPanelBody: "Avi haelt den naechsten Sender ruhig und bewusst.", body: "Melde dich an, um Tune AV Hoeren, gespeicherte Sender und Avi-Empfehlungen mit deinem AV-Konto zu verbinden.", continue: "Weiter", signedIn: "Du bist angemeldet.", title: "Tune AV folgt deinem Signal." }
};

const fr: typeof en = {
  ...en,
  account: { signInTitle: "Connexion a Tune AV", signInSubtitle: "Connectez-vous pour garder stations, bibliotheque et aide d'Avi synchronisees." },
  avi: {
    body: "Avi garde l'ecoute calme : choisir une station, enregistrer ce qui convient et revenir a la bonne ambiance sans reconstruire la file.",
    cards: [
      { text: "Transformez une humeur large en direction d'ecoute claire avant de lancer.", title: "Former la session" },
      { text: "Gardez stations et choix enregistres lisibles pour rapprocher la prochaine ecoute.", title: "Garder le contexte" },
      { text: "Utilisez les signaux de votre vraie ecoute au lieu de repartir d'une liste vide.", title: "Accorder avec memoire" }
    ],
    libraryCta: "Ouvrir la bibliotheque",
    radioCta: "Commencer l'ecoute",
    title: "Un guide calme pour la prochaine station."
  },
  config: { body: "Lancez l'app web avec le wrapper Varlock pour rendre la configuration Account AV disponible. L'accueil public est informatif; les routes produit demandent une connexion.", eyebrow: "Configuration requise", title: "Tune AV Web a besoin de la configuration Clerk." },
  footer: { deleteAccount: "Supprimer le compte", language: "Langue", privacy: "Confidentialite", support: "Assistance", terms: "Conditions" },
  home: { aviBody: ["Commencez par une humeur, une station ou un favori.", "Gardez historique d'ecoute et actions de bibliotheque derriere votre compte AV.", "Laissez Avi garder la prochaine session focalisee plutot que bruyante."], aviTitle: "Avi garde le signal clair", body: "Accordez des stations, gardez une bibliotheque legere et laissez Avi preparer la prochaine session.", cta: "Commencer l'ecoute", items: [{ label: "Stations", value: "Trouver une voie d'ecoute" }, { label: "Bibliotheque", value: "Enregistrer ce qui convient" }, { label: "Avi", value: "Recevoir une aide calme" }], title: "Votre salle d'ecoute est prete." },
  library: {
    add: "Ajouter une station",
    body: "Les stations et favoris enregistres apparaitront ici lorsque vous ecouterez connecte.",
    emptyBody: "Ouvrez Ecouter, choisissez une direction, et Tune AV gardera les stations et favoris utiles dans votre bibliotheque.",
    emptyTitle: "Commencez par enregistrer une station.",
    filters: ["Tout", "Stations", "Favoris", "Recents", "Archive"],
    hints: [
      { text: "Gardez les stations utiles pour la concentration, le repos et la decouverte.", title: "Stations" },
      { text: "Enregistrez les titres ou moments que vous voudrez retrouver facilement.", title: "Favoris" },
      { text: "Mettez les anciennes sessions de cote sans perdre le contexte.", title: "Archive" }
    ],
    kicker: "Bibliotheque",
    title: "Ecoute enregistree pour la prochaine session."
  },
  listen: {
    accountBody: "L'ecoute, la bibliotheque et l'aide d'Avi restent reliees a votre compte AV pendant l'activation des services Tune AV.",
    body: "Le port web commence par des surfaces d'ecoute protegees. Streaming et synchronisation restent derriere le compte.",
    cta: "Protege par le compte AV",
    title: "Accordez une station depuis votre compte connecte.",
    panels: [
      { body: "Choisissez un focus avant la lecture pour garder des recommandations utiles.", title: "Ambiance de session" },
      { body: "Les stations sont preparees pour une synchronisation connectee, pas pour un etat anonyme.", title: "File de stations" },
      { body: "Avi pourra guider la prochaine station depuis le contexte enregistre lorsque les services seront connectes.", title: "Aide d'Avi" }
    ]
  },
  login: { aviGuidance: "Aide d'Avi", cardBody: "Gardez stations, favoris et contexte d'ecoute lies a votre compte AV.", cardTitle: "Continuer depuis votre signal", cta: "Se connecter", heroBody: "Connectez-vous pour garder historique, stations enregistrees et aide d'Avi synchronises.", heroTitle: "Radio calme, compte connecte.", intro: "Tune AV garde l'ecoute type radio concentree, privee et disponible depuis votre compte AV.", mapBody: "L'experience web reprend l'ambiance radio de Tune AV : panneaux sombres, lignes de signal nettes et Avi proche de la session.", mapTitle: "Une salle d'ecoute pour les sessions focalisees.", notebook: "Bibliotheque enregistree", listen: "Accord de station" },
  nav: { ...en.nav, aviLabel: "Ouvrir l'aide d'Avi", home: "Accueil", homeLabel: "Accueil Tune AV", library: "Bibliotheque", listen: "Ecouter", music: "Musique", openNavigation: "Ouvrir la navigation", primaryNavigation: "Navigation principale", mobileNavigation: "Navigation mobile", settings: "Reglages" },
  protected: { body: "Connectez-vous pour ouvrir l'ecoute, la bibliotheque et Avi. Tune AV web garde les fonctions produit derriere votre compte AV.", cta: "Se connecter", title: "Votre ecoute reste derriere votre compte AV." },
  signIn: { aviPanelBody: "Avi garde la prochaine station calme et intentionnelle.", body: "Connectez-vous pour relier l'ecoute Tune AV, les stations enregistrees et les recommandations d'Avi a votre compte AV.", continue: "Continuer", signedIn: "Vous etes connecte.", title: "Tune AV suit votre signal." }
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
    { href: localizedTunePath("/listen", locale), label: text.nav.listen },
    { href: localizedTunePath("/library", locale), label: text.nav.library },
    { href: localizedTunePath("/music", locale), label: text.nav.music },
    { href: localizedTunePath("/avi", locale), label: text.nav.avi },
    { href: localizedTunePath("/settings", locale), label: text.nav.settings }
  ];
}

export function useTuneShellLabels() {
  const text = useTuneText();

  return {
    assistant: text.nav.aviLabel,
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
