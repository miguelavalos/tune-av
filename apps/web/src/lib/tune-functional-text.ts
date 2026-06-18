import type { AppsAvLocale } from "@avalsys/apps-av-web";

const en = {
  listen: {
    allRadio: "All radio",
    body: "Search by station, country, genre, or browse popular feeds. Playback starts only from your action.",
    countries: { CA: "Canada", DE: "Germany", ES: "Spain", FR: "France", GB: "United Kingdom", US: "United States", worldwide: "Worldwide" },
    emptyBody: "Try a broader query, clear the country filter, or browse a genre.",
    emptyTitle: "No stations yet.",
    errorTitle: "Could not load stations.",
    genre: "Genre",
    genreAll: "All genres",
    loadMore: "Load more",
    music: "Music",
    possibleMatches: "possible matches",
    retry: "Retry",
    search: "Search",
    searchPlaceholder: "Search station, city, genre",
    stationResults: "Station results",
    subtitle: "Curated from the Tune AV station feed",
    title: "Find and play live stations."
  },
  library: {
    add: "Add station",
    body: "Favorites, recents, tuned stations, and music stations are local-first. Pro sync uses the existing app-data contract when available.",
    chooseBody: "Use the overview metrics to inspect saved, recent, tuned, or music-focused stations.",
    chooseTitle: "Choose a library view.",
    emptyBody: "Play and save stations from Radio to fill this section.",
    emptyTitle: "No stations in this view.",
    filter: "Filter library",
    modes: { favorites: "Favorites", music: "Music stations", overview: "Overview", recents: "Recent stations", tuned: "Tuned stations" },
    metrics: { favorites: "Favorites", music: "Music", recent: "Recent", tuned: "Tuned" },
    stationCount: "stations",
    title: "Saved listening and station memory."
  },
  music: {
    body: "Track discovery uses now-playing metadata when available. External actions open normal search destinations and respect Free/Pro daily limits.",
    emptyBody: "Play stations with song metadata, then save or hide tracks from this view.",
    emptyTitle: "No discoveries yet.",
    filter: "Filter songs or artists",
    findStations: "Find stations",
    modes: { artists: "Artists", hidden: "Hidden", saved: "Saved", songs: "Songs" },
    title: "Discovered and saved tracks."
  },
  avi: {
    bodyEmpty: "Play or save a station first so Avi can rank real listening context.",
    bodyReady: "Recommendations are scored from favorites, recents, feedback, station quality, and music discovery metadata.",
    emptyBody: "Open Radio, play a station, save a favorite, or add feedback. Avi will rank from those signals.",
    emptyTitle: "No guidance yet.",
    labels: { favorites: "Favorites", recents: "Recents", savedTracks: "Saved tracks" },
    library: "Open library",
    note: "No new AI service is promised here; this uses local/backend station signals already available to the web app.",
    recommended: "Recommended next",
    search: "Search stations",
    title: "Guidance from your station memory."
  },
  settings: {
    account: "Account",
    accountFallback: "Tune AV listener",
    deleteAccount: "Delete account",
    emailFallback: "Signed in with Account AV",
    library: "Open library",
    localSync: "Local-first on Free",
    manage: "Manage in Account AV",
    navigation: "Navigation",
    noCloud: "No cloud activity yet.",
    plan: "Plan",
    planBody: "Web billing is not implemented here. Plan management and upgrades must go through Account AV/account management unless a web billing contract is added.",
    privacy: "Privacy",
    radio: "Open radio",
    signOut: "Sign out is available from the Account AV user menu.",
    status: "Status",
    support: "Support",
    supportLegal: "Support and legal",
    sync: "Sync",
    syncAvailable: "Cloud sync available",
    syncNow: "Synchronize now",
    terms: "Terms"
  }
};

