import AccountAV
import AVFoundation
import Foundation

enum MacPlaybackStatus: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var failureMessage: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

struct MacStationDetailRoute: Identifiable, Equatable {
    let station: Station
    let queue: [Station]
    let showsHistory: Bool

    var id: String { "\(station.id)-\(showsHistory ? "history" : "about")" }
}

struct MacHomeStationListRoute: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let stations: [Station]
}

enum MacMusicDetailRoute: Identifiable, Equatable {
    case track(MacDiscoveredTrack)
    case artist(String)

    var id: String {
        switch self {
        case let .track(discovery):
            return "track-\(discovery.discoveryID)"
        case let .artist(name):
            return "artist-\(TuneAVText.normalizedValue(name) ?? name.lowercased())"
        }
    }
}

struct MacQueueSwitchOption: Identifiable, Equatable {
    let source: TuneAVPlaybackQueueSource
    let title: String
    let stations: [Station]

    var id: String {
        "\(source.displayTitle)-\(stations.map(\.id).joined(separator: "-"))"
    }
}

extension TuneAVPlaybackQueueSource {
    var displayTitle: String {
        switch self {
        case .homeRecents:
            return L10n.string("shell.queue.homeRecents")
        case .homeFavorites:
            return L10n.string("shell.queue.homeFavorites")
        case .homeDiscovery:
            return L10n.string("shell.queue.popular")
        case .searchResults:
            return L10n.string("shell.queue.search")
        case .libraryRecents:
            return L10n.string("shell.queue.recent")
        case .libraryFavorites:
            return L10n.string("shell.queue.saved")
        case .singleStation:
            return L10n.string("shell.queue.single")
        }
    }

    var shortTitle: String {
        switch self {
        case .homeRecents:
            return L10n.string("shell.queue.short.home")
        case .homeFavorites, .libraryFavorites:
            return L10n.string("shell.queue.short.saved")
        case .homeDiscovery:
            return L10n.string("shell.queue.short.popular")
        case .searchResults:
            return L10n.string("shell.queue.short.search")
        case .libraryRecents:
            return L10n.string("shell.queue.short.recent")
        case .singleStation:
            return L10n.string("shell.queue.short.radio")
        }
    }
}

@MainActor
final class TuneAVMacModel: ObservableObject {
    @Published var selectedSection: MacRootSection = .home
    @Published var stationDetailRoute: MacStationDetailRoute?
    @Published var homeStationListRoute: MacHomeStationListRoute?
    @Published var musicDetailRoute: MacMusicDetailRoute?
    @Published private(set) var featuredStations: [Station] = Station.samples
    @Published private(set) var searchResults: [Station] = []
    @Published private(set) var favoriteStations: [Station] = []
    @Published private(set) var recentStations: [Station] = []
    @Published private(set) var stationFeedback: [String: TuneAVStationFeedback] = [:]
    @Published private(set) var discoveredTracks: [MacDiscoveredTrack] = []
    @Published private(set) var currentStation: Station?
    @Published private(set) var currentTrackTitle: String?
    @Published private(set) var currentTrackArtist: String?
    @Published private(set) var currentTrackAlbumTitle: String?
    @Published private(set) var currentTrackArtworkURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackStatus: MacPlaybackStatus = .idle
    @Published private(set) var playbackQueue: [Station] = []
    @Published private(set) var playbackQueueSource: TuneAVPlaybackQueueSource = .singleStation
    @Published private(set) var activeSleepTimerMinutes: Int?
    @Published private(set) var activeSleepTimerRemainingMinutes: Int?
    @Published var searchQuery = ""
    @Published var activeSearchTag: String?
    @Published var selectedSearchCountryCode: String?
    @Published var searchDiscoveryMode: TuneAVStationDiscoveryMode = .music
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMoreSearchResults = false
    @Published private(set) var searchTotalCount: Int?
    @Published private(set) var hasMoreSearchResults = false
    @Published private(set) var searchNextCursor: String?
    @Published private(set) var accountUser: AccountAVUser?
    @Published private(set) var accessMode: AccessMode = .guest
    @Published private(set) var planTier: PlanTier = .free
    @Published private(set) var capabilities: AccessCapabilities = .forMode(.guest)
    @Published private(set) var limits: AccessLimits = .forMode(.guest)
    @Published var upgradePrompt: UpgradePrompt?
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle
    @Published private(set) var lastCloudSyncAt: Date?
    @Published var errorMessage: String?
    @Published var cloudSyncErrorMessage: String?

