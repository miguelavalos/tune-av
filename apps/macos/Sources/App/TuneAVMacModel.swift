import AccountAV
import AVFoundation
import Combine
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
    private static let maxLocalTrackFeedbackRecords = 300

    @Published var selectedSection: MacRootSection = .home
    @Published var stationDetailRoute: MacStationDetailRoute?
    @Published var homeStationListRoute: MacHomeStationListRoute?
    @Published var musicDetailRoute: MacMusicDetailRoute?
    @Published private(set) var featuredStations: [Station] = Station.samples
    @Published private(set) var searchResults: [Station] = []
    @Published private(set) var favoriteStations: [Station] = []
    @Published private(set) var recentStations: [Station] = []
    @Published private(set) var stationFeedback: [String: TuneAVStationFeedback] = [:]
    @Published private(set) var trackFeedback: [String: TuneAVStationFeedback] = [:]
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
    @Published private(set) var isAccountSessionTemporarilyUnavailable = false
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
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private let systemNowPlayingController = MacNowPlayingSystemController()
    private let accountService = ClerkAccountAVService(
        publishableKeyProvider: { TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY") },
        keychainServiceProvider: { TuneAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE") },
        fallbackDisplayName: L10n.string("app.name"),
        loggerSubsystem: "com.avalsys.tuneav"
    )
    private var localLibraryUpdatedAt: Date = .distantPast
    private var latestLocalLibraryMutationAt: Date = .distantPast
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: TuneAVStreamMetadataDelegate?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerTimeControlObserver: NSKeyValueObservation?
    private var playbackNotificationObservers: [NSObjectProtocol] = []
    private var playbackFailuresInCurrentQueue = Set<String>()
    private var favoriteRecords: [FavoriteStationRecord] = []
    private var trackFeedbackRecords: [String: TuneAVLocalFeedbackRecord] = [:]
    private var libraryTombstones: [TuneAVLibraryTombstone] = []
    private var cloudSyncTrigger = MacCloudSyncTrigger()
    private var pendingCloudSyncTask: Task<Void, Never>?
    private var cloudSyncPollingTask: Task<Void, Never>?
    private var proRealtimeSessionTask: Task<Void, Never>?
    private var proRealtimeProjectionCancellable: AnyCancellable?
    private var activeProRealtimeSessionOwnerUserID: String?
    private let proLibraryObserver = TuneAVProLibraryObserver(deploymentURL: TuneAVMacConfig.tuneConvexURL)
    private var lastAppliedProRealtimeProjectionUpdatedAt: Double?
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerEndDate: Date?
    private var trackArtworkTask: Task<Void, Never>?
    private let dailyUsageLimiter = TuneAVDailyUsageLimiter(
        keyStyle: .dayBucket(prefix: "tuneav.featureUsage."),
        limitedFeatures: LimitedFeature.dailyUsageLimitedFeatures
    )
    private let accountUserDefaults = UserDefaults.standard
    private let lastKnownAccountUserKey = "tuneav.mac.account.lastKnownUser"

    init() {
        favoriteRecords = storage.loadFavoriteRecords()
        favoriteStations = favoriteRecords.map { Station(record: $0.station) }
        recentStations = storage.loadStations(forKey: TuneAVMacLibraryStorage.recentsKey)
        stationFeedback = storage.loadStationFeedback()
        trackFeedbackRecords = storage.loadTrackFeedbackRecords()
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        discoveredTracks = storage.loadDiscoveries()
        libraryTombstones = storage.loadTombstones()
        localLibraryUpdatedAt = storage.loadDate(forKey: TuneAVMacLibraryStorage.localLibraryUpdatedAtKey)
            ?? (favoriteStations.isEmpty && recentStations.isEmpty && discoveredTracks.isEmpty ? .distantPast : .now)
        latestLocalLibraryMutationAt = storage.loadDate(forKey: TuneAVMacLibraryStorage.localLibraryMutationAtKey)
            ?? (libraryTombstones.isEmpty ? .distantPast : localLibraryUpdatedAt)
        accountUser = Self.lastKnownAccountUser(from: accountUserDefaults)
        resolveLocalAccessState()
        configureSystemNowPlaying()
    }

    deinit {
        pendingCloudSyncTask?.cancel()
        cloudSyncPollingTask?.cancel()
        proRealtimeSessionTask?.cancel()
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
        var seenKeys = Set<String>()
        return (recentStations + favoriteStations).filter { station in
            seenKeys.insert(stationIdentityKey(for: station)).inserted
        }
    }

    func loadFeaturedStations() async {
        do {
            featuredStations = try await stationService.popularStations(
                filters: TuneAVStationSearchFilters(query: "", limit: 18, allowsEmptySearch: true)
            )
            rememberStationEnrichment(featuredStations)
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.discovery",
                operation: "load_featured",
                step: "popular_stations"
            )
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
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.discovery",
                operation: "search",
                step: query.isEmpty ? "browse" : "query",
                data: [
                    "has_query": String(!query.isEmpty),
                    "has_tag": String(!tag.isEmpty),
                    "has_country": String(!countryCode.isEmpty),
                    "mode": mode,
                ]
            )
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
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.discovery",
                operation: "load_more_search",
                step: "page",
                data: [
                    "has_query": String(!query.isEmpty),
                    "has_tag": String(!tag.isEmpty),
                    "has_country": String(!countryCode.isEmpty),
                    "mode": searchDiscoveryMode.rawValue,
                ]
            )
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
        if let feedbackKey = currentTrackFeedbackKey, let feedback = trackFeedback[feedbackKey] {
            return feedback
        }
        guard let currentDiscoveryIndex else { return nil }
        return discoveredTracks[currentDiscoveryIndex].hiddenAt == nil ? nil : .notForMe
    }

    func feedback(for discovery: MacDiscoveredTrack) -> TuneAVStationFeedback? {
        trackFeedback[Self.trackFeedbackKey(title: discovery.title, artist: discovery.artist)]
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

    private var currentTrackFeedbackKey: String? {
        guard let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackTitle) else {
            return nil
        }
        return Self.trackFeedbackKey(title: normalizedTitle, artist: TuneAVDiscoveredTrackSupport.normalizedValue(currentTrackArtist))
    }

    func play(_ station: Station, queue: [Station]? = nil, source: TuneAVPlaybackQueueSource? = nil) {
        guard let url = URL(string: station.streamURL) else {
            setPlaybackFailure(L10n.string("audio.error.invalidURL"), shouldAutoSkip: false)
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
        let identityKey = stationIdentityKey(for: station)
        if let existing = favoriteStations.first(where: { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }) {
            rememberFavoriteDeletion(for: existing)
            favoriteStations.removeAll { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }
            favoriteRecords.removeAll { TuneAVLibrarySnapshotMerger.stationIdentityKey($0.station) == identityKey }
        } else {
            removeTombstone(resource: "favorites", identityKey: identityKey)
            favoriteStations.insert(station, at: 0)
            favoriteRecords.removeAll { TuneAVLibrarySnapshotMerger.stationIdentityKey($0.station) == identityKey }
            favoriteRecords.insert(
                FavoriteStationRecord(
                    station: station.appDataRecord,
                    createdAt: TuneAVDateCoding.string(from: .now)
                ),
                at: 0
            )
        }
        storage.saveFavoriteRecords(favoriteRecords)
        markLocalLibraryUpdated(syncsCloud: true)
    }

    func isFavorite(_ station: Station) -> Bool {
        let identityKey = stationIdentityKey(for: station)
        return favoriteStations.contains { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        guard stationFeedback[station.id] != feedback else { return }
        stationFeedback[station.id] = feedback
        storage.saveStationFeedback(stationFeedback)
        syncProStationFeedback(feedback, stationID: station.id)
    }

    func clearFavorites(propagatesToCloud: Bool = true) {
        if propagatesToCloud {
            favoriteStations.forEach(rememberFavoriteDeletion(for:))
        }
        favoriteStations = []
        favoriteRecords = []
        storage.saveFavoriteRecords(favoriteRecords)
        markLocalLibraryUpdated(syncsCloud: propagatesToCloud)
    }

    func clearRecents() {
        recentStations = []
        storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        markLocalLibraryUpdated(syncsCloud: false)
    }

    func clearLocalLibraryData() {
        clearFavorites(propagatesToCloud: false)
        clearRecents()
        clearDiscoveredTracks(propagatesToCloud: false)
        libraryTombstones = []
        storage.saveTombstones(libraryTombstones)
        stationFeedback = [:]
        storage.saveStationFeedback(stationFeedback)
        trackFeedbackRecords = [:]
        trackFeedback = [:]
        storage.saveTrackFeedbackRecords(trackFeedbackRecords)
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
            removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
            discoveredTracks[index].playedAt = now
            discoveredTracks[index].markedInterestedAt = discoveredTracks[index].markedInterestedAt == nil ? now : nil
            discoveredTracks[index].hiddenAt = nil
            discoveredTracks[index].updatedAt = now
        } else {
            removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
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
        markLocalLibraryUpdated(syncsCloud: true)
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
        let feedbackKey = Self.trackFeedbackKey(title: normalizedTitle, artist: normalizedArtist)
        if let feedback {
            trackFeedbackRecords[feedbackKey] = TuneAVLocalFeedbackRecord(
                feedback: feedback,
                updatedAt: TuneAVDateCoding.string(from: now)
            )
        } else {
            trackFeedbackRecords[feedbackKey] = nil
        }
        trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(trackFeedbackRecords, maxCount: Self.maxLocalTrackFeedbackRecords)
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        storage.saveTrackFeedbackRecords(trackFeedbackRecords)

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discoveryID }) {
            discoveredTracks[index].playedAt = now
            discoveredTracks[index].hiddenAt = feedback == .notForMe ? now : nil
            discoveredTracks[index].updatedAt = now
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
        markLocalLibraryUpdated(syncsCloud: false)
        syncProTrackFeedback(feedback, title: normalizedTitle, artist: normalizedArtist, stationID: currentStation.id)
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for discovery: MacDiscoveredTrack) {
        let now = Date.now
        let feedbackKey = Self.trackFeedbackKey(title: discovery.title, artist: discovery.artist)
        if let feedback {
            trackFeedbackRecords[feedbackKey] = TuneAVLocalFeedbackRecord(
                feedback: feedback,
                updatedAt: TuneAVDateCoding.string(from: now)
            )
        } else {
            trackFeedbackRecords[feedbackKey] = nil
        }
        trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(trackFeedbackRecords, maxCount: Self.maxLocalTrackFeedbackRecords)
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        storage.saveTrackFeedbackRecords(trackFeedbackRecords)

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) {
            discoveredTracks[index].hiddenAt = feedback == .notForMe ? now : nil
            discoveredTracks[index].updatedAt = now
            discoveredTracks = sortedDiscoveries(discoveredTracks)
            storage.saveDiscoveries(discoveredTracks)
            markLocalLibraryUpdated(syncsCloud: false)
        }

        syncProTrackFeedback(feedback, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
    }

    func clearDiscoveredTracks(propagatesToCloud: Bool = true) {
        if propagatesToCloud {
            discoveredTracks.filter(\.isMarkedInteresting).forEach(rememberSavedDiscoveryDeletion(for:))
        }
        let removedSavedDiscovery = discoveredTracks.contains(where: \.isMarkedInteresting)
        discoveredTracks = []
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: propagatesToCloud && removedSavedDiscovery)
    }

    func toggleDiscoverySaved(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        if discoveredTracks[index].isMarkedInteresting {
            rememberSavedDiscoveryDeletion(for: discoveredTracks[index])
        } else {
            removeTombstone(resource: "savedDiscoveries", identityKey: discovery.discoveryID)
        }
        discoveredTracks[index].markedInterestedAt = discoveredTracks[index].markedInterestedAt == nil ? now : nil
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks[index].updatedAt = now
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: true)
    }

    func hideDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        discoveredTracks[index].hiddenAt = now
        discoveredTracks[index].updatedAt = now
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
    }

    func restoreDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks[index].updatedAt = now
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
    }

    func removeDiscovery(_ discovery: MacDiscoveredTrack) {
        if discovery.isMarkedInteresting {
            rememberSavedDiscoveryDeletion(for: discovery)
        }
        discoveredTracks.removeAll { $0.discoveryID == discovery.discoveryID }
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: discovery.isMarkedInteresting)
    }

    func startAutomaticLibrarySync() async {
        let restoredSessionIsActive = await restoreAccountSessionForAccessRefresh()
        if restoredSessionIsActive {
            await refreshAccessState()
        }
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.startupCompleted(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil,
                hasProAccess: hasProCloudSyncAccess
            )
        )
    }

    func refreshAccount() async {
        let restoredSessionIsActive = await restoreAccountSessionForAccessRefresh()
        guard restoredSessionIsActive else { return }
        await refreshAccessState()
    }

    func signInWithApple() async {
        await performAccountAction {
            try await accountService.signInWithApple()
        }
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.signInCompleted(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil,
                hasProAccess: hasProCloudSyncAccess
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
                hasUser: accountUser != nil,
                hasProAccess: hasProCloudSyncAccess
            )
        )
    }

    func signOut() async {
        handleCloudSyncTriggerAction(cloudSyncTrigger.signOutStarted())
        stopProRealtimeSync()
        await performAccountAction {
            try await accountService.signOut()
        }
        cloudSyncStatus = .idle
        accountUser = nil
        isAccountSessionTemporarilyUnavailable = false
        clearLastKnownAccountUser()
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
            cloudSyncErrorMessage = L10n.string("mac.sync.error.accountUnavailable")
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
            await refreshProFeedbackNow()
            cloudSyncStatus = .synced(lastCloudSyncAt ?? .now)
            if let accountUser {
                persistLastKnownAccountUser(accountUser)
            }
        } catch TuneAVAppDataClientError.missingToken {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.missingToken,
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "auth"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
        } catch TuneAVAppDataClientError.missingBaseURL {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.missingBaseURL,
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "configuration"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("mac.sync.error.missingBaseURL")
        } catch TuneAVAppDataClientError.requestFailed(let statusCode) where statusCode == 401 || statusCode == 403 {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.requestFailed(statusCode: statusCode),
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "http_status",
                data: ["status_code": String(statusCode)]
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
        } catch TuneAVAppDataClientError.requestFailed(let statusCode) {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.requestFailed(statusCode: statusCode),
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "http_status",
                data: ["status_code": String(statusCode)]
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.failed")
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "unknown"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.failed")
        }
    }

    private func startProRealtimeSyncIfNeeded() {
        guard hasProCloudSyncAccess else {
            stopProRealtimeSync()
            return
        }
        guard proLibraryObserver.isConfigured else { return }
        guard let ownerUserId = accountUser?.id, !ownerUserId.isEmpty else { return }
        guard activeProRealtimeSessionOwnerUserID != ownerUserId else { return }

        activeProRealtimeSessionOwnerUserID = ownerUserId
        proRealtimeSessionTask?.cancel()
        proRealtimeProjectionCancellable?.cancel()
        TuneAVRealtimeSessionStore.shared.clear()
        proLibraryObserver.clear()

        proRealtimeProjectionCancellable = proLibraryObserver.$projection
            .compactMap { $0 }
            .sink { [weak self] projection in
                Task { @MainActor [weak self] in
                    await self?.handleProRealtimeInvalidation(projection)
                }
            }

        proRealtimeSessionTask = Task { [weak self] in
            do {
                guard let self else { return }
                let realtimeSessionId = try await self.createRealtimeSession()
                guard self.accountUser?.id == ownerUserId,
                      self.hasProCloudSyncAccess else { return }
                TuneAVRealtimeSessionStore.shared.update(
                    ownerUserId: ownerUserId,
                    realtimeSessionId: realtimeSessionId
                )
                self.proLibraryObserver.observeLibraryProjection(ownerUserId: ownerUserId)
            } catch {
                await MainActor.run {
                    guard self?.activeProRealtimeSessionOwnerUserID == ownerUserId else { return }
                    self?.activeProRealtimeSessionOwnerUserID = nil
                    self?.proLibraryObserver.clear()
                    TuneAVMacDiagnostics.capture(
                        error,
                        feature: "tune.mac.sync",
                        operation: "pro_realtime",
                        step: "session"
                    )
                }
            }
        }
    }

    private func stopProRealtimeSync() {
        proRealtimeSessionTask?.cancel()
        proRealtimeSessionTask = nil
        proRealtimeProjectionCancellable?.cancel()
        proRealtimeProjectionCancellable = nil
        activeProRealtimeSessionOwnerUserID = nil
        lastAppliedProRealtimeProjectionUpdatedAt = nil
        TuneAVRealtimeSessionStore.shared.clear()
        proLibraryObserver.clear()
    }

    private func createRealtimeSession() async throws -> String {
        try await makeAccountAPIClient().createTuneAVRealtimeSession()
    }

    func fetchAccountDeletionSummary() async throws -> AccountSummary {
        try await accountRequest(path: "/v1/me")
    }

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        try await accountRequest(path: "/v1/me/delete-account-request", method: "POST")
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        try await accountRequest(path: "/v1/me/delete-account-finalize", method: "POST")
    }

    func signOutAfterAccountDeletion() async {
        await signOut()
    }

    private func recordRecent(_ station: Station) {
        let identityKey = stationIdentityKey(for: station)
        recentStations.removeAll { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }
        recentStations.insert(station, at: 0)
        recentStations = Array(recentStations.prefix(12))
        storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        markLocalLibraryUpdated(syncsCloud: false)
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
        favoriteRecords = favoriteRecords.map { record in
            let station = Station(record: record.station)
            guard let enriched = bestEnrichedStation(for: station, in: enrichedByKey),
                  enriched.isPreferredMacEnrichment(over: station)
            else {
                return record
            }
            didUpdateFavorites = true
            return FavoriteStationRecord(
                station: enriched.appDataRecord,
                createdAt: record.createdAt,
                deletedAt: record.deletedAt
            )
        }
        favoriteStations = favoriteRecords.map { Station(record: $0.station) }

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
            storage.saveFavoriteRecords(favoriteRecords)
        }
        if didUpdateRecents {
            storage.save(recentStations, forKey: TuneAVMacLibraryStorage.recentsKey)
        }
        markLocalLibraryUpdated(syncsCloud: didUpdateFavorites)
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
                ?? L10n.string("audio.error.streamLoadFailed")
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
            setPlaybackFailure(item.error?.localizedDescription ?? L10n.string("audio.error.streamLoadFailed"), shouldAutoSkip: true)
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
        TuneAVMacDiagnostics.capture(
            player.currentItem?.error ?? NSError(domain: "TuneAVMacAudio", code: 2),
            feature: "tune.mac.audio",
            operation: "playback",
            step: shouldAutoSkip ? "stream_failure" : "manual_failure",
            data: [
                "queue_source": String(describing: playbackQueueSource),
                "failed_count": String(playbackFailuresInCurrentQueue.count),
                "can_auto_skip": String(shouldAutoSkip),
            ]
        )
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
            discoveredTracks[index].updatedAt = now
        } else {
            discoveredTracks.insert(discovery, at: 0)
        }

        trimDiscoveriesToAccessLimit()
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
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
            _ = await restoreAccountSessionForAccessRefresh()
            resolveLocalAccessState()
            await refreshAccessState()
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.account",
                operation: "account_action",
                step: "provider"
            )
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
            let client = makeAccountAPIClient(
                baseURL: baseURL,
                tokenOverride: tokenOverride
            )
            let access = try await client.fetchTuneAVAccess()
            applyResolvedAccess(
                TuneAVResolvedAccess(
                    platformUserId: nil,
                    planTier: access.planTier,
                    accessMode: access.accessMode,
                    capabilities: access.capabilities,
                    limits: access.limits
                )
            )
            cloudSyncErrorMessage = nil
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.account",
                operation: "refresh_access",
                step: "access_client"
            )
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
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
        if let accountUser, resolvedAccess.accessMode != .guest {
            persistLastKnownAccountUser(accountUser)
        }
        if resolvedAccess.accessMode == .signedInPro {
            upgradePrompt = nil
            startCloudSyncPolling()
            startProRealtimeSyncIfNeeded()
        } else {
            stopCloudSyncPolling()
            stopProRealtimeSync()
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
        TuneAVAppDataSyncClient(deviceId: "tuneav-mac") { [weak self] path, method, body, headers in
            guard let self else { throw TuneAVAppDataClientError.missingToken }
            do {
                return try await self.makeAccountAPIClient().requestData(
                    path: path,
                    method: method,
                    body: body,
                    headers: headers
                )
            } catch TuneAVAccessClientError.missingToken {
                throw TuneAVAppDataClientError.missingToken
            } catch TuneAVAccessClientError.missingBaseURL {
                throw TuneAVAppDataClientError.missingBaseURL
            } catch TuneAVAccessClientError.requestFailed(let statusCode) {
                throw TuneAVAppDataClientError.requestFailed(statusCode: statusCode)
            } catch {
                throw error
            }
        }
    }

    private func syncProStationFeedback(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard accessMode == .signedInPro, accountService.isAvailable else { return }
        Task { [weak self] in
            do {
                try await self?.sendFeedbackRequest(
                    path: "/v1/tune/feedback/stations/\(stationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stationID)",
                    payload: TuneAVMacFeedbackRequest(deviceId: "tuneav-mac", feedback: feedback?.backendValue)
                )
            } catch {
                TuneAVMacDiagnostics.capture(
                    error,
                    feature: "tune.mac.sync",
                    operation: "station_feedback",
                    step: "upload"
                )
            }
        }
    }

    private func syncProTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String, artist: String?, stationID: String?) {
        guard accessMode == .signedInPro, accountService.isAvailable else { return }
        let key = Self.trackFeedbackKey(title: title, artist: artist)
        Task { [weak self] in
            do {
                try await self?.sendFeedbackRequest(
                    path: "/v1/tune/feedback/tracks/\(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)",
                    payload: TuneAVMacTrackFeedbackRequest(
                        deviceId: "tuneav-mac",
                        title: title,
                        artist: artist,
                        stationId: stationID,
                        feedback: feedback?.backendValue
                    )
                )
            } catch {
                TuneAVMacDiagnostics.capture(
                    error,
                    feature: "tune.mac.sync",
                    operation: "track_feedback",
                    step: "upload"
                )
            }
        }
    }

    private func sendFeedbackRequest<Payload: Encodable>(path: String, payload: Payload) async throws {
        _ = try await makeAccountAPIClient().requestData(
            path: path,
            method: "PUT",
            body: try JSONEncoder().encode(payload)
        )
    }

    private nonisolated static func trackFeedbackKey(title: String, artist: String?) -> String {
        [title, artist ?? ""]
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }

    private func accountRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        tokenOverride: String? = nil
    ) async throws -> T {
        try await makeAccountAPIClient(tokenOverride: tokenOverride).request(path: path, method: method)
    }

    private func makeAccountAPIClient(
        baseURL: URL? = TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL"),
        tokenOverride: String? = nil
    ) -> TuneAVAccessClient {
        TuneAVAccessClient(
            baseURL: baseURL,
            tokenProvider: { [self] in
                if let tokenOverride {
                    return tokenOverride
                }
                return try await accountService.getToken()
            },
            urlSession: TuneAVURLSessions.account
        )
    }

    private func librarySnapshot() -> TuneAVLibrarySnapshot {
        return TuneAVLibrarySnapshot(
            favorites: favoriteRecords + tombstoneRecords(resource: "favorites", type: FavoriteStationRecord.self),
            savedDiscoveries: discoveredTracks.filter(\.isMarkedInteresting).map(\.record)
                + tombstoneRecords(resource: "savedDiscoveries", type: DiscoveredTrackRecord.self)
        )
    }

    private func cloudBoundedSnapshot(_ snapshot: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: snapshot.favorites,
            savedDiscoveries: Array(snapshot.savedDiscoveries.filter { $0.deletedAt == nil }.prefix(1_000))
                + snapshot.savedDiscoveries.filter { $0.deletedAt != nil }
        )
    }

    private func applyLibrarySnapshot(_ snapshot: TuneAVLibrarySnapshot) {
        cloudSyncTrigger.setApplyingCloudSnapshot(true)
        defer { cloudSyncTrigger.setApplyingCloudSnapshot(false) }

        libraryTombstones = []

        for favorite in snapshot.favorites where favorite.deletedAt != nil {
            rememberTombstone(
                resource: "favorites",
                identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(favorite.station),
                payload: favorite,
                deletedAt: favorite.deletedAt.map(TuneAVDateCoding.date(from:)) ?? .now
            )
        }

        for discovery in snapshot.savedDiscoveries where discovery.deletedAt != nil {
            rememberTombstone(
                resource: "savedDiscoveries",
                identityKey: discovery.discoveryID,
                payload: discovery,
                deletedAt: discovery.deletedAt.map(TuneAVDateCoding.date(from:)) ?? .now
            )
        }

        favoriteRecords = snapshot.favorites
            .filter { $0.deletedAt == nil }

        favoriteStations = favoriteRecords
            .map { Station(record: $0.station) }

        let savedDiscoveriesByID = Dictionary(
            snapshot.savedDiscoveries.filter { $0.deletedAt == nil }.map { ($0.discoveryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let deletedSavedDiscoveryIDs = Set(snapshot.savedDiscoveries.compactMap { $0.deletedAt == nil ? nil : $0.discoveryID })
        var nextDiscoveries = discoveredTracks.map { discovery in
            var nextDiscovery = discovery
            if let savedRecord = savedDiscoveriesByID[discovery.discoveryID] {
                nextDiscovery = MacDiscoveredTrack(record: savedRecord) ?? discovery
            } else if deletedSavedDiscoveryIDs.contains(discovery.discoveryID) {
                nextDiscovery.markedInterestedAt = nil
            }
            return nextDiscovery
        }
        let existingDiscoveryIDs = Set(nextDiscoveries.map(\.discoveryID))
        nextDiscoveries.append(
            contentsOf: savedDiscoveriesByID.values
                .filter { !existingDiscoveryIDs.contains($0.discoveryID) }
                .compactMap(MacDiscoveredTrack.init(record:))
        )
        discoveredTracks = sortedDiscoveries(nextDiscoveries)

        storage.saveFavoriteRecords(favoriteRecords)
        storage.saveDiscoveries(discoveredTracks)
        storage.saveTombstones(libraryTombstones)
        markCloudLibraryApplied()
    }

    private func handleProRealtimeInvalidation(_ projection: TuneAVProLibraryProjection) async {
        if let lastAppliedProRealtimeProjectionUpdatedAt,
           projection.updatedAt <= lastAppliedProRealtimeProjectionUpdatedAt {
            return
        }

        lastAppliedProRealtimeProjectionUpdatedAt = projection.updatedAt
        if projection.resource?.hasPrefix("feedback.") == true {
            await refreshProFeedbackNow()
            return
        }

        await synchronizeLibraryNow()
    }

    private func refreshProFeedbackNow() async {
        guard accessMode == .signedInPro, accountService.isAvailable else { return }

        do {
            let snapshot: TuneAVFeedbackSnapshot = try await makeAccountAPIClient().request(path: "/v1/tune/feedback")
            applyProRealtimeFeedback(
                stationFeedback: snapshot.stationFeedback,
                trackFeedback: snapshot.trackFeedback
            )
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.sync",
                operation: "feedback_snapshot",
                step: "download"
            )
        }
    }

    func applyProRealtimeFeedback(
        stationFeedback remoteStationFeedback: [TuneAVStationFeedbackRecord],
        trackFeedback remoteTrackFeedback: [TuneAVTrackFeedbackRecord]
    ) {
        let nextStationFeedback = TuneAVRealtimeFeedbackProjection.stationFeedback(from: remoteStationFeedback)
        if nextStationFeedback != stationFeedback {
            stationFeedback = nextStationFeedback
            storage.saveStationFeedback(stationFeedback)
        }

        let nextTrackRecords = TuneAVRealtimeFeedbackProjection.trackFeedbackRecords(from: remoteTrackFeedback)
        if nextTrackRecords != trackFeedbackRecords {
            trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(nextTrackRecords, maxCount: Self.maxLocalTrackFeedbackRecords)
            trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
            storage.saveTrackFeedbackRecords(trackFeedbackRecords)
        }
    }

    private func rememberFavoriteDeletion(for station: Station) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "favorites",
            identityKey: stationIdentityKey(for: station),
            payload: FavoriteStationRecord(
                station: station.appDataRecord,
                deletedAt: TuneAVDateCoding.string(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
    }

    private func rememberSavedDiscoveryDeletion(for discovery: MacDiscoveredTrack) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "savedDiscoveries",
            identityKey: discovery.discoveryID,
            payload: DiscoveredTrackRecord(
                discoveryID: discovery.discoveryID,
                title: discovery.title,
                artist: discovery.artist,
                stationID: discovery.stationID,
                stationName: discovery.stationName,
                artworkURL: discovery.artworkURL,
                stationArtworkURL: discovery.stationArtworkURL,
                playedAt: TuneAVDateCoding.string(from: discovery.playedAt),
                markedInterestedAt: discovery.markedInterestedAt.map(TuneAVDateCoding.string(from:)),
                hiddenAt: discovery.hiddenAt.map(TuneAVDateCoding.string(from:)),
                deletedAt: TuneAVDateCoding.string(from: deletedAt),
                updatedAt: TuneAVDateCoding.string(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
    }

    private func rememberTombstone<Payload: Encodable>(
        resource: String,
        identityKey: String,
        payload: Payload,
        deletedAt: Date
    ) {
        libraryTombstones = TuneAVLibraryTombstoneCoding.upserting(
            resource: resource,
            identityKey: identityKey,
            payload: payload,
            deletedAt: deletedAt,
            into: libraryTombstones,
            encoder: tombstoneEncoder
        )
        storage.saveTombstones(libraryTombstones)
    }

    private func removeTombstone(resource: String, identityKey: String) {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        libraryTombstones.removeAll { $0.resourceKey == resourceKey }
        storage.saveTombstones(libraryTombstones)
    }

    private func hasTombstone(resource: String, identityKey: String) -> Bool {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        return libraryTombstones.contains { $0.resourceKey == resourceKey }
    }

    private func tombstoneRecords<Record: Decodable>(resource: String, type: Record.Type) -> [Record] {
        let retainedTombstones = libraryTombstones
            .filter { $0.resource == resource }
            .sorted { $0.deletedAt > $1.deletedAt }
            .prefix(1_000)
        return TuneAVLibraryTombstoneCoding.records(
            for: resource,
            in: Array(retainedTombstones),
            as: type,
            decoder: tombstoneDecoder
        )
    }

    private func stationIdentityKey(for station: Station) -> String {
        TuneAVLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }

    private func markLocalLibraryUpdated(_ date: Date = .now, syncsCloud: Bool = false) {
        localLibraryUpdatedAt = date
        latestLocalLibraryMutationAt = date
        storage.saveDate(date, forKey: TuneAVMacLibraryStorage.localLibraryUpdatedAtKey)
        storage.saveDate(date, forKey: TuneAVMacLibraryStorage.localLibraryMutationAtKey)
        guard syncsCloud else { return }
        handleCloudSyncTriggerAction(
            cloudSyncTrigger.localLibraryChanged(
                accountAvailable: accountService.isAvailable,
                hasUser: accountUser != nil,
                hasProAccess: hasProCloudSyncAccess
            )
        )
    }

    private func markCloudLibraryApplied(_ date: Date = .now) {
        localLibraryUpdatedAt = date
        storage.saveDate(date, forKey: TuneAVMacLibraryStorage.localLibraryUpdatedAtKey)
    }

    private var hasProCloudSyncAccess: Bool {
        accountUser != nil && accessMode == .signedInPro
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

    @discardableResult
    private func restoreAccountSessionForAccessRefresh() async -> Bool {
        switch await accountService.restoreSession() {
        case .active(let providerUser):
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.mac.account", operation: "restore_active")
            guard let user = await resolveInternalAccountUser(providerUser: providerUser) else {
                isAccountSessionTemporarilyUnavailable = true
                if accountUser == nil {
                    resolveLocalAccessState()
                }
                return false
            }
            accountUser = user
            TuneAVMacDiagnostics.setUserContext(id: user.id)
            isAccountSessionTemporarilyUnavailable = false
            persistLastKnownAccountUser(user)
            resolveLocalAccessState()
            return true
        case .temporarilyUnavailable:
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.mac.account", operation: "restore_temporarily_unavailable")
            isAccountSessionTemporarilyUnavailable = true
            resolveLocalAccessState()
            return false
        case .signedOut, .invalidated:
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.mac.account", operation: "restore_signed_out")
            accountUser = nil
            isAccountSessionTemporarilyUnavailable = false
            clearLastKnownAccountUser()
            TuneAVMacDiagnostics.clearUserContext()
            resolveLocalAccessState()
            return false
        }
    }

    private func resolveInternalAccountUser(providerUser: AccountAVUser) async -> AccountAVUser? {
        do {
            let summary: AccountSummary = try await accountRequest(path: "/v1/me")
            guard let id = summary.id, !id.isEmpty else {
                return nil
            }
            let displayName = summary.displayName.flatMap { value -> String? in
                value.isEmpty ? nil : value
            } ?? providerUser.displayName
            return AccountAVUser(
                id: id,
                displayName: displayName,
                emailAddress: summary.emailAddress ?? providerUser.emailAddress
            )
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.account",
                operation: "resolve_internal_user",
                step: "account_profile"
            )
            return nil
        }
    }

    private static func lastKnownAccountUser(from userDefaults: UserDefaults) -> AccountAVUser? {
        guard let data = userDefaults.data(forKey: "tuneav.mac.account.lastKnownUser"),
              let snapshot = try? JSONDecoder().decode(MacLastKnownAccountUser.self, from: data) else {
            return nil
        }
        return snapshot.accountUser
    }

    private func persistLastKnownAccountUser(_ user: AccountAVUser) {
        let snapshot = MacLastKnownAccountUser(user: user)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        accountUserDefaults.set(data, forKey: lastKnownAccountUserKey)
    }

    private func clearLastKnownAccountUser() {
        accountUserDefaults.removeObject(forKey: lastKnownAccountUserKey)
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

    private func startCloudSyncPolling() {
        guard cloudSyncPollingTask == nil else { return }
        cloudSyncPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    guard let self, self.hasProCloudSyncAccess, self.cloudSyncStatus != .syncing else { continue }
                    await self.synchronizeLibraryNow()
                } catch {
                    return
                }
            }
        }
    }

    private func stopCloudSyncPolling() {
        cloudSyncPollingTask?.cancel()
        cloudSyncPollingTask = nil
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

private struct MacLastKnownAccountUser: Codable {
    let id: String
    let displayName: String
    let emailAddress: String?

    init(user: AccountAVUser) {
        id = user.id
        displayName = user.displayName
        emailAddress = user.emailAddress
    }

    var accountUser: AccountAVUser {
        AccountAVUser(id: id, displayName: displayName, emailAddress: emailAddress)
    }
}

struct TuneAVMacLibraryStorage {
    static let favoritesKey = "tuneav.mac.library.favorites"
    static let favoriteRecordsKey = "tuneav.mac.library.favoriteRecords.v1"
    static let recentsKey = "tuneav.mac.library.recents"
    static let discoveriesKey = "tuneav.mac.library.discoveries"
    static let stationFeedbackKey = "tuneav.mac.library.stationFeedback"
    static let trackFeedbackKey = "tuneav.mac.library.trackFeedback.v1"
    static let tombstonesKey = "tuneav.mac.library.tombstones"
    static let localLibraryUpdatedAtKey = "tuneav.mac.library.updatedAt"
    static let localLibraryMutationAtKey = "tuneav.mac.library.localMutationAt.v1"

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

    func loadFavoriteRecords() -> [FavoriteStationRecord] {
        if let data = defaults.data(forKey: Self.favoriteRecordsKey),
           let records = try? decoder.decode([FavoriteStationRecord].self, from: data) {
            return records.filter { $0.deletedAt == nil }
        }

        let legacyStations = loadStations(forKey: Self.favoritesKey)
        guard !legacyStations.isEmpty else { return [] }
        let createdAt = loadDate(forKey: Self.localLibraryUpdatedAtKey)
            .map(TuneAVDateCoding.string(from:))
            ?? TuneAVDateCoding.string(from: .now)
        return legacyStations.map {
            FavoriteStationRecord(station: $0.appDataRecord, createdAt: createdAt)
        }
    }

    func saveFavoriteRecords(_ records: [FavoriteStationRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Self.favoriteRecordsKey)
        save(records.filter { $0.deletedAt == nil }.map { Station(record: $0.station) }, forKey: Self.favoritesKey)
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

    func loadTrackFeedbackRecords() -> [String: TuneAVLocalFeedbackRecord] {
        guard let data = defaults.data(forKey: Self.trackFeedbackKey) else { return [:] }
        if let records = try? decoder.decode([String: TuneAVLocalFeedbackRecord].self, from: data) {
            return records
        }
        let migrated = (try? decoder.decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
        return TuneAVLocalFeedbackStore.records(fromLegacy: migrated, updatedAt: .now)
    }

    func saveTrackFeedbackRecords(_ feedback: [String: TuneAVLocalFeedbackRecord]) {
        guard !feedback.isEmpty else {
            defaults.removeObject(forKey: Self.trackFeedbackKey)
            return
        }
        guard let data = try? encoder.encode(feedback) else { return }
        defaults.set(data, forKey: Self.trackFeedbackKey)
    }

    func loadTombstones() -> [TuneAVLibraryTombstone] {
        guard let data = defaults.data(forKey: Self.tombstonesKey) else { return [] }
        return (try? decoder.decode([TuneAVLibraryTombstone].self, from: data)) ?? []
    }

    func saveTombstones(_ tombstones: [TuneAVLibraryTombstone]) {
        guard let data = try? encoder.encode(tombstones) else { return }
        defaults.set(data, forKey: Self.tombstonesKey)
    }

    func loadDate(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    func saveDate(_ date: Date, forKey key: String) {
        defaults.set(date, forKey: key)
    }
}

private struct TuneAVMacFeedbackRequest: Encodable {
    let deviceId: String
    let feedback: String?
}

private struct TuneAVMacTrackFeedbackRequest: Encodable {
    let deviceId: String
    let title: String
    let artist: String?
    let stationId: String?
    let feedback: String?
}

private extension TuneAVStationFeedback {
    var backendValue: String {
        switch self {
        case .liked:
            return "liked"
        case .notForMe:
            return "not_for_me"
        case .disliked:
            return "disliked"
        }
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
    var updatedAt: Date

    var id: String { discoveryID }

    init(
        title: String,
        artist: String?,
        station: Station,
        artworkURL: URL? = nil,
        playedAt: Date = .now,
        markedInterestedAt: Date? = nil,
        hiddenAt: Date? = nil,
        updatedAt: Date? = nil
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
        self.updatedAt = updatedAt ?? [playedAt, markedInterestedAt, hiddenAt].compactMap { $0 }.max() ?? playedAt
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
        self.updatedAt = record.updatedAt.map(TuneAVDateCoding.date(from:))
            ?? [playedAt, markedInterestedAt, hiddenAt].compactMap { $0 }.max()
            ?? playedAt
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
            hiddenAt: hiddenAt.map(TuneAVDateCoding.string(from:)),
            updatedAt: TuneAVDateCoding.string(from: updatedAt)
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