export const tuneFunctionalText: Record<AppsAvLocale, typeof en> = {
  en,
  es: {
    listen: { ...en.listen, allRadio: "Toda la radio", body: "Busca por emisora, pais, genero o explora feeds populares. La reproduccion empieza solo con tu accion.", countries: { CA: "Canada", DE: "Alemania", ES: "Espana", FR: "Francia", GB: "Reino Unido", US: "Estados Unidos", worldwide: "Todo el mundo" }, emptyBody: "Prueba una busqueda mas amplia, limpia el pais o explora un genero.", emptyTitle: "Aun no hay emisoras.", errorTitle: "No se pudieron cargar emisoras.", genre: "Genero", genreAll: "Todos", loadMore: "Cargar mas", music: "Musica", possibleMatches: "coincidencias posibles", retry: "Reintentar", search: "Buscar", searchPlaceholder: "Buscar emisora, ciudad, genero", stationResults: "Resultados de emisoras", subtitle: "Seleccionado desde el feed de emisoras de Tune AV", title: "Busca y reproduce emisoras en directo." },
    library: { ...en.library, add: "Anadir emisora", body: "Favoritos, recientes, emisoras ajustadas y emisoras musicales son local-first. La sincronizacion Pro usa el contrato app-data existente cuando esta disponible.", chooseBody: "Usa las metricas para revisar guardadas, recientes, ajustadas o emisoras de musica.", chooseTitle: "Elige una vista de biblioteca.", emptyBody: "Reproduce y guarda emisoras desde Escuchar para llenar esta seccion.", emptyTitle: "No hay emisoras en esta vista.", filter: "Filtrar biblioteca", modes: { favorites: "Favoritos", music: "Emisoras de musica", overview: "Resumen", recents: "Emisoras recientes", tuned: "Emisoras ajustadas" }, metrics: { favorites: "Favoritos", music: "Musica", recent: "Recientes", tuned: "Ajustadas" }, stationCount: "emisoras", title: "Escucha guardada y memoria de emisoras." },
    music: { ...en.music, body: "El descubrimiento usa metadata now-playing cuando esta disponible. Las acciones externas abren busquedas normales y respetan limites Free/Pro.", emptyBody: "Reproduce emisoras con metadata de canciones, luego guarda u oculta pistas desde esta vista.", emptyTitle: "Aun no hay descubrimientos.", filter: "Filtrar canciones o artistas", findStations: "Buscar emisoras", modes: { artists: "Artistas", hidden: "Ocultas", saved: "Guardadas", songs: "Canciones" }, title: "Pistas descubiertas y guardadas." },
    avi: { ...en.avi, bodyEmpty: "Reproduce o guarda una emisora primero para que Avi pueda ordenar contexto real.", bodyReady: "Las recomendaciones se puntuan con favoritos, recientes, feedback, calidad de emisora y metadata musical.", emptyBody: "Abre Escuchar, reproduce una emisora, guarda un favorito o anade feedback. Avi ordenara desde esas senales.", emptyTitle: "Aun no hay guia.", labels: { favorites: "Favoritos", recents: "Recientes", savedTracks: "Pistas guardadas" }, library: "Abrir biblioteca", note: "Aqui no se promete un servicio nuevo de IA; usa senales locales/backend ya disponibles en la web.", recommended: "Siguiente recomendado", search: "Buscar emisoras", title: "Guia desde tu memoria de emisoras." },
    settings: { ...en.settings, account: "Cuenta", accountFallback: "Oyente de Tune AV", deleteAccount: "Eliminar cuenta", emailFallback: "Sesion iniciada con Account AV", library: "Abrir biblioteca", localSync: "Local-first en Free", manage: "Gestionar en Account AV", navigation: "Navegacion", noCloud: "Aun no hay actividad cloud.", plan: "Plan", planBody: "El billing web no esta implementado aqui. La gestion de plan y upgrades debe pasar por Account AV/account management salvo que se anada un contrato de billing web.", privacy: "Privacidad", radio: "Abrir radio", signOut: "Cerrar sesion esta disponible en el menu de usuario de Account AV.", status: "Estado", support: "Soporte", supportLegal: "Soporte y legal", sync: "Sincronizacion", syncAvailable: "Sincronizacion cloud disponible", syncNow: "Sincronizar ahora", terms: "Terminos" }
  },
  ca: {
    ...en,
    listen: { ...en.listen, allRadio: "Tota la radio", music: "Musica", search: "Buscar", title: "Busca i reprodueix emissores en directe.", searchPlaceholder: "Buscar emissora, ciutat, genere", stationResults: "Resultats d'emissores", subtitle: "Seleccionat des del feed d'emissores de Tune AV", errorTitle: "No s'han pogut carregar emissores.", retry: "Reintenta", emptyTitle: "Encara no hi ha emissores.", emptyBody: "Prova una cerca mes ampla, neteja el pais o explora un genere.", loadMore: "Carrega mes" },
    library: { ...en.library, add: "Afegeix emissora", body: "Favorits, recents, emissores ajustades i emissores musicals son local-first. La sincronitzacio Pro usa el contracte app-data existent quan esta disponible.", chooseBody: "Usa les metriques per revisar desades, recents, ajustades o emissores de musica.", chooseTitle: "Tria una vista de biblioteca.", emptyBody: "Reprodueix i desa emissores des d'Escoltar per omplir aquesta seccio.", emptyTitle: "No hi ha emissores en aquesta vista.", filter: "Filtra biblioteca", modes: { favorites: "Favorits", music: "Emissores de musica", overview: "Resum", recents: "Emissores recents", tuned: "Emissores ajustades" }, metrics: { favorites: "Favorits", music: "Musica", recent: "Recents", tuned: "Ajustades" }, stationCount: "emissores", title: "Escolta desada i memoria d'emissores." },
    music: { ...en.music, body: "El descobriment usa metadata now-playing quan esta disponible. Les accions externes obren cerques normals i respecten limits Free/Pro.", emptyBody: "Reprodueix emissores amb metadata de cancons, despres desa o amaga pistes des d'aquesta vista.", emptyTitle: "Encara no hi ha descobriments.", filter: "Filtra cancons o artistes", findStations: "Buscar emissores", modes: { artists: "Artistes", hidden: "Amagades", saved: "Desades", songs: "Cancons" }, title: "Pistes descobertes i desades." },
    avi: { ...en.avi, bodyEmpty: "Reprodueix o desa una emissora primer perque Avi pugui ordenar context real.", bodyReady: "Les recomanacions es puntuen amb favorits, recents, feedback, qualitat d'emissora i metadata musical.", emptyBody: "Obre Escoltar, reprodueix una emissora, desa un favorit o afegeix feedback. Avi ordenara des d'aquests senyals.", emptyTitle: "Encara no hi ha guia.", labels: { favorites: "Favorits", recents: "Recents", savedTracks: "Pistes desades" }, library: "Obre biblioteca", note: "Aqui no es promet cap servei nou d'IA; usa senyals locals/backend ja disponibles a la web.", recommended: "Seguent recomanat", search: "Buscar emissores", title: "Guia des de la teva memoria d'emissores." },
    settings: { ...en.settings, account: "Compte", accountFallback: "Oient de Tune AV", deleteAccount: "Eliminar compte", emailFallback: "Sessio iniciada amb Account AV", library: "Obre biblioteca", localSync: "Local-first a Free", manage: "Gestiona a Account AV", navigation: "Navegacio", privacy: "Privacitat", radio: "Obre radio", support: "Suport", supportLegal: "Suport i legal", sync: "Sincronitzacio", syncNow: "Sincronitza ara", terms: "Termes" }
  },
  de: {
    ...en,
    listen: { ...en.listen, allRadio: "Alle Radios", music: "Musik", search: "Suchen", title: "Live-Sender suchen und abspielen.", searchPlaceholder: "Sender, Stadt, Genre suchen", stationResults: "Senderergebnisse", subtitle: "Aus dem Tune AV Senderfeed", errorTitle: "Sender konnten nicht geladen werden.", retry: "Erneut versuchen", emptyTitle: "Noch keine Sender.", emptyBody: "Suche breiter, entferne das Land oder waehle ein Genre.", loadMore: "Mehr laden" },
    library: { ...en.library, add: "Sender hinzufuegen", body: "Favoriten, letzte Sender, abgestimmte Sender und Musiksender sind local-first. Pro-Sync nutzt den bestehenden app-data Vertrag, wenn verfuegbar.", chooseBody: "Nutze die Kennzahlen fuer gespeicherte, letzte, abgestimmte oder musikbezogene Sender.", chooseTitle: "Bibliotheksansicht waehlen.", emptyBody: "Spiele und speichere Sender aus Hoeren, um diesen Bereich zu fuellen.", emptyTitle: "Keine Sender in dieser Ansicht.", filter: "Bibliothek filtern", modes: { favorites: "Favoriten", music: "Musiksender", overview: "Uebersicht", recents: "Letzte Sender", tuned: "Abgestimmte Sender" }, metrics: { favorites: "Favoriten", music: "Musik", recent: "Zuletzt", tuned: "Abgestimmt" }, stationCount: "Sender", title: "Gespeichertes Hoeren und Sendergedaechtnis." },
    music: { ...en.music, body: "Entdeckungen nutzen Now-Playing-Metadaten, wenn verfuegbar. Externe Aktionen oeffnen normale Suchen und beachten Free/Pro-Limits.", emptyBody: "Spiele Sender mit Song-Metadaten, speichere oder verstecke Titel dann in dieser Ansicht.", emptyTitle: "Noch keine Entdeckungen.", filter: "Songs oder Kuenstler filtern", findStations: "Sender suchen", modes: { artists: "Kuenstler", hidden: "Ausgeblendet", saved: "Gespeichert", songs: "Songs" }, title: "Entdeckte und gespeicherte Titel." },
    avi: { ...en.avi, bodyEmpty: "Spiele oder speichere zuerst einen Sender, damit Avi echten Kontext sortieren kann.", bodyReady: "Empfehlungen werden aus Favoriten, letzten Sendern, Feedback, Senderqualitaet und Musikmetadaten bewertet.", emptyBody: "Oeffne Hoeren, spiele einen Sender, speichere einen Favoriten oder gib Feedback. Avi sortiert aus diesen Signalen.", emptyTitle: "Noch keine Hilfe.", labels: { favorites: "Favoriten", recents: "Zuletzt", savedTracks: "Gespeicherte Titel" }, library: "Bibliothek oeffnen", note: "Hier wird kein neuer KI-Dienst versprochen; genutzt werden lokale/backend Signale, die der Web-App bereits vorliegen.", recommended: "Als naechstes empfohlen", search: "Sender suchen", title: "Hilfe aus deinem Sendergedaechtnis." },
    settings: { ...en.settings, account: "Konto", accountFallback: "Tune AV Hoerer", deleteAccount: "Konto loeschen", emailFallback: "Mit Account AV angemeldet", library: "Bibliothek oeffnen", localSync: "Local-first in Free", manage: "In Account AV verwalten", navigation: "Navigation", privacy: "Datenschutz", radio: "Radio oeffnen", support: "Hilfe", supportLegal: "Hilfe und Rechtliches", sync: "Synchronisierung", syncNow: "Jetzt synchronisieren", terms: "Bedingungen" }
  },
  fr: {
    ...en,
    listen: { ...en.listen, allRadio: "Toute la radio", music: "Musique", search: "Rechercher", title: "Chercher et ecouter des stations en direct.", searchPlaceholder: "Station, ville, genre", stationResults: "Resultats de stations", subtitle: "Selection du flux de stations Tune AV", errorTitle: "Impossible de charger les stations.", retry: "Reessayer", emptyTitle: "Aucune station pour le moment.", emptyBody: "Elargissez la recherche, effacez le pays ou choisissez un genre.", loadMore: "Charger plus" },
    library: { ...en.library, add: "Ajouter une station", body: "Favoris, recents, stations ajustees et stations musicales sont local-first. La synchronisation Pro utilise le contrat app-data existant quand il est disponible.", chooseBody: "Utilisez les indicateurs pour voir les stations enregistrees, recentes, ajustees ou musicales.", chooseTitle: "Choisir une vue de bibliotheque.", emptyBody: "Ecoutez et enregistrez des stations depuis Ecouter pour remplir cette section.", emptyTitle: "Aucune station dans cette vue.", filter: "Filtrer la bibliotheque", modes: { favorites: "Favoris", music: "Stations musicales", overview: "Apercu", recents: "Stations recentes", tuned: "Stations ajustees" }, metrics: { favorites: "Favoris", music: "Musique", recent: "Recentes", tuned: "Ajustees" }, stationCount: "stations", title: "Ecoute enregistree et memoire des stations." },
    music: { ...en.music, body: "La decouverte utilise les metadonnees now-playing quand elles sont disponibles. Les actions externes ouvrent des recherches normales et respectent les limites Free/Pro.", emptyBody: "Ecoutez des stations avec metadonnees de titres, puis enregistrez ou masquez les morceaux ici.", emptyTitle: "Aucune decouverte pour le moment.", filter: "Filtrer titres ou artistes", findStations: "Chercher des stations", modes: { artists: "Artistes", hidden: "Masques", saved: "Enregistres", songs: "Titres" }, title: "Titres decouverts et enregistres." },
    avi: { ...en.avi, bodyEmpty: "Ecoutez ou enregistrez d'abord une station pour qu'Avi puisse classer un vrai contexte.", bodyReady: "Les recommandations sont notees avec favoris, recents, feedback, qualite de station et metadonnees musicales.", emptyBody: "Ouvrez Ecouter, lancez une station, ajoutez un favori ou du feedback. Avi classera ces signaux.", emptyTitle: "Aucune aide pour le moment.", labels: { favorites: "Favoris", recents: "Recents", savedTracks: "Titres enregistres" }, library: "Ouvrir la bibliotheque", note: "Aucun nouveau service d'IA n'est promis ici; cela utilise les signaux locaux/backend deja disponibles dans l'app web.", recommended: "Prochaine recommandation", search: "Chercher des stations", title: "Aide depuis votre memoire de stations." },
    settings: { ...en.settings, account: "Compte", accountFallback: "Auditeur Tune AV", deleteAccount: "Supprimer le compte", emailFallback: "Connecte avec Account AV", library: "Ouvrir la bibliotheque", localSync: "Local-first en Free", manage: "Gerer dans Account AV", navigation: "Navigation", privacy: "Confidentialite", radio: "Ouvrir la radio", support: "Assistance", supportLegal: "Assistance et legal", sync: "Synchronisation", syncNow: "Synchroniser", terms: "Conditions" }
  }
};