    private let stationService = TuneAVStationService()
    private let player = AVPlayer()
    private let trackArtworkService = TuneAVTrackArtworkService()
    private let storage = TuneAVMacLibraryStorage()
    private let systemNowPlayingController = MacNowPlayingSystemController()
    private let accountService = ClerkAccountAVService(
        publishableKeyProvider: { TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY") },
        fallbackDisplayName: "Tune AV",
        loggerSubsystem: "com.avalsys.tuneav"
    )
    private var localLibraryUpdatedAt: Date = .distantPast
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: TuneAVStreamMetadataDelegate?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var playbackNotificationObservers: [NSObjectProtocol] = []
    private var playbackFailuresInCurrentQueue = Set<String>()
    private var currentTrackFeedbackByID: [String: TuneAVStationFeedback] = [:]
    private var cloudSyncTrigger = MacCloudSyncTrigger()
    private var pendingCloudSyncTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerEndDate: Date?
    private var trackArtworkTask: Task<Void, Never>?
    private let dailyUsageLimiter = TuneAVDailyUsageLimiter(
        keyStyle: .dayBucket(prefix: "tuneav.featureUsage."),
        limitedFeatures: LimitedFeature.dailyUsageLimitedFeatures
    )

    init() {
        favoriteStations = storage.loadStations(forKey: TuneAVMacLibraryStorage.favoritesKey)
        recentStations = storage.loadStations(forKey: TuneAVMacLibraryStorage.recentsKey)
        stationFeedback = storage.loadStationFeedback()
        discoveredTracks = storage.loadDiscoveries()
        localLibraryUpdatedAt = storage.loadDate(forKey: TuneAVMacLibraryStorage.localLibraryUpdatedAtKey)
            ?? (favoriteStations.isEmpty && recentStations.isEmpty && discoveredTracks.isEmpty ? .distantPast : .now)
        resolveLocalAccessState()
        configureSystemNowPlaying()
    }

    deinit {
        sleepTimerTask?.cancel()
        trackArtworkTask?.cancel()
    }

    var heroStation: Station? {
        currentStation ?? recentStations.first ?? favoriteStations.first ?? featuredStations.first
    }

    var moodGenreSuggestions: [MacHomeMoodGenreSuggestion] {
        TuneAVMusicGenreCatalog.visibleTags.map { tag in
            MacHomeMoodGenreSuggestion(
                tag: tag,
                title: L10n.genreLabel(for: tag).capitalized(with: L10n.locale)
            )
        }
    }

    var allAviPickStations: [Station] {
        featuredStations.filter { $0.id != heroStation?.id }
    }

    var aviPickStations: [Station] {
        Array(allAviPickStations.prefix(4))
    }

    var allAroundYouStations: [Station] {
        let excludedIDs = Set(([heroStation] + aviPickStations).compactMap(\.?.id))
        let preferredCountryCode = currentStation?.countryCode ?? Locale.current.region?.identifier
        let countryStations = featuredStations.filter { station in
            guard !excludedIDs.contains(station.id) else { return false }
            return TuneAVCountry.sanitizedCode(station.countryCode) == TuneAVCountry.sanitizedCode(preferredCountryCode)
        }

        if !countryStations.isEmpty {
            return countryStations
        }

        return featuredStations.filter { !excludedIDs.contains($0.id) }
    }

    var aroundYouStations: [Station] {
        Array(allAroundYouStations.prefix(6))
    }

    var recentAndFavoriteStations: [Station] {
        var seenIDs = Set<String>()
        return (recentStations + favoriteStations).filter { station in
            seenIDs.insert(station.id).inserted
        }
    }

    func loadFeaturedStations() async {
        do {
            featuredStations = try await stationService.popularStations(
                filters: TuneAVStationSearchFilters(query: "", limit: 18, allowsEmptySearch: true)
            )
            rememberStationEnrichment(featuredStations)
        } catch {
            errorMessage = error.localizedDescription
            featuredStations = Station.samples
        }
    }

    func openStationDetail(_ station: Station, queue: [Station], showsHistory: Bool = false) {
        stationDetailRoute = MacStationDetailRoute(
            station: station,
            queue: queue.isEmpty ? [station] : queue,
            showsHistory: showsHistory
        )
        musicDetailRoute = nil
    }

    func openHomeStationList(id: String, title: String, subtitle: String, stations: [Station]) {
        homeStationListRoute = MacHomeStationListRoute(
            id: id,
            title: title,
            subtitle: subtitle,
            stations: stations
        )
        stationDetailRoute = nil
        musicDetailRoute = nil
    }

    func closeStationDetail() {
        stationDetailRoute = nil
        homeStationListRoute = nil
        musicDetailRoute = nil
    }

    func openMusicTrackDetail(_ discovery: MacDiscoveredTrack) {
        musicDetailRoute = .track(discovery)
        stationDetailRoute = nil
        homeStationListRoute = nil
    }

    func openMusicArtistDetail(_ artistName: String) {
        musicDetailRoute = .artist(artistName)
        stationDetailRoute = nil
        homeStationListRoute = nil
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeSearchTag ?? ""
        let countryCode = TuneAVCountry.sanitizedCode(selectedSearchCountryCode) ?? ""
        let mode = searchDiscoveryMode.rawValue

        do {
            isSearching = true
            isLoadingMoreSearchResults = false
            defer { isSearching = false }

            if query.isEmpty, tag.isEmpty, countryCode.isEmpty {
                searchResults = try await stationService.popularStations(
                    filters: TuneAVStationSearchFilters(
                        query: "",
                        locale: L10n.locale.identifier,
                        mode: mode,
                        limit: 30,
                        allowsEmptySearch: true
                    )
                )
                searchTotalCount = searchResults.count
                hasMoreSearchResults = false
                searchNextCursor = nil
            } else {
                let page = try await stationService.searchStationsPage(
                    filters: TuneAVStationSearchFilters(
                        query: query,
                        countryCode: countryCode,
                        tag: tag,
                        locale: L10n.locale.identifier,
                        mode: mode,
                        limit: 30,
                        allowsEmptySearch: true
                    )
                )
                searchResults = page.stations
                searchTotalCount = page.total
                hasMoreSearchResults = page.hasMore
                searchNextCursor = page.nextCursor
            }
            rememberStationEnrichment(searchResults)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            searchResults = searchFallbackStations(query: query, tag: tag, countryCode: countryCode)
            searchTotalCount = searchResults.count
            hasMoreSearchResults = false
            searchNextCursor = nil
        }
    }

    func loadMoreSearchResults() async {
        guard !isSearching, !isLoadingMoreSearchResults, hasMoreSearchResults, let cursor = searchNextCursor else { return }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeSearchTag ?? ""
        let countryCode = TuneAVCountry.sanitizedCode(selectedSearchCountryCode) ?? ""

        do {
            isLoadingMoreSearchResults = true
            defer { isLoadingMoreSearchResults = false }
            let page = try await stationService.searchStationsPage(
                filters: TuneAVStationSearchFilters(
                    query: query,
                    countryCode: countryCode,
                    tag: tag,
                    locale: L10n.locale.identifier,
                    mode: searchDiscoveryMode.rawValue,
                    cursor: cursor,
                    limit: query.isEmpty ? 30 : 24,
                    allowsEmptySearch: true
                )
            )
            let existingIDs = Set(searchResults.map(\.id))
            let newStations = page.stations.filter { !existingIDs.contains($0.id) }
            searchResults.append(contentsOf: newStations)
            rememberStationEnrichment(newStations)
            searchTotalCount = page.total ?? searchTotalCount
            hasMoreSearchResults = page.hasMore
            searchNextCursor = page.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            hasMoreSearchResults = false
            searchNextCursor = nil
        }
    }

    var searchGenreTags: [String] {
        switch searchDiscoveryMode {
        case .music:
            return TuneAVMusicGenreCatalog.visibleTags
        case .allRadio:
            return TuneAVMusicGenreCatalog.visibleTags + ["news", "sports", "talk", "culture", "local", "public", "religion"]
        }
    }

    var searchSectionTitle: String {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, activeSearchTag == nil, let countryCode = TuneAVCountry.sanitizedCode(selectedSearchCountryCode) {
            return L10n.string("shell.search.section.country.title", L10n.countryName(for: countryCode))
        }
        if query.isEmpty, activeSearchTag == nil {
            return L10n.string("shell.search.section.popularWorldwide.title")
        }
        if query.isEmpty {
            return L10n.string("shell.search.section.browse.title")
        }
        return L10n.string("shell.search.section.results.title")
    }

    var searchSectionSubtitle: String {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return L10n.plural(
                singular: "shell.search.results.count.one",
                plural: "shell.search.results.count.other",
                count: searchTotalCount ?? searchResults.count,
                searchTotalCount ?? searchResults.count,
                query
            )
        }

        if let countryCode = TuneAVCountry.sanitizedCode(selectedSearchCountryCode) {
            return L10n.string("shell.search.section.country.subtitle", L10n.countryName(for: countryCode))
        }

        if activeSearchTag == nil {
            return L10n.string("shell.search.section.popularWorldwide.subtitle")
        }

        return L10n.string("shell.search.section.browse.subtitle")
    }

    var canCyclePlaybackQueue: Bool {
        playbackQueue.count > 1
    }

    var nowPlayingDisplayLines: TuneAVNowPlayingDisplayLines? {
        guard let currentStation else { return nil }
        return TuneAVNowPlayingDisplayLines.resolve(
            station: currentStation,
            currentTitle: currentTrackTitle,
            currentArtist: currentTrackArtist,
            currentAlbumTitle: currentTrackAlbumTitle,
            liveNowFallback: L10n.string("player.track.liveNow"),
            liveStreamFallback: L10n.string("shell.liveNow.title")
        )
    }

    var currentDiscovery: TuneAVCurrentDiscovery? {
        TuneAVCurrentDiscovery.resolve(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: currentStation
        )
    }

    var hasCurrentDiscovery: Bool {
        currentDiscovery != nil
    }

    var savedDiscoveredTracks: [MacDiscoveredTrack] {
        TuneAVMusicLibraryLogic.savedDiscoveries(discoveredTracks)
    }

    var currentDiscoveryIsSaved: Bool {
        guard let currentDiscoveryIndex else { return false }
        return discoveredTracks[currentDiscoveryIndex].isMarkedInteresting
    }

    var currentDiscoveryFeedback: TuneAVStationFeedback? {
        if let discoveryID = currentDiscoveryFeedbackID, let feedback = currentTrackFeedbackByID[discoveryID] {
            return feedback
        }
        guard let currentDiscoveryIndex else { return nil }
        return discoveredTracks[currentDiscoveryIndex].hiddenAt == nil ? nil : .notForMe
    }

    var playbackQueueSourceTitle: String {
        playbackQueueSource.displayTitle
    }

    var playbackQueueSwitchOptions: [MacQueueSwitchOption] {
        var options: [MacQueueSwitchOption] = []

        if !playbackQueue.isEmpty {
            options.append(
                MacQueueSwitchOption(
                    source: playbackQueueSource,
                    title: L10n.string("shell.queue.currentOption", playbackQueueSource.displayTitle),
                    stations: playbackQueue
                )
            )
        }

        if !featuredStations.isEmpty {
            options.append(
                MacQueueSwitchOption(
                    source: .homeDiscovery,
                    title: L10n.string("shell.queue.popular"),
                    stations: featuredStations
                )
            )
        }

        if !favoriteStations.isEmpty {
            options.append(
                MacQueueSwitchOption(
                    source: .libraryFavorites,
                    title: L10n.string("shell.queue.saved"),
                    stations: favoriteStations
                )
            )
        }

        if !recentStations.isEmpty {
            options.append(
                MacQueueSwitchOption(
                    source: .libraryRecents,
                    title: L10n.string("shell.queue.recent"),
                    stations: recentStations
                )
            )
        }

        var seen = Set<String>()
        return options.filter { option in
            let key = "\(option.source.shortTitle)|\(option.stations.map(\.id).joined(separator: ","))"
            return seen.insert(key).inserted
        }
    }

    private var currentDiscoveryIndex: Int? {
        guard let currentStation, let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackTitle) else {
            return nil
        }
        let discoveryID = MacDiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackArtist),
            stationID: currentStation.id
        )
        return discoveredTracks.firstIndex { $0.discoveryID == discoveryID }
    }

    private var currentDiscoveryFeedbackID: String? {
        guard let currentStation, let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackTitle) else {
            return nil
        }
        return MacDiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackArtist),
            stationID: currentStation.id
        )
    }

    func play(_ station: Station, queue: [Station]? = nil, source: TuneAVPlaybackQueueSource? = nil) {
        guard let url = URL(string: station.streamURL) else {
            setPlaybackFailure("Invalid stream URL.", shouldAutoSkip: false)
            return
        }

        if let queue {
            playbackQueue = sanitizedQueue(queue, currentStation: station)
            playbackQueueSource = source ?? playbackQueueSource
        } else if playbackQueue.isEmpty || !playbackQueue.contains(where: { $0.id == station.id }) {
            playbackQueue = [station]
            playbackQueueSource = source ?? .singleStation
        }

        currentStation = station
        playbackFailuresInCurrentQueue.remove(station.id)
        playbackStatus = .loading
        isPlaying = false
        resetCurrentTrackMetadata()
        recordRecent(station)
        let item = AVPlayerItem(url: url)
        attachMetadataOutput(to: item)
        attachPlaybackObservers(to: item)
        player.replaceCurrentItem(with: item)
        player.play()
        updateSystemNowPlaying()
    }

    func selectPlaybackQueue(_ option: MacQueueSwitchOption) {
        guard let currentStation else { return }
        let queue = option.stations.contains(where: { $0.id == currentStation.id })
            ? option.stations
            : [currentStation] + option.stations
        play(currentStation, queue: queue, source: option.source)
    }

    func search(tag: String) async {
        activeSearchTag = tag
        searchQuery = ""
        await search()
    }

    func toggleSearchTag(_ tag: String) async {
        activeSearchTag = activeSearchTag == tag ? nil : tag
        searchQuery = ""
        await search()
    }

    func clearSearchFilters() async {
        searchQuery = ""
        activeSearchTag = nil
        selectedSearchCountryCode = nil
        await search()
    }

    func setSearchCountryCode(_ countryCode: String?) async {
        selectedSearchCountryCode = TuneAVCountry.sanitizedCode(countryCode)
        await search()
    }

    func setSearchDiscoveryMode(_ mode: TuneAVStationDiscoveryMode) async {
        searchDiscoveryMode = mode
        if case .allRadio = mode {
            // Keep all tags available. Music tags remain valid in both modes.
        } else if let tag = activeSearchTag, !TuneAVMusicGenreCatalog.visibleTags.contains(tag) {
            self.activeSearchTag = nil
        }
        await search()
    }

    private func searchFallbackStations(query: String, tag: String, countryCode: String) -> [Station] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return featuredStations.filter { station in
            let matchesQuery = normalizedQuery.isEmpty ||
                station.name.lowercased().contains(normalizedQuery) ||
                station.country.lowercased().contains(normalizedQuery) ||
                station.language.lowercased().contains(normalizedQuery) ||
                station.tags.lowercased().contains(normalizedQuery)
            let matchesTag = tag.isEmpty || station.tagsList.contains { $0.localizedCaseInsensitiveContains(tag) }
            let matchesCountry = countryCode.isEmpty ||
                TuneAVCountry.sanitizedCode(station.countryCode) == TuneAVCountry.sanitizedCode(countryCode)
            return matchesQuery && matchesTag && matchesCountry
        }
    }

    func togglePlayback() {
        guard currentStation != nil else {
            if let firstStation = featuredStations.first {
                play(firstStation, queue: featuredStations)
            }
            return
        }

        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func retryCurrentStation() {
        guard let currentStation else { return }
        play(currentStation, queue: playbackQueue.isEmpty ? [currentStation] : playbackQueue)
    }

    func pausePlayback() {
        guard currentStation != nil else { return }
        player.pause()
        setPlaybackStatus(.paused)
    }

    func stopPlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentStation = nil
        playbackQueue = []
        playbackQueueSource = .singleStation
        playbackFailuresInCurrentQueue.removeAll()
        resetCurrentTrackMetadata()
        setPlaybackStatus(.idle)
        updateSystemNowPlaying()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard let minutes else {
            activeSleepTimerMinutes = nil
            activeSleepTimerRemainingMinutes = nil
            sleepTimerEndDate = nil
            return
        }

        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        activeSleepTimerMinutes = minutes
        activeSleepTimerRemainingMinutes = minutes
        sleepTimerEndDate = endDate

        sleepTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                let remainingMinutes = max(0, Int(ceil(endDate.timeIntervalSinceNow / 60)))
                await MainActor.run {
                    guard self?.sleepTimerEndDate == endDate else { return }
                    self?.activeSleepTimerRemainingMinutes = remainingMinutes
                }

                if remainingMinutes <= 0 {
                    break
                }

                try? await Task.sleep(for: .seconds(30))
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.sleepTimerEndDate == endDate else { return }
                self?.activeSleepTimerMinutes = nil
                self?.activeSleepTimerRemainingMinutes = nil
                self?.sleepTimerEndDate = nil
                self?.stopPlayback()
            }
        }
    }

    func resumePlayback() {
        guard currentStation != nil else {
            if let firstStation = featuredStations.first {
                play(firstStation, queue: featuredStations)
            }
            return
        }

        player.play()
        setPlaybackStatus(player.timeControlStatus == .playing ? .playing : .loading)
    }

    func toggleFavorite(_ station: Station) {
        if favoriteStations.contains(station) {
            favoriteStations.removeAll { $0 == station }
        } else {
            favoriteStations.insert(station, at: 0)
        }
        storage.save(favoriteStations, forKey: TuneAVMacLibraryStorage.favoritesKey)
        markLocalLibraryUpdated()
    }

    func isFavorite(_ station: Station) -> Bool {
        favoriteStations.contains(station)
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        guard stationFeedback[station.id] != feedback else { return }
        stationFeedback[station.id] = feedback
        storage.saveStationFeedback(stationFeedback)
        markLocalLibraryUpdated()
    }

    func clearFavorites() {
        favoriteStations = []
        storage.save(favoriteStations, forKey: TuneAVMacLibraryStorage.favoritesKey)
        markLocalLibraryUpdated()
    }

    func clearRecents() {
        recentStations = []
        storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        markLocalLibraryUpdated()
    }

    func clearLocalLibraryData() {
        clearFavorites()
        clearRecents()
        clearDiscoveredTracks()
        stationFeedback = [:]
        storage.saveStationFeedback(stationFeedback)
    }

    func playPreviousInQueue() {
        guard let station = adjacentQueueStation(offset: -1) else { return }
        play(station, queue: playbackQueue, source: playbackQueueSource)
    }

    func playNextInQueue() {
        guard let station = adjacentQueueStation(offset: 1) else { return }
        play(station, queue: playbackQueue, source: playbackQueueSource)
    }

    func currentTrackSearchURL(destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) -> URL? {
        guard let query = currentTrackSearchQuery(suffix: suffix) else { return nil }
        return TuneAVExternalSearchURL.url(for: destination, query: query)
    }

    func currentTrackSearchQuery(suffix: String? = nil) -> String? {
        guard let currentStation else { return nil }
        let query = TuneAVExternalSearchURL.query(
            parts: [currentTrackArtist, currentTrackTitle, currentStation.name],
            suffix: suffix
        )
        guard !query.isEmpty else { return nil }
        return query
    }

    func currentArtistSearchURL() -> URL? {
        guard let artist = TuneAVExternalSearchURL.normalizedValue(currentTrackArtist) else { return nil }
        return TuneAVExternalSearchURL.url(for: .web, query: artist)
    }

    func currentDiscoveryShareText() -> String? {
        currentDiscovery?.localizedShareText
    }

    @discardableResult
    func toggleCurrentDiscoverySaved() -> Bool {
        guard let currentStation, let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackTitle) else {
            return false
        }

        let normalizedArtist = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackArtist)
        let discoveryID = MacDiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: normalizedArtist,
            stationID: currentStation.id
        )
        let now = Date.now

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discoveryID }) {
            discoveredTracks[index].playedAt = now
            discoveredTracks[index].markedInterestedAt = discoveredTracks[index].markedInterestedAt == nil ? now : nil
            discoveredTracks[index].hiddenAt = nil
        } else {
            discoveredTracks.insert(
                MacDiscoveredTrack(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    station: currentStation,
                    playedAt: now,
                    markedInterestedAt: now
                ),
                at: 0
            )
        }

        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
        return currentDiscoveryIsSaved
    }

    func setCurrentDiscoveryFeedback(_ feedback: TuneAVStationFeedback?) {
        guard let currentStation, let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackTitle) else {
            return
        }

        let normalizedArtist = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackArtist)
        let discoveryID = MacDiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: normalizedArtist,
            stationID: currentStation.id
        )
        let now = Date.now
        currentTrackFeedbackByID[discoveryID] = feedback

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discoveryID }) {
            discoveredTracks[index].playedAt = now
            discoveredTracks[index].hiddenAt = feedback == .notForMe ? now : nil
        } else if feedback == .notForMe {
            discoveredTracks.insert(
                MacDiscoveredTrack(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    station: currentStation,
                    playedAt: now,
                    hiddenAt: now
                ),
                at: 0
            )
        }

        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func clearDiscoveredTracks() {
        discoveredTracks = []
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func toggleDiscoverySaved(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        discoveredTracks[index].markedInterestedAt = discoveredTracks[index].markedInterestedAt == nil ? Date.now : nil
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func hideDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        discoveredTracks[index].hiddenAt = Date.now
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func restoreDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func removeDiscovery(_ discovery: MacDiscoveredTrack) {
        discoveredTracks.removeAll { $0.discoveryID == discovery.discoveryID }
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    func startAutomaticLibrarySync() async {
        accountUser = accountService.currentUser
        resolveLocalAccessState()
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.startupCompleted(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil
            )
        )
    }

    func refreshAccount() async {
        accountUser = accountService.currentUser
        resolveLocalAccessState()
        guard accountUser != nil else { return }
        let token = try? await accountService.getToken()
        guard let token, !token.isEmpty else { return }
        await refreshAccessState(tokenOverride: token)
    }

    func signInWithApple() async {
        await performAccountAction {
            try await accountService.signInWithApple()
        }
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.signInCompleted(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil
            )
        )
    }

    func signInWithGoogle() async {
        await performAccountAction {
            try await accountService.signInWithGoogle()
        }
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.signInCompleted(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil
            )
        )
    }

    func signOut() async {
        handleCloudSyncTriggerAction(cloudSyncTrigger.signOutStarted())
        await performAccountAction {
            try await accountService.signOut()
        }
        cloudSyncStatus = .idle
        accountUser = accountService.currentUser
        resolveLocalAccessState()
    }

    func canPerformPremiumAviAction(feature: LimitedFeature, usageKey: String? = nil) -> Bool {
        guard capabilities.canAccessPremiumFeatures else {
            presentUpgradePrompt(for: feature)
            return false
        }

        let dailyFeature = dailyUsageFeature(for: feature)
        let limit = limits.limit(for: feature)
        let canUse: Bool
        if let usageKey {
            canUse = dailyUsageLimiter.canUse(
                dailyFeature,
                limit: limit,
                usageKey: dailyUsageKey(for: feature, usageKey: usageKey)
            )
        } else {
            canUse = dailyUsageLimiter.canUse(dailyFeature, limit: limit)
        }

        guard canUse else {
            presentUpgradePrompt(for: feature)
            return false
        }

        if let usageKey {
            dailyUsageLimiter.recordUse(dailyFeature, usageKey: dailyUsageKey(for: feature, usageKey: usageKey))
        } else {
            dailyUsageLimiter.recordUse(dailyFeature)
        }
        return true
    }

    func canPerformPremiumAviSearch(
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil,
        usageKey: String
    ) -> Bool {
        canPerformPremiumAviAction(
            feature: premiumFeature(for: destination, suffix: suffix),
            usageKey: usageKey
        )
    }

    func synchronizeLibraryNow() async {
        guard accountService.isAvailable else {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = "Account AV is not configured."
            return
        }

        do {
            cloudSyncStatus = .syncing
            cloudSyncErrorMessage = nil
            let client = makeAppDataSyncClient()
            let localSnapshot = librarySnapshot()
            let remoteDocument = try await client.pullLibrary()
            let snapshotToApply: TuneAVLibrarySnapshot

            switch TuneAVLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: localLibraryUpdatedAt,
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                snapshotToApply = cloudBoundedSnapshot(
                    TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                )
                applyLibrarySnapshot(snapshotToApply)
                if snapshotToApply != remoteSnapshot {
                    try await client.pushLibrary(snapshotToApply)
                }
            case .pushLocal:
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToApply = cloudBoundedSnapshot(
                        TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                    )
                } else {
                    snapshotToApply = cloudBoundedSnapshot(localSnapshot)
                }
                try await client.pushLibrary(snapshotToApply)
                if snapshotToApply != localSnapshot {
                    applyLibrarySnapshot(snapshotToApply)
                }
            case .noContent:
                snapshotToApply = localSnapshot
            case .alreadyCurrent:
                snapshotToApply = localSnapshot
            }

            lastCloudSyncAt = .now
            cloudSyncStatus = .synced(lastCloudSyncAt ?? .now)
            accountUser = accountService.currentUser
        } catch TuneAVAppDataClientError.missingToken {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = "Sign in to sync your Tune AV library."
        } catch TuneAVAppDataClientError.missingBaseURL {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = "Missing Account AV API base URL."
        } catch {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    private func recordRecent(_ station: Station) {
        recentStations.removeAll { $0.id == station.id }
        recentStations.insert(station, at: 0)
        recentStations = Array(recentStations.prefix(12))
        storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        markLocalLibraryUpdated()
    }

    private func rememberStationEnrichment(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        let enrichedByKey = stations.reduce(into: [String: Station]()) { result, station in
            for key in station.macEnrichmentLookupKeys {
                guard station.isPreferredMacEnrichment(over: result[key]) else { continue }
                result[key] = station
            }
        }
        guard !enrichedByKey.isEmpty else { return }

        var didUpdateFavorites = false
        favoriteStations = favoriteStations.map { station in
            guard let enriched = bestEnrichedStation(for: station, in: enrichedByKey),
                  enriched.isPreferredMacEnrichment(over: station)
            else {
                return station
            }
            didUpdateFavorites = true
            return enriched
        }

        var didUpdateRecents = false
        recentStations = recentStations.map { station in
            guard let enriched = bestEnrichedStation(for: station, in: enrichedByKey),
                  enriched.isPreferredMacEnrichment(over: station)
            else {
                return station
            }
            didUpdateRecents = true
            return enriched
        }

        if let currentStation,
           let enriched = bestEnrichedStation(for: currentStation, in: enrichedByKey),
           enriched.isPreferredMacEnrichment(over: currentStation) {
            self.currentStation = enriched
        }

        guard didUpdateFavorites || didUpdateRecents else { return }
        if didUpdateFavorites {
            storage.save(favoriteStations, forKey: TuneAVMacLibraryStorage.favoritesKey)
        }
        if didUpdateRecents {
            storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        }
        markLocalLibraryUpdated()
    }

    private func bestEnrichedStation(for station: Station, in enrichedByKey: [String: Station]) -> Station? {
        station.macEnrichmentLookupKeys
            .compactMap { enrichedByKey[$0] }
            .max { $0.macEnrichmentRank < $1.macEnrichmentRank }
    }

    private func sanitizedQueue(_ queue: [Station], currentStation: Station) -> [Station] {
        var seenIDs = Set<String>()
        let stations = queue.filter { station in
            seenIDs.insert(station.id).inserted
        }

        guard stations.contains(where: { $0.id == currentStation.id }) else {
            return [currentStation] + stations
        }

        return stations
    }

    private func adjacentQueueStation(offset: Int) -> Station? {
        guard canCyclePlaybackQueue, let currentStation else { return nil }
        guard let currentIndex = playbackQueue.firstIndex(where: { $0.id == currentStation.id }) else {
            return playbackQueue.first
        }

        let nextIndex = (currentIndex + offset + playbackQueue.count) % playbackQueue.count
        return playbackQueue[nextIndex]
    }

    private func attachMetadataOutput(to item: AVPlayerItem) {
        let metadataDelegate = TuneAVStreamMetadataDelegate { [weak self] events in
            Task { @MainActor in
                self?.updateTrackMetadata(from: events)
            }
        }
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(metadataDelegate, queue: .main)
        item.add(metadataOutput)
        self.metadataOutput = metadataOutput
        self.metadataDelegate = metadataDelegate
    }

    private func attachPlaybackObservers(to item: AVPlayerItem) {
        playerItemStatusObserver?.invalidate()
        playerTimeControlObserver?.invalidate()
        playbackNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        playbackNotificationObservers = []

        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                self?.handleItemStatusChange(observedItem)
            }
        }

        playerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(observedPlayer.timeControlStatus)
            }
        }

        let failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                ?? "Stream playback failed."
            Task { @MainActor in
                self?.setPlaybackFailure(message, shouldAutoSkip: true)
            }
        }

        let stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackStatus.failureMessage == nil else { return }
                self.setPlaybackStatus(.loading)
            }
        }

        playbackNotificationObservers = [failureObserver, stalledObserver]
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            setPlaybackStatus(player.timeControlStatus == .playing ? .playing : .loading)
        case .failed:
            setPlaybackFailure(item.error?.localizedDescription ?? "Stream playback failed.", shouldAutoSkip: true)
        case .unknown:
            setPlaybackStatus(.loading)
        @unknown default:
            setPlaybackStatus(.loading)
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        guard playbackStatus.failureMessage == nil else { return }

        switch status {
        case .playing:
            setPlaybackStatus(.playing)
        case .paused:
            setPlaybackStatus(currentStation == nil ? .idle : .paused)
        case .waitingToPlayAtSpecifiedRate:
            setPlaybackStatus(.loading)
        @unknown default:
            setPlaybackStatus(currentStation == nil ? .idle : .paused)
        }
    }

    private func setPlaybackStatus(_ status: MacPlaybackStatus) {
        playbackStatus = status
        isPlaying = status == .playing
        updateSystemNowPlaying()
    }

    private func setPlaybackFailure(_ message: String, shouldAutoSkip: Bool) {
        player.pause()
        setPlaybackStatus(.failed(message))
        errorMessage = message

        guard shouldAutoSkip, let currentStation else { return }
        playbackFailuresInCurrentQueue.insert(currentStation.id)
        attemptAutoSkipAfterFailure(from: currentStation)
    }

    private func attemptAutoSkipAfterFailure(from failedStation: Station) {
        guard canCyclePlaybackQueue else { return }

        let queueIDs = Set(playbackQueue.map(\.id))
        guard !queueIDs.isSubset(of: playbackFailuresInCurrentQueue) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard currentStation?.id == failedStation.id, playbackStatus.failureMessage != nil else { return }
            playNextInQueue()
        }
    }

    private func updateTrackMetadata(from events: [TuneAVStreamMetadataEvent]) {
        guard !events.isEmpty else { return }

        var resolvedTitle = currentTrackTitle
        var resolvedArtist = currentTrackArtist

        for event in events {
            let value = event.value
            let commonKey = event.commonKey
            let identifier = event.identifier

            if commonKey == "title" || identifier.contains("title") || identifier.contains("streamtitle") {
                let parsed = TuneAVTrackMetadataParser.parse(value)
                guard !TuneAVTrackMetadataParser.titleLooksLikeTruncatedContraction(parsed.title) else {
                    continue
                }
                resolvedTitle = parsed.title ?? resolvedTitle
                resolvedArtist = parsed.artist ?? resolvedArtist
                continue
            }

            if commonKey == "artist" || identifier.contains("artist") {
                resolvedArtist = TuneAVTrackMetadataParser.sanitizeArtist(value) ?? resolvedArtist
            }

            if commonKey == "albumname" || commonKey == "album" || identifier.contains("album") {
                currentTrackAlbumTitle = TuneAVDisplayMetadata.normalized(value)
            }
        }

        if TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(resolvedTitle, stationName: currentStation?.name) ||
            TuneAVTrackMetadataParser.titleLooksLikeTruncatedContraction(resolvedTitle) {
            resolvedTitle = nil
            resolvedArtist = nil
        } else if TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(resolvedArtist, stationName: currentStation?.name) {
            resolvedArtist = nil
        }

        currentTrackTitle = TuneAVDisplayMetadata.normalized(resolvedTitle)
        currentTrackArtist = TuneAVDisplayMetadata.normalized(resolvedArtist)
        recordCurrentTrackDiscovery()
        resolveCurrentTrackArtwork()
        updateSystemNowPlaying()
    }

    private func resetCurrentTrackMetadata() {
        currentTrackTitle = nil
        currentTrackArtist = nil
        currentTrackAlbumTitle = nil
        currentTrackArtworkURL = nil
        trackArtworkTask?.cancel()
        trackArtworkTask = nil
    }

    private func resolveCurrentTrackArtwork() {
        trackArtworkTask?.cancel()
        currentTrackArtworkURL = nil

        guard let artist = currentTrackArtist, let title = currentTrackTitle else {
            return
        }

        trackArtworkTask = Task { [weak self, trackArtworkService] in
            let artwork = await trackArtworkService.resolveArtwork(artist: artist, title: title)
            await MainActor.run {
                guard self?.currentTrackArtist == artist, self?.currentTrackTitle == title else { return }
                self?.currentTrackArtworkURL = artwork?.artworkURL
                if let albumTitle = artwork?.albumTitle, self?.currentTrackAlbumTitle == nil {
                    self?.currentTrackAlbumTitle = albumTitle
                }
                self?.recordCurrentTrackDiscovery()
                self?.updateSystemNowPlaying()
            }
        }
    }

    private func recordCurrentTrackDiscovery() {
        guard
            let currentStation,
            let trackTitle = TuneAVDisplayMetadata.plausibleTitle(currentTrackTitle, stationName: currentStation.name),
            let trackArtist = TuneAVDisplayMetadata.plausibleArtist(currentTrackArtist, stationName: currentStation.name)
        else {
            return
        }

        let discovery = MacDiscoveredTrack(
            title: trackTitle,
            artist: trackArtist,
            station: currentStation,
            artworkURL: currentTrackArtworkURL
        )
        let now = Date.now

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) {
            let currentArtworkURL = currentTrackArtworkURL?.absoluteString
            let shouldRefresh = now.timeIntervalSince(discoveredTracks[index].playedAt) >= 60
                || (currentArtworkURL != nil && discoveredTracks[index].artworkURL != currentArtworkURL)
            guard shouldRefresh else { return }
            discoveredTracks[index].playedAt = now
            if let currentArtworkURL {
                discoveredTracks[index].artworkURL = currentArtworkURL
            }
        } else {
            discoveredTracks.insert(discovery, at: 0)
        }

        trimDiscoveriesToAccessLimit()
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated()
    }

    private func trimDiscoveriesToAccessLimit() {
        guard let limit = limits.discoveredTracks, discoveredTracks.count > limit else { return }
        discoveredTracks = Array(sortedDiscoveries(discoveredTracks).prefix(limit))
    }

    private func configureSystemNowPlaying() {
        systemNowPlayingController.configureRemoteCommands(
            play: { [weak self] in self?.resumePlayback() },
            pause: { [weak self] in self?.pausePlayback() },
            toggle: { [weak self] in self?.togglePlayback() },
            next: { [weak self] in self?.playNextInQueue() },
            previous: { [weak self] in self?.playPreviousInQueue() }
        )
    }

    private func updateSystemNowPlaying() {
        systemNowPlayingController.update(
            station: currentStation,
            title: currentTrackTitle,
            artist: currentTrackArtist,
            albumTitle: currentTrackAlbumTitle,
            isPlaying: isPlaying,
            elapsedTime: player.currentTime().seconds
        )
    }

    private func performAccountAction(_ action: () async throws -> Void) async {
        do {
            cloudSyncErrorMessage = nil
            try await action()
            accountUser = accountService.currentUser
            resolveLocalAccessState()
            await refreshAccessState()
        } catch {
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    private func refreshAccessState(tokenOverride: String? = nil) async {
        guard accountUser != nil else {
            applyResolvedAccess(.guest)
            return
        }
        guard !TuneAVUITestEnvironment.current.hasAccountOverride else {
            resolveLocalAccessState()
            return
        }
        guard let baseURL = TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL") else {
            resolveLocalAccessState()
            return
        }

        do {
            let resolvedToken = tokenOverride
            let client = TuneAVAccessClient(
                baseURL: baseURL,
                tokenProvider: { [self] in
                    if let resolvedToken {
                        return resolvedToken
                    }
                    return try await accountService.getToken()
                },
                urlSession: TuneAVURLSessions.account
            )
            let access = try await client.fetchTuneAVAccess()
            applyResolvedAccess(
                TuneAVResolvedAccess(
                    planTier: access.planTier,
                    accessMode: access.accessMode,
                    capabilities: access.capabilities,
                    limits: access.limits
                )
            )
        } catch {
            resolveLocalAccessState()
        }
    }

    private func resolveLocalAccessState() {
        if let uiTestAccess = uiTestResolvedAccess() {
            applyResolvedAccess(uiTestAccess)
            return
        }
        guard accountUser != nil else {
            applyResolvedAccess(.guest)
            return
        }
        applyResolvedAccess(.localFallback(for: .signedInFree))
    }

    private func applyResolvedAccess(_ resolvedAccess: TuneAVResolvedAccess) {
        guard accountUser != nil || resolvedAccess.accessMode == .guest else {
            applyResolvedAccess(.guest)
            return
        }

        planTier = resolvedAccess.planTier
        accessMode = resolvedAccess.accessMode
        capabilities = resolvedAccess.capabilities
        limits = TuneAVAccessLimitPolicy.resolvedLimits(resolvedAccess.limits, accessMode: resolvedAccess.accessMode)
        if resolvedAccess.accessMode == .signedInPro {
            upgradePrompt = nil
        }
    }

    private func uiTestResolvedAccess() -> TuneAVResolvedAccess? {
        let uiTestEnvironment = TuneAVUITestEnvironment.current
        guard uiTestEnvironment.hasAccountOverride else { return nil }

        let mode: AccessMode = uiTestEnvironment.isProAccount ? .signedInPro : .signedInFree
        return .localFallback(for: mode)
    }

    private func presentUpgradePrompt(for feature: LimitedFeature) {
        upgradePrompt = UpgradePrompt.forLimitState(
            FeatureLimitState(
                feature: feature,
                currentUsage: dailyUsageLimiter.usageCount(for: dailyUsageFeature(for: feature)),
                limit: limits.limit(for: feature)
            )
        )
    }

    private func dailyUsageFeature(for feature: LimitedFeature) -> LimitedFeature {
        LimitedFeature.dailyUsageLimitedFeatures.contains(feature) ? .aviAction : feature
    }

    private func dailyUsageKey(for feature: LimitedFeature, usageKey: String) -> String {
        "\(feature.rawValue):\(TuneAVDailyUsageLimiter.normalizedUsageKey(usageKey))"
    }

    private func premiumFeature(
        for destination: TuneAVExternalSearchURL.Destination,
        suffix: String?
    ) -> LimitedFeature {
        switch destination {
        case .web:
            suffix == nil ? .webSearch : .lyricsSearch
        case .youtube:
            .youtubeSearch
        case .appleMusic:
            .appleMusicSearch
        case .spotify:
            .spotifySearch
        }
    }

    private func makeAppDataSyncClient() -> TuneAVAppDataSyncClient {
        TuneAVAppDataSyncClient(deviceId: "tuneav-mac") { [accountService] path, method, body, headers in
            guard let token = try await accountService.getToken(), !token.isEmpty else {
                throw TuneAVAppDataClientError.missingToken
            }

            guard let baseURL = TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL") else {
                throw TuneAVAppDataClientError.missingBaseURL
            }

            var request = URLRequest(url: Self.accountAPIURL(baseURL: baseURL, path: path))
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("tuneav", forHTTPHeaderField: "x-appsav-app-id")
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await TuneAVURLSessions.account.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                throw TuneAVAppDataClientError.requestFailed(statusCode: httpResponse.statusCode)
            }
            return data
        }
    }

    private nonisolated static func accountAPIURL(baseURL: URL, path: String) -> URL {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathAndQuery = sanitizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let url = baseURL.appending(path: String(pathAndQuery.first ?? ""))
        guard pathAndQuery.count == 2,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.percentEncodedQuery = String(pathAndQuery[1])
        return components.url ?? url
    }

    private func librarySnapshot() -> TuneAVLibrarySnapshot {
        let updatedAt = TuneAVDateCoding.string(from: localLibraryUpdatedAt)
        return TuneAVLibrarySnapshot(
            favorites: favoriteStations.map {
                FavoriteStationRecord(station: $0.appDataRecord, createdAt: updatedAt)
            },
            recents: recentStations.map {
                RecentStationRecord(station: $0.appDataRecord, lastPlayedAt: updatedAt)
            },
            discoveries: discoveredTracks.map(\.record),
            settings: AppSettingsRecord(
                preferredCountry: selectedSearchCountryCode ?? "",
                preferredLanguage: L10n.locale.language.languageCode?.identifier ?? "",
                preferredTag: activeSearchTag ?? "",
                lastPlayedStationID: currentStation?.id,
                sleepTimerMinutes: activeSleepTimerMinutes,
                openLastStationOnLaunch: true,
                autoSkipUnstableStreams: true,
                updatedAt: updatedAt
            )
        )
    }

    private func cloudBoundedSnapshot(_ snapshot: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: snapshot.favorites,
            recents: Array(snapshot.recents.prefix(24)),
            discoveries: Array(snapshot.discoveries.prefix(1_000)),
            settings: snapshot.settings
        )
    }

    private func applyLibrarySnapshot(_ snapshot: TuneAVLibrarySnapshot) {
        cloudSyncTrigger.setApplyingCloudSnapshot(true)
        defer { cloudSyncTrigger.setApplyingCloudSnapshot(false) }

        favoriteStations = snapshot.favorites
            .filter { $0.deletedAt == nil }
            .map { Station(record: $0.station) }

        recentStations = snapshot.recents
            .filter { $0.deletedAt == nil }
            .map { Station(record: $0.station) }

        discoveredTracks = snapshot.discoveries
            .compactMap(MacDiscoveredTrack.init(record:))
            .sorted { $0.playedAt > $1.playedAt }

        selectedSearchCountryCode = TuneAVCountry.sanitizedCode(snapshot.settings.preferredCountry)
        activeSearchTag = snapshot.settings.preferredTag.isEmpty ? nil : snapshot.settings.preferredTag

        storage.save(favoriteStations, forKey: TuneAVMacLibraryStorage.favoritesKey)
        storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(Date.now)
    }

    private func markLocalLibraryUpdated(_ date: Date = .now) {
        localLibraryUpdatedAt = date
        storage.saveDate(date, forKey: TuneAVMacLibraryStorage.localLibraryUpdatedAtKey)
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.localLibraryChanged(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil
            )
        )
    }

    private func handleCloudSyncTriggerAction(_ action: MacCloudSyncTrigger.Action) {
        switch action {
        case .schedule(let delay):
            scheduleCloudSync(delay: delay)
        case .cancel:
            pendingCloudSyncTask?.cancel()
            pendingCloudSyncTask = nil
        case .none:
            break
        }
    }

    private func scheduleCloudSync(delay: Duration) {
        pendingCloudSyncTask?.cancel()
        pendingCloudSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.synchronizeLibraryNow()
            } catch {
                return
            }
        }
    }

    private func sortedDiscoveries(_ discoveries: [MacDiscoveredTrack]) -> [MacDiscoveredTrack] {
        discoveries.sorted { first, second in
            first.playedAt > second.playedAt
        }
    }
}

struct MacHomeMoodGenreSuggestion: Hashable {
    let tag: String
    let title: String
}

struct TuneAVMacLibraryStorage {
    static let favoritesKey = "tuneav.mac.library.favorites"
    static let recentsKey = "tuneav.mac.library.recents"
    static let discoveriesKey = "tuneav.mac.library.discoveries"
    static let stationFeedbackKey = "tuneav.mac.library.stationFeedback"
    static let localLibraryUpdatedAtKey = "tuneav.mac.library.updatedAt"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadStations(forKey key: String) -> [Station] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? decoder.decode([Station].self, from: data)) ?? []
    }

    func save(_ stations: [Station], forKey key: String) {
        guard let data = try? encoder.encode(stations) else { return }
        defaults.set(data, forKey: key)
    }

    func loadDiscoveries() -> [MacDiscoveredTrack] {
        guard let data = defaults.data(forKey: Self.discoveriesKey) else { return [] }
        return ((try? decoder.decode([DiscoveredTrackRecord].self, from: data)) ?? [])
            .compactMap(MacDiscoveredTrack.init(record:))
            .sorted { $0.playedAt > $1.playedAt }
    }

    func saveDiscoveries(_ discoveries: [MacDiscoveredTrack]) {
        let records = discoveries.map(\.record)
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Self.discoveriesKey)
    }

    func loadStationFeedback() -> [String: TuneAVStationFeedback] {
        guard let data = defaults.data(forKey: Self.stationFeedbackKey) else { return [:] }
        return (try? decoder.decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
    }

    func saveStationFeedback(_ feedback: [String: TuneAVStationFeedback]) {
        guard let data = try? encoder.encode(feedback) else { return }
        defaults.set(data, forKey: Self.stationFeedbackKey)
    }

    func loadDate(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    func saveDate(_ date: Date, forKey key: String) {
        defaults.set(date, forKey: key)
    }
}

struct MacDiscoveredTrack: Identifiable, Equatable {
    let discoveryID: String
    var title: String
    var artist: String?
    var stationID: String
    var stationName: String
    var artworkURL: String?
    var stationArtworkURL: String?
    var playedAt: Date
    var markedInterestedAt: Date?
    var hiddenAt: Date?

    var id: String { discoveryID }

    init(
        title: String,
        artist: String?,
        station: Station,
        artworkURL: URL? = nil,
        playedAt: Date = .now,
        markedInterestedAt: Date? = nil,
        hiddenAt: Date? = nil
    ) {
        let normalizedArtist = TuneAVDiscoveredTrackSupport.normalizedValue(artist)
        let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(title) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.discoveryID = Self.makeID(title: normalizedTitle, artist: normalizedArtist, stationID: station.id)
        self.title = normalizedTitle
        self.artist = normalizedArtist
        self.stationID = station.id
        self.stationName = station.name
        self.artworkURL = artworkURL?.absoluteString
        self.stationArtworkURL = nil
        self.playedAt = playedAt
        self.markedInterestedAt = markedInterestedAt
        self.hiddenAt = hiddenAt
    }

    init?(record: DiscoveredTrackRecord) {
        guard record.deletedAt == nil else { return nil }
        let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(record.title) ?? record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        self.discoveryID = record.discoveryID
        self.title = normalizedTitle
        self.artist = TuneAVDiscoveredTrackSupport.normalizedValue(record.artist)
        self.stationID = record.stationID
        self.stationName = record.stationName
        self.artworkURL = record.artworkURL
        self.stationArtworkURL = record.stationArtworkURL
        self.playedAt = TuneAVDateCoding.date(from: record.playedAt)
        self.markedInterestedAt = record.markedInterestedAt.map(TuneAVDateCoding.date(from:))
        self.hiddenAt = record.hiddenAt.map(TuneAVDateCoding.date(from:))
    }

    static func makeID(title: String, artist: String?, stationID: String) -> String {
        TuneAVDiscoveredTrackSupport.makeID(title: title, artist: artist, stationID: stationID, locale: L10n.locale)
    }

    var record: DiscoveredTrackRecord {
        DiscoveredTrackRecord(
            discoveryID: discoveryID,
            title: title,
            artist: artist,
            stationID: stationID,
            stationName: stationName,
            artworkURL: artworkURL,
            stationArtworkURL: stationArtworkURL,
            playedAt: TuneAVDateCoding.string(from: playedAt),
            markedInterestedAt: markedInterestedAt.map(TuneAVDateCoding.string(from:)),
            hiddenAt: hiddenAt.map(TuneAVDateCoding.string(from:))
        )
    }
}

extension MacDiscoveredTrack: TuneAVMusicLibraryDiscovery {
    var isMarkedInteresting: Bool {
        markedInterestedAt != nil
    }

    var isHidden: Bool {
        hiddenAt != nil
    }

    var artistDisplayText: String {
        TuneAVDiscoveredTrackSupport.artistDisplayText(artist, liveFallback: L10n.string("player.track.liveNow"))
    }

    var searchQuery: String {
        TuneAVDiscoveredTrackSupport.searchQuery(title: title, artist: artist)
    }

    var resolvedArtworkURL: URL? {
        TuneAVDiscoveredTrackSupport.resolvedURL(artworkURL)
    }

    var resolvedStationArtworkURL: URL? {
        TuneAVDiscoveredTrackSupport.resolvedURL(stationArtworkURL)
    }
}

private extension Station {
    var macEnrichmentLookupKeys: [String] {
        var keys: [String] = []
        appendMacEnrichmentIDKeys(id, to: &keys)
        if let canonicalStationId {
            appendMacEnrichmentIDKeys(canonicalStationId, to: &keys)
        }
        if let streamKey = normalizedMacEnrichmentURLKey(streamURL) {
            keys.append("stream:\(streamKey)")
        }
        if let homepageURL, let homepageKey = normalizedMacEnrichmentURLKey(homepageURL) {
            keys.append("homepage:\(homepageKey)")
        }
        return keys
    }

    var macEnrichmentRank: Int {
        var rank = 0

        if canonicalStationId != nil { rank += 1 }
        if category != nil { rank += 1 }
        if visibility != nil { rank += 1 }
        if qualityScore != nil { rank += 1 }
        if enrichmentStatus == "enriched" { rank += 4 }
        else if enrichmentStatus != nil { rank += 1 }

        if let artwork, artwork.status != "none" || artwork.url != nil {
            rank += 2
        }

        if let editorial {
            rank += 6
            if editorial.discoveryProfile != nil { rank += 4 }
            rank += min(editorial.programming.count, 3)
            rank += min(editorial.audience.count, 2)
            rank += min(editorial.secondaryFormats.count, 2)
        }

        return rank
    }

    func isPreferredMacEnrichment(over current: Station?) -> Bool {
        guard let current else { return true }
        if let isNewer = metadataFreshnessCompared(to: current) {
            return isNewer
        }
        if displayArtworkURL != nil, current.displayArtworkURL == nil {
            return true
        }
        if displayArtworkURL == nil, current.displayArtworkURL != nil {
            return false
        }
        return macEnrichmentRank > current.macEnrichmentRank
    }

    private func appendMacEnrichmentIDKeys(_ rawID: String, to keys: inout [String]) {
        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        keys.append("id:\(trimmedID)")

        if trimmedID.hasPrefix("st_rb_") {
            let radioBrowserID = String(trimmedID.dropFirst("st_rb_".count)).replacingOccurrences(of: "_", with: "-")
            if radioBrowserID != trimmedID {
                keys.append("id:\(radioBrowserID)")
            }
        } else if trimmedID.contains("-") {
            keys.append("id:st_rb_\(trimmedID.replacingOccurrences(of: "-", with: "_"))")
        }
    }

    private func normalizedMacEnrichmentURLKey(_ rawURL: String) -> String? {
        guard
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        components.scheme = "stream"
        return components.string?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
