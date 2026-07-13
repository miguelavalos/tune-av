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

    var analyticsSource: String {
        switch self {
        case .searchResults:
            return "search"
        case .libraryFavorites, .libraryRecents:
            return "library"
        case .homeRecents, .homeFavorites, .homeDiscovery:
            return "home"
        case .singleStation:
            return "player"
        }
    }
}

@MainActor
final class TuneAVMacModel: ObservableObject {
    enum SubscriptionReconciliationSource: Equatable {
        case purchase
        case restore
        case redeemCode
    }

    private enum CloudLibraryItemOperation: Equatable {
        case upsert
        case delete
    }

    private static let maxLocalTrackFeedbackRecords = 300
    private static let librarySyncRetryBaseDelay: TimeInterval = 5
    private static let librarySyncRetryMaxDelay: TimeInterval = 120
    private static let librarySyncRetryJitterFraction = 0.2
    private static let feedbackSyncRetryBaseDelay: TimeInterval = 5
    private static let feedbackSyncRetryMaxDelay: TimeInterval = 120
    private static let feedbackSyncRetryJitterFraction = 0.2
    private static let listeningSessionMinimumDuration: TimeInterval = 10
    private static let listeningSessionBatchSize = 5
    private static let maxPendingListeningSessions = 50
    private static let pendingListeningSessionMaxAge: TimeInterval = 60 * 60 * 24 * 7
    private static let listeningSessionRetryBaseDelay: TimeInterval = 30
    private static let listeningSessionRetryMaxDelay: TimeInterval = 300
    private static let listeningSessionRetryJitterFraction = 0.2

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
    @Published private(set) var tunedTrackDiscoveries: [MacDiscoveredTrack] = []
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
    @Published private(set) var subscriptionOffer: MacTuneAVSubscriptionOffer?
    @Published private(set) var subscriptionError: MacTuneAVSubscriptionPurchaseError?
    @Published private(set) var isSubscriptionOperationInProgress = false
    @Published private(set) var isWaitingForSubscriptionReconciliation = false
    @Published private(set) var subscriptionReconciliationSource: SubscriptionReconciliationSource?
    @Published private(set) var isAccountOperationInProgress = false
    @Published private(set) var isRefreshingAccountAccess = false
    @Published var upgradePrompt: UpgradePrompt?
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle
    @Published private(set) var lastCloudSyncAt: Date?
    @Published var errorMessage: String?
    @Published var cloudSyncErrorMessage: String?

    private let stationService = TuneAVStationService()
    private let player = AVPlayer()
    private let trackArtworkService = TuneAVTrackArtworkService()
    private let storage: TuneAVMacLibraryStorage
    private let subscriptionPurchasing: MacTuneAVSubscriptionPurchasing
    private let promotionCodeRedeemer: TuneAVPromotionCodeRedeeming?
    private let subscriptionReconciliationRetryDelaysNanoseconds: [UInt64]
    private let sleepNanoseconds: (UInt64) async -> Void
    private let listeningAnalyticsUploadEnabled: Bool
    private let syncMutationGate = TuneAVSyncMutationGate()
    private let nowProvider: () -> Date
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private let systemNowPlayingController = MacNowPlayingSystemController()
    private let accountService = ClerkAccountAVService(
        publishableKeyProvider: { TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY") },
        keychainServiceProvider: { TuneAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE") },
        keychainAccessGroupProvider: { TuneAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP") },
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
    private var pendingLibraryOperations: [String: TuneAVMacPendingLibraryOperation] = [:]
    private var librarySyncTasks: [String: Task<Void, Never>] = [:]
    private var librarySyncTokens: [String: UUID] = [:]
    private var librarySyncRetryCounts: [String: Int] = [:]
    private var deferredLibrarySyncKeys = Set<String>()
    private var activePendingLibraryOperationUserID: String?
    private var trackFeedbackRecords: [String: TuneAVLocalFeedbackRecord] = [:]
    private var pendingFeedbackUploads: [String: TuneAVMacPendingFeedbackUpload] = [:]
    private var feedbackSyncTasks: [String: Task<Void, Never>] = [:]
    private var feedbackSyncTokens: [String: UUID] = [:]
    private var feedbackSyncRetryCounts: [String: Int] = [:]
    private var deferredFeedbackSyncKeys = Set<String>()
    private var activePendingFeedbackUploadUserID: String?
    private var activeListeningSession: TuneAVMacActiveListeningSession?
    private var pendingListeningSessions: [TuneAVMacListeningSessionDraft] = []
    private var listeningSessionUploadTask: Task<Void, Never>?
    private var listeningSessionFlushTask: Task<Void, Never>?
    private var listeningSessionFlushToken: UUID?
    private var listeningSessionUploadRetryCount = 0
    private var listeningSessionUploadsDeferred = false
    private var listeningSessionRetryAfterDelay: TimeInterval?
    private var libraryTombstones: [TuneAVLibraryTombstone] = []
    private var cloudSyncTrigger = MacCloudSyncTrigger()
    private var cloudSyncExecutionGate = MacCloudSyncExecutionGate()
    private var proRealtimeBootstrapGate = MacProRealtimeBootstrapGate()
    private var pendingCloudSyncTask: Task<Void, Never>?
    private var proRealtimeProjectionCancellable: AnyCancellable?
    private var activeProRealtimeSessionOwnerUserID: String?
    private var accountAccessRefreshGeneration = 0
    private let proLibraryObserver = TuneAVProLibraryObserver(deploymentURL: TuneAVMacConfig.tuneConvexURL)
    private let realtimeSessionSupervisor = TuneAVRealtimeSessionSupervisor()
    private var proRealtimeProjectionCursor = TuneAVProRealtimeProjectionCursor()
    private var cloudLibrarySourceUpdatedAtByResource: [String: Date] = [:]
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerEndDate: Date?
    private var trackArtworkTask: Task<Void, Never>?
    private let dailyUsageLimiter = TuneAVDailyUsageLimiter(
        keyStyle: .dayBucket(prefix: "tuneav.featureUsage."),
        limitedFeatures: LimitedFeature.dailyUsageLimitedFeatures
    )
    private let accountUserDefaults = UserDefaults.standard
    private let lastKnownAccountUserKey = "tuneav.mac.account.lastKnownUser"

    init(
        subscriptionPurchasing: MacTuneAVSubscriptionPurchasing? = nil,
        promotionCodeRedeemer: TuneAVPromotionCodeRedeeming? = nil,
        subscriptionReconciliationRetryDelaysNanoseconds: [UInt64] = [
            1_000_000_000,
            2_000_000_000,
            3_000_000_000,
            5_000_000_000
        ],
        storage: TuneAVMacLibraryStorage = TuneAVMacLibraryStorage(),
        listeningAnalyticsUploadEnabled: Bool = TuneAVMacConfig.isListeningAnalyticsUploadEnabled,
        nowProvider: @escaping () -> Date = { .now },
        sleepNanoseconds: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.subscriptionPurchasing = subscriptionPurchasing
            ?? (TuneAVUITestEnvironment.current.shouldUseSubscriptionPurchasingStub
                ? MacUITestTuneAVSubscriptionPurchasing()
                : MacRevenueCatTuneAVSubscriptionPurchasing())
        self.promotionCodeRedeemer = promotionCodeRedeemer
        self.subscriptionReconciliationRetryDelaysNanoseconds = subscriptionReconciliationRetryDelaysNanoseconds
        self.storage = storage
        self.listeningAnalyticsUploadEnabled = listeningAnalyticsUploadEnabled
        self.nowProvider = nowProvider
        self.sleepNanoseconds = sleepNanoseconds
        favoriteRecords = storage.loadFavoriteRecords()
        favoriteStations = favoriteRecords.map { Station(record: $0.station) }
        pendingLibraryOperations = storage.loadPendingLibraryOperations()
        recentStations = storage.loadStations(forKey: TuneAVMacLibraryStorage.recentsKey)
        stationFeedback = storage.loadStationFeedback()
        trackFeedbackRecords = storage.loadTrackFeedbackRecords()
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        pendingFeedbackUploads = storage.loadPendingFeedbackUploads()
        pendingListeningSessions = TuneAVMacListeningSessionOutbox.bounded(
            storage.loadPendingListeningSessions(),
            maxCount: Self.maxPendingListeningSessions,
            maxAge: Self.pendingListeningSessionMaxAge,
            now: nowProvider()
        )
        storage.savePendingListeningSessions(pendingListeningSessions)
        discoveredTracks = storage.loadDiscoveries()
        refreshTunedTrackDiscoveries()
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
        librarySyncTasks.values.forEach { $0.cancel() }
        feedbackSyncTasks.values.forEach { $0.cancel() }
        listeningSessionUploadTask?.cancel()
        listeningSessionFlushTask?.cancel()
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

        if let activeListeningSession, activeListeningSession.station.id != station.id {
            flushActiveListeningSession(endedReason: .stationChanged)
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
        flushActiveListeningSession(endedReason: .paused)
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

    func prepareForTermination() {
        flushActiveListeningSession(endedReason: .appClosed, schedulesUpload: false)
        stopListeningSessionUploads()
        stopProRealtimeSync()
    }

    func prepareForSystemSleep() {
        flushActiveListeningSession(endedReason: .appBackgrounded, schedulesUpload: false)
        stopListeningSessionUploads()
        pauseProRealtimeSync()
    }

    func resumeAfterSystemWake() {
        resumeListeningSessionIfEligible()
        schedulePendingListeningSessionUploadsForCurrentUser()
        startProRealtimeSyncIfNeeded()
    }

    func prepareForAppInactivity() {
        pauseProRealtimeSync()
    }

    func resumeAfterAppActivation() {
        startProRealtimeSyncIfNeeded()
    }

    func flushPendingListeningSessions() {
        flushListeningSessionUploads()
    }

    func toggleFavorite(_ station: Station) {
        let identityKey = stationIdentityKey(for: station)
        let operation: (CloudLibraryItemOperation, FavoriteStationRecord)
        if let existing = favoriteStations.first(where: { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }) {
            operation = (.delete, rememberFavoriteDeletion(for: existing))
            favoriteStations.removeAll { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }
            favoriteRecords.removeAll { TuneAVLibrarySnapshotMerger.stationIdentityKey($0.station) == identityKey }
        } else {
            let record = FavoriteStationRecord(
                station: station.appDataRecord,
                createdAt: TuneAVDateCoding.string(from: .now)
            )
            removeTombstone(resource: "favorites", identityKey: identityKey)
            favoriteStations.insert(station, at: 0)
            favoriteRecords.removeAll { TuneAVLibrarySnapshotMerger.stationIdentityKey($0.station) == identityKey }
            favoriteRecords.insert(record, at: 0)
            operation = (.upsert, record)
        }
        storage.saveFavoriteRecords(favoriteRecords)
        markLocalLibraryUpdated(syncsCloud: true)
        enqueueFavoriteLibraryOperation(operation.0, record: operation.1)
    }

    func isFavorite(_ station: Station) -> Bool {
        let identityKey = stationIdentityKey(for: station)
        return favoriteStations.contains { $0.id == station.id || stationIdentityKey(for: $0) == identityKey }
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        guard stationFeedback[station.id] != feedback else { return }
        stationFeedback[station.id] = feedback
        storage.saveStationFeedback(stationFeedback)
        enqueueStationFeedbackUpload(feedback, stationID: station.id)
    }

    func clearFavorites(propagatesToCloud: Bool = false) {
        if propagatesToCloud {
            favoriteStations.forEach { _ = rememberFavoriteDeletion(for: $0) }
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
        refreshTunedTrackDiscoveries()
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
        let discoveryIdentityKey = Self.savedDiscoveryIdentityKey(title: normalizedTitle, artist: normalizedArtist)
        let now = Date.now
        var operation: (CloudLibraryItemOperation, DiscoveredTrackRecord)?

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discoveryID }) {
            let wasSaved = discoveredTracks[index].isMarkedInteresting
            if wasSaved {
                operation = (.delete, rememberSavedDiscoveryDeletion(for: discoveredTracks[index]))
            } else {
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryIdentityKey)
            }
            discoveredTracks[index].playedAt = now
            discoveredTracks[index].markedInterestedAt = wasSaved ? nil : now
            discoveredTracks[index].hiddenAt = nil
            discoveredTracks[index].updatedAt = now
            if !wasSaved {
                operation = (.upsert, discoveredTracks[index].record)
            }
        } else {
            removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
            removeTombstone(resource: "savedDiscoveries", identityKey: discoveryIdentityKey)
            let discovery = MacDiscoveredTrack(
                title: normalizedTitle,
                artist: normalizedArtist,
                station: currentStation,
                playedAt: now,
                markedInterestedAt: now
            )
            discoveredTracks.insert(discovery, at: 0)
            operation = (.upsert, discovery.record)
        }

        discoveredTracks = sortedDiscoveries(discoveredTracks)
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: true)
        if let operation {
            enqueueSavedDiscoveryLibraryOperation(operation.0, record: operation.1)
        }
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
                updatedAt: TuneAVDateCoding.string(from: now),
                title: normalizedTitle,
                artist: normalizedArtist,
                stationID: currentStation.id
            )
        } else {
            trackFeedbackRecords[feedbackKey] = nil
        }
        trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(trackFeedbackRecords, maxCount: Self.maxLocalTrackFeedbackRecords)
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        refreshTunedTrackDiscoveries()
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
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
        enqueueTrackFeedbackUpload(feedback, title: normalizedTitle, artist: normalizedArtist, stationID: currentStation.id)
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for discovery: MacDiscoveredTrack) {
        let now = Date.now
        let feedbackKey = Self.trackFeedbackKey(title: discovery.title, artist: discovery.artist)
        if let feedback {
            trackFeedbackRecords[feedbackKey] = TuneAVLocalFeedbackRecord(
                feedback: feedback,
                updatedAt: TuneAVDateCoding.string(from: now),
                title: discovery.title,
                artist: discovery.artist,
                stationID: discovery.stationID
            )
        } else {
            trackFeedbackRecords[feedbackKey] = nil
        }
        trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(trackFeedbackRecords, maxCount: Self.maxLocalTrackFeedbackRecords)
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        refreshTunedTrackDiscoveries()
        storage.saveTrackFeedbackRecords(trackFeedbackRecords)

        if let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) {
            discoveredTracks[index].hiddenAt = feedback == .notForMe ? now : nil
            discoveredTracks[index].updatedAt = now
            discoveredTracks = sortedDiscoveries(discoveredTracks)
            refreshTunedTrackDiscoveries()
            storage.saveDiscoveries(discoveredTracks)
            markLocalLibraryUpdated(syncsCloud: false)
        }

        enqueueTrackFeedbackUpload(feedback, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
    }

    func clearDiscoveredTracks(propagatesToCloud: Bool = false) {
        if propagatesToCloud {
            discoveredTracks.filter(\.isMarkedInteresting).forEach { _ = rememberSavedDiscoveryDeletion(for: $0) }
        }
        let removedSavedDiscovery = discoveredTracks.contains(where: \.isMarkedInteresting)
        discoveredTracks = []
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: propagatesToCloud && removedSavedDiscovery)
    }

    func toggleDiscoverySaved(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        let wasSaved = discoveredTracks[index].isMarkedInteresting
        var operation: (CloudLibraryItemOperation, DiscoveredTrackRecord)?
        if wasSaved {
            operation = (.delete, rememberSavedDiscoveryDeletion(for: discoveredTracks[index]))
        } else {
            removeTombstone(resource: "savedDiscoveries", identityKey: discovery.discoveryID)
            removeTombstone(resource: "savedDiscoveries", identityKey: savedDiscoveryIdentityKey(for: discovery))
        }
        discoveredTracks[index].markedInterestedAt = wasSaved ? nil : now
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks[index].updatedAt = now
        if !wasSaved {
            operation = (.upsert, discoveredTracks[index].record)
        }
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: true)
        if let operation {
            enqueueSavedDiscoveryLibraryOperation(operation.0, record: operation.1)
        }
    }

    func hideDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        discoveredTracks[index].hiddenAt = now
        discoveredTracks[index].updatedAt = now
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
    }

    func restoreDiscovery(_ discovery: MacDiscoveredTrack) {
        guard let index = discoveredTracks.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        let now = Date.now
        discoveredTracks[index].hiddenAt = nil
        discoveredTracks[index].updatedAt = now
        discoveredTracks = sortedDiscoveries(discoveredTracks)
        refreshTunedTrackDiscoveries()
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: false)
    }

    func removeDiscovery(_ discovery: MacDiscoveredTrack) {
        let wasSaved = discovery.isMarkedInteresting
        let operationRecord = wasSaved ? rememberSavedDiscoveryDeletion(for: discovery) : nil
        discoveredTracks.removeAll { $0.discoveryID == discovery.discoveryID }
        storage.saveDiscoveries(discoveredTracks)
        markLocalLibraryUpdated(syncsCloud: wasSaved)
        if let operationRecord {
            enqueueSavedDiscoveryLibraryOperation(.delete, record: operationRecord)
        }
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
        flushActiveListeningSession(endedReason: .appClosed)
        handleCloudSyncTriggerAction(cloudSyncTrigger.signOutStarted())
        stopProRealtimeSync()
        stopPendingLibraryOperations()
        stopPendingFeedbackUploads()
        stopListeningSessionUploads()
        await performAccountAction {
            try await accountService.signOut()
        }
        cloudSyncStatus = .idle
        accountUser = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        isAccountSessionTemporarilyUnavailable = false
        clearLastKnownAccountUser()
        resolveLocalAccessState()
    }

    func loadMonthlySubscriptionOffer() async {
        guard accountUser != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        do {
            subscriptionOffer = try await subscriptionPurchasing.loadMonthlyOffer(for: accountUser)
            subscriptionError = nil
        } catch let error as MacTuneAVSubscriptionPurchaseError {
            subscriptionError = error
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.subscription",
                operation: "load_offer",
                step: "unknown"
            )
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    func purchaseMonthlyPro() async {
        await runSubscriptionOperation(source: .purchase) {
            try await subscriptionPurchasing.purchaseMonthlyPro(for: accountUser)
        }
    }

    func restorePurchases() async {
        await runSubscriptionOperation(source: .restore) {
            try await subscriptionPurchasing.restorePurchases(for: accountUser)
        }
    }

    func claimPromotionCode(_ code: String) async throws {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return }
        guard accountUser != nil else {
            subscriptionError = .missingAccountUser
            throw MacTuneAVSubscriptionPurchaseError.missingAccountUser
        }

        isSubscriptionOperationInProgress = true
        subscriptionError = nil
        defer {
            isSubscriptionOperationInProgress = false
        }

        do {
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "redeem_code")
            _ = try await makePromotionCodeRedeemer().redeemPromotionCode(normalizedCode)
            isWaitingForSubscriptionReconciliation = true
            subscriptionReconciliationSource = .redeemCode
            await refreshAccessState()
            await retrySubscriptionReconciliationIfNeeded()
        } catch let error as MacTuneAVSubscriptionPurchaseError {
            subscriptionError = error
            throw error
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.subscription",
                operation: "redeem_code",
                step: "backend"
            )
            let mappedError = MacTuneAVSubscriptionPurchaseError.underlying(error.localizedDescription)
            subscriptionError = mappedError
            throw mappedError
        }
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
        guard cloudSyncExecutionGate.begin() else { return }
        let bootstrapOwnerUserID = proRealtimeBootstrapGate.ownerUserID
        var bootstrapSucceeded = false
        defer {
            cloudSyncExecutionGate.finish()
            proRealtimeBootstrapGate.complete(
                ownerUserID: bootstrapOwnerUserID,
                succeeded: bootstrapSucceeded
            )
        }

        bootstrapSucceeded = await performLibrarySyncNow()
        if cloudSyncExecutionGate.consumePendingFollowUp() {
            let followUpSucceeded = await performLibrarySyncNow()
            bootstrapSucceeded = bootstrapSucceeded && followUpSucceeded
        }
    }

    private func synchronizeLibraryResourceNow(_ resource: TuneAVAppDataResource) async {
        guard cloudSyncExecutionGate.begin() else { return }
        _ = await performLibraryResourceRefreshNow(resource)
        if cloudSyncExecutionGate.consumePendingFollowUp() {
            _ = await performLibrarySyncNow()
        }
        cloudSyncExecutionGate.finish()
    }

    private func performLibrarySyncNow() async -> Bool {
        guard accountService.isAvailable else {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("mac.sync.error.accountUnavailable")
            return false
        }

        do {
            cloudSyncStatus = .syncing
            cloudSyncErrorMessage = nil
            let client = makeAppDataSyncClient()
            let localSnapshot = librarySnapshot()
            let remoteDocument = try await client.pullLibrary()
            cloudLibrarySourceUpdatedAtByResource = remoteDocument.sourceUpdatedAtByResource
            let snapshotToApply: TuneAVLibrarySnapshot

            switch TuneAVLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalLibraryMutationAt,
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                snapshotToApply = cloudBoundedSnapshot(
                    TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                )
                applyLibrarySnapshot(snapshotToApply)
                if snapshotToApply != remoteSnapshot {
                    try await syncMutationGate.withPermit {
                        try await client.pushLibrary(snapshotToApply)
                    }
                }
            case .pushLocal:
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToApply = cloudBoundedSnapshot(
                        TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                    )
                } else {
                    snapshotToApply = cloudBoundedSnapshot(localSnapshot)
                }
                try await syncMutationGate.withPermit {
                    try await client.pushLibrary(snapshotToApply)
                }
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
            if let accountUser {
                persistLastKnownAccountUser(accountUser)
            }
            return true
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
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) where statusCode == 401 || statusCode == 403 {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.requestFailed(statusCode: statusCode),
                feature: "tune.mac.sync",
                operation: "synchronize_library",
                step: "http_status",
                data: ["status_code": String(statusCode)]
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) {
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
        return false
    }

    private func performLibraryResourceRefreshNow(_ resource: TuneAVAppDataResource) async -> Bool {
        guard accountService.isAvailable else {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("mac.sync.error.accountUnavailable")
            return false
        }

        do {
            cloudSyncStatus = .syncing
            cloudSyncErrorMessage = nil
            let client = makeAppDataSyncClient()
            let localSnapshot = librarySnapshot()
            let remoteDocument = try await client.pullLibraryResource(
                resource,
                mergingInto: localSnapshot
            )
            let snapshotToApply = cloudBoundedSnapshot(
                TuneAVLibrarySnapshotMerger.merged(
                    local: localSnapshot,
                    remote: remoteDocument.snapshot
                )
            )
            applyLibrarySnapshot(snapshotToApply)
            cloudLibrarySourceUpdatedAtByResource[resource.rawValue] = remoteDocument.updatedAt
            lastCloudSyncAt = .now
            cloudSyncStatus = .synced(lastCloudSyncAt ?? .now)
            if let accountUser {
                persistLastKnownAccountUser(accountUser)
            }
            return true
        } catch TuneAVAppDataClientError.missingToken {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.missingToken,
                feature: "tune.mac.sync",
                operation: "refresh_library_resource",
                step: "auth"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
        } catch TuneAVAppDataClientError.missingBaseURL {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.missingBaseURL,
                feature: "tune.mac.sync",
                operation: "refresh_library_resource",
                step: "configuration"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("mac.sync.error.missingBaseURL")
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) where statusCode == 401 || statusCode == 403 {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.requestFailed(statusCode: statusCode),
                feature: "tune.mac.sync",
                operation: "refresh_library_resource",
                step: "http_status",
                data: ["status_code": String(statusCode)]
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.signInAgain")
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) {
            TuneAVMacDiagnostics.capture(
                TuneAVAppDataClientError.requestFailed(statusCode: statusCode),
                feature: "tune.mac.sync",
                operation: "refresh_library_resource",
                step: "http_status",
                data: ["status_code": String(statusCode)]
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.failed")
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.mac.sync",
                operation: "refresh_library_resource",
                step: "unknown"
            )
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = L10n.string("profile.sync.detail.failed")
        }
        return false
    }

    private func startProRealtimeSyncIfNeeded() {
        guard hasProCloudSyncAccess else {
            stopProRealtimeSync()
            return
        }
        guard proLibraryObserver.isConfigured else { return }
        guard let ownerUserId = accountUser?.id, !ownerUserId.isEmpty else { return }
        if activeProRealtimeSessionOwnerUserID == ownerUserId,
           proRealtimeProjectionCancellable != nil {
            return
        }

        let shouldResetProjectionState = MacProRealtimeProjectionStatePolicy.shouldReset(
            previousOwnerUserID: activeProRealtimeSessionOwnerUserID,
            nextOwnerUserID: ownerUserId
        )
        if shouldResetProjectionState {
            proRealtimeProjectionCursor.reset()
            cloudLibrarySourceUpdatedAtByResource.removeAll()
            TuneAVRealtimeSessionStore.shared.clear()
        }
        activeProRealtimeSessionOwnerUserID = ownerUserId
        proRealtimeProjectionCancellable?.cancel()
        proLibraryObserver.clear()

        proRealtimeProjectionCancellable = proLibraryObserver.$projection
            .compactMap { $0 }
            .sink { [weak self] projection in
                Task { @MainActor [weak self] in
                    await self?.handleProRealtimeInvalidation(projection)
                }
            }

        realtimeSessionSupervisor.start(
            createSession: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.createRealtimeSession()
            },
            didCreateSession: { [weak self] session in
                guard let self else { return }
                guard self.accountUser?.id == ownerUserId,
                      self.hasProCloudSyncAccess else { return }
                TuneAVRealtimeSessionStore.shared.update(
                    ownerUserId: ownerUserId,
                    realtimeSessionId: session.realtimeSessionId
                )
                self.proLibraryObserver.observeLibraryProjection(ownerUserId: ownerUserId)
            },
            didExhaustRetries: { [weak self] error in
                guard self?.activeProRealtimeSessionOwnerUserID == ownerUserId else { return }
                self?.activeProRealtimeSessionOwnerUserID = nil
                TuneAVRealtimeSessionStore.shared.clear()
                self?.proLibraryObserver.clear()
                TuneAVMacDiagnostics.capture(
                    error,
                    feature: "tune.mac.sync",
                    operation: "pro_realtime",
                    step: "session"
                )
            }
        )
    }

    private func stopProRealtimeSync() {
        realtimeSessionSupervisor.stop()
        proRealtimeProjectionCancellable?.cancel()
        proRealtimeProjectionCancellable = nil
        pendingCloudSyncTask?.cancel()
        pendingCloudSyncTask = nil
        proRealtimeBootstrapGate.reset()
        activeProRealtimeSessionOwnerUserID = nil
        proRealtimeProjectionCursor.reset()
        cloudLibrarySourceUpdatedAtByResource.removeAll()
        TuneAVRealtimeSessionStore.shared.clear()
        proLibraryObserver.clear()
    }

    private func pauseProRealtimeSync() {
        realtimeSessionSupervisor.pause()
        proRealtimeProjectionCancellable?.cancel()
        proRealtimeProjectionCancellable = nil
        proLibraryObserver.clear()
    }

    private func createRealtimeSession() async throws -> TuneAVRealtimeSession {
        try await makeTuneAPIClient().createTuneAVRealtimeSession()
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
        let previousStatus = playbackStatus
        playbackStatus = status
        isPlaying = status == .playing

        switch status {
        case .playing:
            resumeListeningSessionIfEligible()
        case .paused:
            if previousStatus != .paused {
                flushActiveListeningSession(endedReason: .paused)
            }
        case .failed:
            if previousStatus.failureMessage == nil {
                flushActiveListeningSession(endedReason: .streamError)
            }
        case .idle, .loading:
            break
        }
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
        rememberCurrentTrackForListeningSession()
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
        refreshTunedTrackDiscoveries()
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
        guard !isAccountOperationInProgress else { return }
        isAccountOperationInProgress = true
        defer { isAccountOperationInProgress = false }

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

    private func runSubscriptionOperation(
        source: SubscriptionReconciliationSource,
        _ operation: () async throws -> MacTuneAVPurchaseOutcome
    ) async {
        guard accountUser != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        isSubscriptionOperationInProgress = true
        subscriptionError = nil
        defer {
            isSubscriptionOperationInProgress = false
        }

        do {
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: source.diagnosticsOperation)
            let outcome = try await operation()
            guard outcome.shouldRefreshAccess else { return }
            isWaitingForSubscriptionReconciliation = true
            subscriptionReconciliationSource = source
            await refreshAccessState()
            await retrySubscriptionReconciliationIfNeeded()
        } catch let error as MacTuneAVSubscriptionPurchaseError {
            if error != .purchaseCancelled {
                subscriptionError = error
            }
        } catch {
            TuneAVMacDiagnostics.capture(
                error,
                feature: "tune.subscription",
                operation: source.diagnosticsOperation,
                step: "unknown"
            )
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    private func retrySubscriptionReconciliationIfNeeded() async {
        guard accessMode != .signedInPro else {
            clearSubscriptionReconciliationState()
            return
        }

        let reconciliationAccountUser = accountUser
        for delay in subscriptionReconciliationRetryDelaysNanoseconds {
            guard isWaitingForSubscriptionReconciliation else { return }
            guard accountUser == reconciliationAccountUser else { return }

            await sleepNanoseconds(delay)
            guard isWaitingForSubscriptionReconciliation else { return }
            guard accountUser == reconciliationAccountUser else { return }

            await refreshAccessState()
            if accessMode == .signedInPro {
                clearSubscriptionReconciliationState()
                return
            }
        }
    }

    private func clearSubscriptionReconciliationState() {
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        upgradePrompt = nil
    }

    private func refreshAccessState(tokenOverride: String? = nil) async {
        accountAccessRefreshGeneration += 1
        let refreshGeneration = accountAccessRefreshGeneration
        isRefreshingAccountAccess = true
        defer {
            if refreshGeneration == accountAccessRefreshGeneration {
                isRefreshingAccountAccess = false
            }
        }

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

        if accessMode == .signedInPro, resolvedAccess.accessMode != .signedInPro {
            flushActiveListeningSession(endedReason: .appClosed, schedulesUpload: false)
            stopListeningSessionUploads()
        }

        let previousAccessMode = accessMode
        planTier = resolvedAccess.planTier
        accessMode = resolvedAccess.accessMode
        capabilities = resolvedAccess.capabilities
        limits = TuneAVAccessLimitPolicy.resolvedLimits(resolvedAccess.limits, accessMode: resolvedAccess.accessMode)
        if let accountUser, resolvedAccess.accessMode != .guest {
            persistLastKnownAccountUser(accountUser)
        }
        if resolvedAccess.accessMode == .signedInPro {
            clearSubscriptionReconciliationState()
            if previousAccessMode != .signedInPro,
               let ownerUserID = accountUser?.id {
                proRealtimeBootstrapGate.begin(ownerUserID: ownerUserID)
                scheduleCloudSync(delay: MacCloudSyncTrigger.startupDelay)
            }
            startProRealtimeSyncIfNeeded()
            schedulePendingLibraryOperationsForCurrentUser()
            resumeListeningSessionIfEligible()
            schedulePendingListeningSessionUploadsForCurrentUser()
        } else {
            stopProRealtimeSync()
            stopPendingLibraryOperations()
            stopListeningSessionUploads()
        }
        if resolvedAccess.accessMode == .signedInPro {
            schedulePendingFeedbackUploadsForCurrentUser()
        } else {
            stopPendingFeedbackUploads()
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
        TuneAVAppDataSyncClient(deviceId: "tuneav-mac", platform: "macos") { [weak self] path, method, body, headers in
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
            } catch TuneAVAccessClientError.requestFailed(let statusCode, let retryAfterSeconds) {
                throw TuneAVAppDataClientError.requestFailed(
                    statusCode: statusCode,
                    retryAfterSeconds: retryAfterSeconds
                )
            } catch {
                throw error
            }
        }
    }

    private func enqueueFavoriteLibraryOperation(
        _ operation: CloudLibraryItemOperation,
        record: FavoriteStationRecord
    ) {
        guard hasProCloudSyncAccess, let userID = accountUser?.id else { return }
        let pendingOperation = TuneAVMacPendingLibraryOperation(
            resource: .favorites,
            action: operation == .upsert ? .upsert : .delete,
            userID: userID,
            identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(record.station),
            favoriteRecord: record,
            discoveryRecord: nil,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        rememberPendingLibraryOperation(pendingOperation)
        schedulePendingLibraryOperationsForCurrentUser()
    }

    private func enqueueSavedDiscoveryLibraryOperation(
        _ operation: CloudLibraryItemOperation,
        record: DiscoveredTrackRecord
    ) {
        guard hasProCloudSyncAccess, let userID = accountUser?.id else { return }
        let pendingOperation = TuneAVMacPendingLibraryOperation(
            resource: .savedDiscoveries,
            action: operation == .upsert ? .upsert : .delete,
            userID: userID,
            identityKey: TuneAVLibrarySnapshotMerger.discoveryIdentityKey(record),
            favoriteRecord: nil,
            discoveryRecord: record,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        rememberPendingLibraryOperation(pendingOperation)
        schedulePendingLibraryOperationsForCurrentUser()
    }

    private func rememberPendingLibraryOperation(_ operation: TuneAVMacPendingLibraryOperation) {
        let key = operation.storageKey
        deferredLibrarySyncKeys.remove(key)
        librarySyncTasks[key]?.cancel()
        librarySyncTasks[key] = nil
        librarySyncTokens[key] = nil
        librarySyncRetryCounts[key] = nil
        pendingLibraryOperations = TuneAVMacPendingLibraryOutbox.upserting(operation, into: pendingLibraryOperations)
        storage.savePendingLibraryOperations(pendingLibraryOperations)
    }

    private func schedulePendingLibraryOperationsForCurrentUser() {
        guard hasProCloudSyncAccess,
              accountService.isAvailable,
              let userID = accountUser?.id
        else { return }

        if activePendingLibraryOperationUserID != userID {
            librarySyncTasks.values.forEach { $0.cancel() }
            librarySyncTasks.removeAll()
            librarySyncTokens.removeAll()
            librarySyncRetryCounts.removeAll()
            activePendingLibraryOperationUserID = userID
        }

        for operation in pendingLibraryOperations.values where operation.userID == userID {
            guard !deferredLibrarySyncKeys.contains(operation.storageKey) else { continue }
            guard librarySyncTasks[operation.storageKey] == nil else { continue }
            startPendingLibraryOperation(operation, retryCount: 0)
        }
    }

    private func startPendingLibraryOperation(
        _ operation: TuneAVMacPendingLibraryOperation,
        retryCount: Int,
        minimumDelay: TimeInterval? = nil
    ) {
        let key = operation.storageKey
        let token = UUID()
        let computedDelay = retryCount == 0
            ? 1
            : TuneAVMacSyncRetryPolicy.delay(
                retryCount: retryCount - 1,
                baseDelay: Self.librarySyncRetryBaseDelay,
                maxDelay: Self.librarySyncRetryMaxDelay,
                jitterFraction: Self.librarySyncRetryJitterFraction
            )
        let delay = max(computedDelay, minimumDelay ?? 0)

        librarySyncTokens[key] = token
        librarySyncRetryCounts[key] = retryCount
        librarySyncTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard let self,
                      !Task.isCancelled,
                      self.accountUser?.id == operation.userID,
                      self.pendingLibraryOperations[key]?.id == operation.id,
                      self.librarySyncTokens[key] == token
                else { return }
                let receipt = try await self.syncMutationGate.withPermit {
                    try await self.sendPendingLibraryOperation(operation)
                }
                TuneAVLibraryMutationCoverage.record(
                    receipt,
                    in: &self.cloudLibrarySourceUpdatedAtByResource
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.accountUser?.id == operation.userID,
                      self.pendingLibraryOperations[key]?.id == operation.id,
                      self.librarySyncTokens[key] == token
                else { return }
                if retryCount == 0 {
                    TuneAVMacDiagnostics.capture(
                        error,
                        feature: "tune.mac.sync",
                        operation: operation.resource == .favorites ? "favorite_item" : "saved_discovery_item",
                        step: "upload_retry_scheduled"
                    )
                }
                if case .retry(let retryAfterSeconds) = TuneAVSyncRetryPolicy.disposition(for: error),
                   TuneAVSyncRetryPolicy.canRetry(afterAttempt: retryCount) {
                    self.startPendingLibraryOperation(
                        operation,
                        retryCount: retryCount + 1,
                        minimumDelay: retryAfterSeconds
                    )
                } else {
                    self.deferPendingLibraryOperation(key: key, token: token)
                }
                return
            }

            guard let self,
                  self.pendingLibraryOperations[key]?.id == operation.id,
                  self.librarySyncTokens[key] == token
            else { return }
            self.pendingLibraryOperations[key] = nil
            self.librarySyncTasks[key] = nil
            self.librarySyncTokens[key] = nil
            self.librarySyncRetryCounts[key] = nil
            self.storage.savePendingLibraryOperations(self.pendingLibraryOperations)
            self.lastCloudSyncAt = .now
        }
    }

    private func sendPendingLibraryOperation(
        _ operation: TuneAVMacPendingLibraryOperation
    ) async throws -> TuneAVLibraryMutationReceipt {
        let client = makeAppDataSyncClient()
        switch (operation.resource, operation.action) {
        case (.favorites, .upsert):
            guard let record = operation.favoriteRecord else {
                throw TuneAVMacPendingLibraryOperationError.invalidPayload
            }
            return try await client.upsertFavorite(record, idempotencyKey: operation.id.uuidString.lowercased())
        case (.favorites, .delete):
            guard let record = operation.favoriteRecord else {
                throw TuneAVMacPendingLibraryOperationError.invalidPayload
            }
            return try await client.deleteFavorite(record, idempotencyKey: operation.id.uuidString.lowercased())
        case (.savedDiscoveries, .upsert):
            guard let record = operation.discoveryRecord else {
                throw TuneAVMacPendingLibraryOperationError.invalidPayload
            }
            return try await client.upsertSavedDiscovery(record, idempotencyKey: operation.id.uuidString.lowercased())
        case (.savedDiscoveries, .delete):
            guard let record = operation.discoveryRecord else {
                throw TuneAVMacPendingLibraryOperationError.invalidPayload
            }
            return try await client.deleteSavedDiscovery(record, idempotencyKey: operation.id.uuidString.lowercased())
        }
    }

    private func stopPendingLibraryOperations() {
        librarySyncTasks.values.forEach { $0.cancel() }
        librarySyncTasks.removeAll()
        librarySyncTokens.removeAll()
        librarySyncRetryCounts.removeAll()
        deferredLibrarySyncKeys.removeAll()
        activePendingLibraryOperationUserID = nil
    }

    private func deferPendingLibraryOperation(key: String, token: UUID) {
        guard librarySyncTokens[key] == token else { return }
        librarySyncTasks[key] = nil
        librarySyncTokens[key] = nil
        librarySyncRetryCounts[key] = nil
        deferredLibrarySyncKeys.insert(key)
    }

    private func resumeListeningSessionIfEligible() {
        guard listeningAnalyticsUploadEnabled,
              accessMode == .signedInPro,
              let userID = accountUser?.id,
              let currentStation,
              isPlaying
        else { return }

        if let activeListeningSession, activeListeningSession.userID != userID {
            flushActiveListeningSession(endedReason: .appClosed, schedulesUpload: false)
        }

        TuneAVMacListeningSessionCoordinator.resumeIfNeeded(
            session: &activeListeningSession,
            station: currentStation,
            source: playbackQueueSource.analyticsSource,
            userID: userID,
            now: nowProvider()
        )
    }

    private func rememberCurrentTrackForListeningSession() {
        guard let title = TuneAVDisplayMetadata.plausibleTitle(currentTrackTitle, stationName: currentStation?.name) else {
            return
        }
        let artist = TuneAVDisplayMetadata.plausibleArtist(currentTrackArtist, stationName: currentStation?.name)
        TuneAVMacListeningSessionCoordinator.rememberTrack(
            session: &activeListeningSession,
            title: title,
            artist: artist
        )
    }

    private func flushActiveListeningSession(endedReason: TuneAVListeningEndedReason, schedulesUpload: Bool = true) {
        guard listeningAnalyticsUploadEnabled,
              let session = TuneAVMacListeningSessionCoordinator.flush(session: &activeListeningSession),
              let draft = TuneAVMacListeningSessionDraft(
                session: session,
                endedAt: nowProvider(),
                endedReason: endedReason,
                minimumDuration: Self.listeningSessionMinimumDuration
              )
        else { return }

        pendingListeningSessions = TuneAVMacListeningSessionOutbox.appending(
            draft,
            to: pendingListeningSessions,
            maxCount: Self.maxPendingListeningSessions,
            maxAge: Self.pendingListeningSessionMaxAge,
            now: nowProvider()
        )
        listeningSessionUploadsDeferred = false
        storage.savePendingListeningSessions(pendingListeningSessions)

        guard schedulesUpload else { return }
        if uploadablePendingListeningSessions().count >= Self.listeningSessionBatchSize {
            flushListeningSessionUploads()
        } else {
            schedulePendingListeningSessionUploadsForCurrentUser()
        }
    }

    private func uploadablePendingListeningSessions() -> [TuneAVMacListeningSessionDraft] {
        guard let userID = accountUser?.id else { return [] }
        return TuneAVMacListeningSessionOutbox.sessions(
            in: pendingListeningSessions,
            forUserID: userID,
            limit: Self.listeningSessionBatchSize
        )
    }

    private func schedulePendingListeningSessionUploadsForCurrentUser() {
        prunePendingListeningSessions()
        let client = makeTuneAPIClient()
        guard TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: listeningAnalyticsUploadEnabled,
            accessMode: accessMode,
            userID: accountUser?.id,
            accountServiceAvailable: accountService.isAvailable,
            apiConfigured: client.isConfigured
        ), !uploadablePendingListeningSessions().isEmpty,
           !listeningSessionUploadsDeferred,
           listeningSessionUploadTask == nil,
           listeningSessionFlushTask == nil
        else { return }

        let computedDelay = TuneAVMacSyncRetryPolicy.delay(
            retryCount: listeningSessionUploadRetryCount,
            baseDelay: Self.listeningSessionRetryBaseDelay,
            maxDelay: Self.listeningSessionRetryMaxDelay,
            jitterFraction: Self.listeningSessionRetryJitterFraction
        )
        let delay = max(computedDelay, listeningSessionRetryAfterDelay ?? 0)
        listeningSessionRetryAfterDelay = nil
        listeningSessionUploadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.listeningSessionUploadTask = nil
            self.flushListeningSessionUploads()
        }
    }

    private func flushListeningSessionUploads() {
        listeningSessionUploadTask?.cancel()
        listeningSessionUploadTask = nil
        guard listeningSessionFlushTask == nil else { return }

        prunePendingListeningSessions()

        let client = makeTuneAPIClient()
        guard TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: listeningAnalyticsUploadEnabled,
            accessMode: accessMode,
            userID: accountUser?.id,
            accountServiceAvailable: accountService.isAvailable,
            apiConfigured: client.isConfigured
        ) else { return }

        let sessions = uploadablePendingListeningSessions()
        guard !sessions.isEmpty else { return }
        let userID = accountUser?.id
        let sessionIDs = Set(sessions.map(\.id))
        let flushToken = UUID()
        listeningSessionFlushToken = flushToken

        listeningSessionFlushTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let token = try await self.accountService.getToken()
                guard let token, !token.isEmpty,
                      self.accountUser?.id == userID,
                      self.listeningSessionFlushToken == flushToken
                else {
                    throw TuneAVAccessClientError.missingToken
                }
                try await self.syncMutationGate.withPermit {
                    try await self.sendListeningSessions(sessions, tokenOverride: token)
                }
                guard self.accountUser?.id == userID,
                      self.listeningSessionFlushToken == flushToken else { return }
                self.pendingListeningSessions.removeAll { sessionIDs.contains($0.id) }
                self.storage.savePendingListeningSessions(self.pendingListeningSessions)
                self.listeningSessionUploadRetryCount = 0
                self.listeningSessionUploadsDeferred = false
                self.listeningSessionRetryAfterDelay = nil
                self.listeningSessionFlushTask = nil
                self.listeningSessionFlushToken = nil
                if !self.uploadablePendingListeningSessions().isEmpty {
                    self.flushListeningSessionUploads()
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.listeningSessionFlushToken == flushToken else { return }
                self.listeningSessionFlushTask = nil
                self.listeningSessionFlushToken = nil
                let disposition = TuneAVSyncRetryPolicy.disposition(for: error)
                if disposition == .stop {
                    self.pendingListeningSessions.removeAll { sessionIDs.contains($0.id) }
                    self.storage.savePendingListeningSessions(self.pendingListeningSessions)
                    self.listeningSessionUploadRetryCount = 0
                    self.listeningSessionUploadsDeferred = false
                    self.listeningSessionRetryAfterDelay = nil
                    TuneAVMacDiagnostics.capture(
                        error,
                        feature: "tune.mac.analytics",
                        operation: "listening_sessions",
                        step: "upload_permanently_rejected"
                    )
                    if !self.uploadablePendingListeningSessions().isEmpty {
                        self.flushListeningSessionUploads()
                    }
                    return
                }
                let shouldRetry = disposition != .stop
                    && TuneAVSyncRetryPolicy.canRetry(afterAttempt: self.listeningSessionUploadRetryCount)
                if case .retry(let retryAfterSeconds) = disposition {
                    self.listeningSessionRetryAfterDelay = retryAfterSeconds
                }
                if shouldRetry {
                    self.listeningSessionUploadRetryCount += 1
                } else {
                    self.listeningSessionUploadsDeferred = true
                }
                if self.listeningSessionUploadRetryCount == 1 {
                    TuneAVMacDiagnostics.capture(
                        error,
                        feature: "tune.mac.analytics",
                        operation: "listening_sessions",
                        step: "upload_retry_scheduled"
                    )
                }
                if shouldRetry {
                    self.schedulePendingListeningSessionUploadsForCurrentUser()
                }
            }
        }
    }

    private func sendListeningSessions(
        _ sessions: [TuneAVMacListeningSessionDraft],
        tokenOverride: String
    ) async throws {
        let payload = TuneAVMacListeningSessionsRequest(deviceId: "tuneav-mac", sessions: sessions.map(\.apiInput))
        _ = try await makeTuneAPIClient(tokenOverride: tokenOverride).requestData(
            path: "/v1/tune/analytics/listening-sessions",
            method: "POST",
            body: try JSONEncoder().encode(payload),
            headers: ["Idempotency-Key": "tuneav-mac-listening-\(sessions.map(\.id).joined(separator: ":"))"]
        )
    }

    private func stopListeningSessionUploads() {
        listeningSessionUploadTask?.cancel()
        listeningSessionUploadTask = nil
        listeningSessionFlushTask?.cancel()
        listeningSessionFlushTask = nil
        listeningSessionFlushToken = nil
        listeningSessionUploadRetryCount = 0
        listeningSessionUploadsDeferred = false
        listeningSessionRetryAfterDelay = nil
    }

    private func prunePendingListeningSessions() {
        let bounded = TuneAVMacListeningSessionOutbox.bounded(
            pendingListeningSessions,
            maxCount: Self.maxPendingListeningSessions,
            maxAge: Self.pendingListeningSessionMaxAge,
            now: nowProvider()
        )
        guard bounded != pendingListeningSessions else { return }
        pendingListeningSessions = bounded
        storage.savePendingListeningSessions(pendingListeningSessions)
    }

    private func enqueueStationFeedbackUpload(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard TuneAVFeedbackBackendPolicy.canUpload(accessMode: accessMode),
              let userID = accountUser?.id else { return }
        let upload = TuneAVMacPendingFeedbackUpload(
            kind: .station,
            userID: userID,
            identityKey: stationID,
            feedback: feedback,
            stationID: stationID,
            title: nil,
            artist: nil,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        rememberPendingFeedbackUpload(upload)
        schedulePendingFeedbackUploadsForCurrentUser()
    }

    private func enqueueTrackFeedbackUpload(
        _ feedback: TuneAVStationFeedback?,
        title: String,
        artist: String?,
        stationID: String?
    ) {
        guard TuneAVFeedbackBackendPolicy.canUpload(accessMode: accessMode),
              let userID = accountUser?.id else { return }
        let upload = TuneAVMacPendingFeedbackUpload(
            kind: .track,
            userID: userID,
            identityKey: Self.trackFeedbackKey(title: title, artist: artist),
            feedback: feedback,
            stationID: stationID,
            title: title,
            artist: artist,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        rememberPendingFeedbackUpload(upload)
        schedulePendingFeedbackUploadsForCurrentUser()
    }

    private func rememberPendingFeedbackUpload(_ upload: TuneAVMacPendingFeedbackUpload) {
        let key = upload.storageKey
        deferredFeedbackSyncKeys.remove(key)
        feedbackSyncTasks[key]?.cancel()
        feedbackSyncTasks[key] = nil
        feedbackSyncTokens[key] = nil
        feedbackSyncRetryCounts[key] = nil
        pendingFeedbackUploads = TuneAVMacPendingFeedbackOutbox.upserting(upload, into: pendingFeedbackUploads)
        storage.savePendingFeedbackUploads(pendingFeedbackUploads)
    }

    private func schedulePendingFeedbackUploadsForCurrentUser() {
        guard TuneAVFeedbackBackendPolicy.canUpload(accessMode: accessMode),
              accountService.isAvailable,
              let userID = accountUser?.id
        else { return }

        if activePendingFeedbackUploadUserID != userID {
            feedbackSyncTasks.values.forEach { $0.cancel() }
            feedbackSyncTasks.removeAll()
            feedbackSyncTokens.removeAll()
            feedbackSyncRetryCounts.removeAll()
            activePendingFeedbackUploadUserID = userID
        }

        for upload in pendingFeedbackUploads.values where upload.userID == userID {
            guard !deferredFeedbackSyncKeys.contains(upload.storageKey) else { continue }
            guard feedbackSyncTasks[upload.storageKey] == nil else { continue }
            startPendingFeedbackUpload(upload, retryCount: 0)
        }
    }

    private func startPendingFeedbackUpload(
        _ upload: TuneAVMacPendingFeedbackUpload,
        retryCount: Int,
        minimumDelay: TimeInterval? = nil
    ) {
        let key = upload.storageKey
        let token = UUID()
        let computedDelay = retryCount == 0
            ? 1
            : TuneAVMacSyncRetryPolicy.delay(
                retryCount: retryCount - 1,
                baseDelay: Self.feedbackSyncRetryBaseDelay,
                maxDelay: Self.feedbackSyncRetryMaxDelay,
                jitterFraction: Self.feedbackSyncRetryJitterFraction
            )
        let delay = max(computedDelay, minimumDelay ?? 0)

        feedbackSyncTokens[key] = token
        feedbackSyncRetryCounts[key] = retryCount
        feedbackSyncTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard let self,
                      !Task.isCancelled,
                      self.accountUser?.id == upload.userID,
                      self.pendingFeedbackUploads[key]?.id == upload.id,
                      self.feedbackSyncTokens[key] == token
                else { return }
                try await self.syncMutationGate.withPermit {
                    try await self.sendPendingFeedbackUpload(upload)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.accountUser?.id == upload.userID,
                      self.pendingFeedbackUploads[key]?.id == upload.id,
                      self.feedbackSyncTokens[key] == token
                else { return }
                if retryCount == 0 {
                    TuneAVMacDiagnostics.capture(
                        error,
                        feature: "tune.mac.sync",
                        operation: upload.kind == .station ? "station_feedback" : "track_feedback",
                        step: "upload_retry_scheduled"
                    )
                }
                if case .retry(let retryAfterSeconds) = TuneAVSyncRetryPolicy.disposition(for: error),
                   TuneAVSyncRetryPolicy.canRetry(afterAttempt: retryCount) {
                    self.startPendingFeedbackUpload(
                        upload,
                        retryCount: retryCount + 1,
                        minimumDelay: retryAfterSeconds
                    )
                } else {
                    self.deferPendingFeedbackUpload(key: key, token: token)
                }
                return
            }

            guard let self,
                  self.pendingFeedbackUploads[key]?.id == upload.id,
                  self.feedbackSyncTokens[key] == token
            else { return }
            self.pendingFeedbackUploads[key] = nil
            self.feedbackSyncTasks[key] = nil
            self.feedbackSyncTokens[key] = nil
            self.feedbackSyncRetryCounts[key] = nil
            self.storage.savePendingFeedbackUploads(self.pendingFeedbackUploads)
        }
    }

    private func sendPendingFeedbackUpload(_ upload: TuneAVMacPendingFeedbackUpload) async throws {
        switch upload.kind {
        case .station:
            try await sendFeedbackRequest(
                path: "/v1/tune/feedback/stations/\(Self.encodedPathSegment(upload.identityKey))",
                payload: TuneAVMacFeedbackRequest(deviceId: "tuneav-mac", feedback: upload.feedback?.backendValue)
            )
        case .track:
            guard let title = upload.title else { return }
            try await sendFeedbackRequest(
                path: "/v1/tune/feedback/tracks/\(Self.encodedPathSegment(upload.identityKey))",
                payload: TuneAVMacTrackFeedbackRequest(
                    deviceId: "tuneav-mac",
                    title: title,
                    artist: upload.artist,
                    stationId: upload.stationID,
                    feedback: upload.feedback?.backendValue
                )
            )
        }
    }

    private func stopPendingFeedbackUploads() {
        feedbackSyncTasks.values.forEach { $0.cancel() }
        feedbackSyncTasks.removeAll()
        feedbackSyncTokens.removeAll()
        feedbackSyncRetryCounts.removeAll()
        deferredFeedbackSyncKeys.removeAll()
        activePendingFeedbackUploadUserID = nil
    }

    private func deferPendingFeedbackUpload(key: String, token: UUID) {
        guard feedbackSyncTokens[key] == token else { return }
        feedbackSyncTasks[key] = nil
        feedbackSyncTokens[key] = nil
        feedbackSyncRetryCounts[key] = nil
        deferredFeedbackSyncKeys.insert(key)
    }

    private func sendFeedbackRequest<Payload: Encodable>(path: String, payload: Payload) async throws {
        _ = try await makeTuneAPIClient().requestData(
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

    private func refreshTunedTrackDiscoveries() {
        let localDiscoveriesByFeedbackKey = Dictionary(
            discoveredTracks.map { (Self.trackFeedbackKey(title: $0.title, artist: $0.artist), $0) },
            uniquingKeysWith: { first, second in
                first.playedAt >= second.playedAt ? first : second
            }
        )

        tunedTrackDiscoveries = trackFeedbackRecords
            .compactMap { key, record -> MacDiscoveredTrack? in
                if let localDiscovery = localDiscoveriesByFeedbackKey[key] {
                    return localDiscovery
                }
                guard let title = record.title else { return nil }
                let updatedAt = TuneAVDateCoding.date(from: record.updatedAt)
                let stationID = record.stationID ?? "tuneav-feedback"
                return MacDiscoveredTrack(
                    record: DiscoveredTrackRecord(
                        discoveryID: MacDiscoveredTrack.makeID(
                            title: title,
                            artist: record.artist,
                            stationID: stationID
                        ),
                        trackKey: key,
                        title: title,
                        artist: record.artist,
                        stationID: stationID,
                        stationName: "Tune AV",
                        artworkURL: nil,
                        stationArtworkURL: nil,
                        playedAt: TuneAVDateCoding.string(from: updatedAt),
                        updatedAt: record.updatedAt
                    )
                )
            }
            .sorted { first, second in
                let firstRank = Self.feedbackSortRank(trackFeedback[Self.trackFeedbackKey(title: first.title, artist: first.artist)])
                let secondRank = Self.feedbackSortRank(trackFeedback[Self.trackFeedbackKey(title: second.title, artist: second.artist)])
                if firstRank == secondRank {
                    return first.playedAt > second.playedAt
                }
                return firstRank < secondRank
            }
    }

    private nonisolated static func feedbackSortRank(_ feedback: TuneAVStationFeedback?) -> Int {
        switch feedback {
        case .liked:
            return 0
        case .notForMe:
            return 1
        case .disliked:
            return 2
        case nil:
            return 3
        }
    }

    private nonisolated static func encodedPathSegment(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
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

    private func makeTuneAPIClient(tokenOverride: String? = nil) -> TuneAVAccessClient {
        makeAccountAPIClient(
            baseURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_API_BASE_URL")
                ?? TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL"),
            tokenOverride: tokenOverride
        )
    }

    private func makePromotionCodeRedeemer() -> TuneAVPromotionCodeRedeeming {
        if let promotionCodeRedeemer {
            return promotionCodeRedeemer
        }

        return TuneAVPromoCodeClient(
            baseURL: TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL"),
            urlSession: TuneAVURLSessions.account,
            tokenProvider: { [self] in
                try await accountService.getToken()
            }
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
                identityKey: TuneAVLibrarySnapshotMerger.discoveryIdentityKey(discovery),
                payload: discovery,
                deletedAt: discovery.deletedAt.map(TuneAVDateCoding.date(from:)) ?? .now
            )
        }

        favoriteRecords = snapshot.favorites
            .filter { $0.deletedAt == nil }

        favoriteStations = favoriteRecords
            .map { Station(record: $0.station) }

        let savedDiscoveriesByIdentity = Dictionary(
            snapshot.savedDiscoveries.filter { $0.deletedAt == nil }.map { (TuneAVLibrarySnapshotMerger.discoveryIdentityKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let deletedSavedDiscoveryIdentityKeys = Set(
            snapshot.savedDiscoveries.compactMap { $0.deletedAt == nil ? nil : TuneAVLibrarySnapshotMerger.discoveryIdentityKey($0) }
        )
        var nextDiscoveries = discoveredTracks.map { discovery in
            var nextDiscovery = discovery
            let discoveryIdentityKey = savedDiscoveryIdentityKey(for: discovery)
            if let savedRecord = savedDiscoveriesByIdentity[discoveryIdentityKey] {
                nextDiscovery = MacDiscoveredTrack(record: savedRecord) ?? discovery
            } else if deletedSavedDiscoveryIdentityKeys.contains(discoveryIdentityKey) {
                nextDiscovery.markedInterestedAt = nil
            }
            return nextDiscovery
        }
        let existingDiscoveryIdentityKeys = Set(nextDiscoveries.map(savedDiscoveryIdentityKey(for:)))
        nextDiscoveries.append(
            contentsOf: savedDiscoveriesByIdentity.values
                .filter { !existingDiscoveryIdentityKeys.contains(TuneAVLibrarySnapshotMerger.discoveryIdentityKey($0)) }
                .compactMap(MacDiscoveredTrack.init(record:))
        )
        discoveredTracks = sortedDiscoveries(nextDiscoveries)
        refreshTunedTrackDiscoveries()

        storage.saveFavoriteRecords(favoriteRecords)
        storage.saveDiscoveries(discoveredTracks)
        storage.saveTombstones(libraryTombstones)
        markCloudLibraryApplied()
    }

    private func handleProRealtimeInvalidation(_ projection: TuneAVProLibraryProjection) async {
        if proRealtimeBootstrapGate.shouldAwaitBootstrap(for: projection.ownerUserId),
           let pendingCloudSyncTask {
            await pendingCloudSyncTask.value
        }

        guard accessMode == .signedInPro,
              accountUser?.id == projection.ownerUserId else { return }

        while cloudSyncExecutionGate.isRunning {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard accessMode == .signedInPro,
                  accountUser?.id == projection.ownerUserId else { return }
        }

        if TuneAVProRealtimeInitialProjectionPolicy.shouldEstablishLegacyBaseline(
            projection: projection,
            hasProjectionBaseline: proRealtimeProjectionCursor.hasBaseline(for: projection.ownerUserId),
            didCompleteLibraryBootstrap: proRealtimeBootstrapGate.hasCompletedSuccessfulBootstrap(
                for: projection.ownerUserId
            )
        ) {
            proRealtimeProjectionCursor.establishBaseline(projection)
            proRealtimeBootstrapGate.finishInitialProjection(ownerUserID: projection.ownerUserId)
            return
        }

        let refreshPlan = proRealtimeProjectionCursor.consume(
            projection,
            coverage: TuneAVProRealtimeCoverage(
                librarySourceUpdatedAtByResource: cloudLibrarySourceUpdatedAtByResource
            )
        )
        proRealtimeBootstrapGate.finishInitialProjection(ownerUserID: projection.ownerUserId)
        let executionPlan = MacProRealtimeRefreshExecutionPlan(refreshPlan)
        if let resource = executionPlan.libraryResource {
            await synchronizeLibraryResourceNow(resource)
        } else if executionPlan.requiresFullLibraryRefresh {
            await synchronizeLibraryNow()
        }
    }

    @discardableResult
    private func rememberFavoriteDeletion(for station: Station) -> FavoriteStationRecord {
        let deletedAt = Date.now
        let record = FavoriteStationRecord(
            station: station.appDataRecord,
            deletedAt: TuneAVDateCoding.string(from: deletedAt)
        )
        rememberTombstone(
            resource: "favorites",
            identityKey: stationIdentityKey(for: station),
            payload: record,
            deletedAt: deletedAt
        )
        return record
    }

    @discardableResult
    private func rememberSavedDiscoveryDeletion(for discovery: MacDiscoveredTrack) -> DiscoveredTrackRecord {
        let deletedAt = Date.now
        let record = DiscoveredTrackRecord(
            discoveryID: discovery.discoveryID,
            trackKey: discovery.trackKey,
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
        )
        rememberTombstone(
            resource: "savedDiscoveries",
            identityKey: savedDiscoveryIdentityKey(for: discovery),
            payload: record,
            deletedAt: deletedAt
        )
        return record
    }

    private func savedDiscoveryIdentityKey(for discovery: MacDiscoveredTrack) -> String {
        TuneAVLibrarySnapshotMerger.discoveryIdentityKey(discovery.record)
    }

    private static func savedDiscoveryIdentityKey(title: String, artist: String?) -> String {
        "track:\(TuneAVDiscoveredTrackSupport.trackKey(title: title, artist: artist, locale: L10n.locale))"
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
            proRealtimeBootstrapGate.reset()
        case .none:
            break
        }
    }

    @discardableResult
    private func restoreAccountSessionForAccessRefresh() async -> Bool {
        let previousAccountUserID = accountUser?.id

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
            if MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterActiveRestore(
                previousUserID: previousAccountUserID,
                restoredUserID: user.id
            ) {
                resolveLocalAccessState()
            }
            return true
        case .temporarilyUnavailable:
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.mac.account", operation: "restore_temporarily_unavailable")
            isAccountSessionTemporarilyUnavailable = true
            if MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterUnavailableRestore(
                hasCurrentUser: accountUser != nil
            ) {
                resolveLocalAccessState()
            }
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
        guard pendingCloudSyncTask == nil else { return }
        pendingCloudSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.synchronizeLibraryNow()
            } catch {
                // Cancellation is expected when the account or access changes.
            }
            self?.pendingCloudSyncTask = nil
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

struct TuneAVMacActiveListeningSession {
    let station: Station
    let startedAt: Date
    let source: String
    let userID: String
    var trackKeys: Set<String>
}

enum TuneAVMacListeningSessionCoordinator {
    static func begin(
        session: inout TuneAVMacActiveListeningSession?,
        station: Station,
        source: String,
        userID: String,
        now: Date = .now
    ) -> TuneAVMacActiveListeningSession? {
        if session?.station.id == station.id, session?.userID == userID {
            return nil
        }

        let endedSession = session
        session = TuneAVMacActiveListeningSession(
            station: station,
            startedAt: now,
            source: source,
            userID: userID,
            trackKeys: []
        )
        return endedSession
    }

    static func resumeIfNeeded(
        session: inout TuneAVMacActiveListeningSession?,
        station: Station,
        source: String,
        userID: String,
        now: Date = .now
    ) {
        guard session == nil else { return }
        session = TuneAVMacActiveListeningSession(
            station: station,
            startedAt: now,
            source: source,
            userID: userID,
            trackKeys: []
        )
    }

    static func rememberTrack(
        session: inout TuneAVMacActiveListeningSession?,
        title: String,
        artist: String?
    ) {
        guard var currentSession = session else { return }
        let key = [artist ?? "", title]
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
            }
            .joined(separator: "|")
        currentSession.trackKeys.insert(key)
        session = currentSession
    }

    static func flush(
        session: inout TuneAVMacActiveListeningSession?
    ) -> TuneAVMacActiveListeningSession? {
        defer { session = nil }
        return session
    }
}

struct TuneAVMacListeningSessionDraft: Codable, Equatable {
    let id: String
    let stationID: String
    let stationName: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let source: String
    let endedReason: TuneAVListeningEndedReason
    let trackDetectedCount: Int
    let userID: String

    init?(
        id: String = UUID().uuidString,
        session: TuneAVMacActiveListeningSession,
        endedAt: Date,
        endedReason: TuneAVListeningEndedReason,
        minimumDuration: TimeInterval = 10
    ) {
        let durationSeconds = max(0, Int(endedAt.timeIntervalSince(session.startedAt).rounded()))
        guard TimeInterval(durationSeconds) >= minimumDuration else { return nil }
        self.id = id
        self.stationID = session.station.id
        self.stationName = session.station.name
        self.startedAt = session.startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.source = session.source
        self.endedReason = endedReason
        self.trackDetectedCount = session.trackKeys.count
        self.userID = session.userID
    }

    init(
        id: String = UUID().uuidString,
        stationID: String,
        stationName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        source: String,
        endedReason: TuneAVListeningEndedReason,
        trackDetectedCount: Int,
        userID: String
    ) {
        self.id = id
        self.stationID = stationID
        self.stationName = stationName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.source = source
        self.endedReason = endedReason
        self.trackDetectedCount = trackDetectedCount
        self.userID = userID
    }

    var apiInput: TuneAVMacListeningSessionInput {
        TuneAVMacListeningSessionInput(
            id: id,
            stationId: stationID,
            stationName: stationName,
            startedAt: TuneAVDateCoding.string(from: startedAt),
            endedAt: TuneAVDateCoding.string(from: endedAt),
            durationSeconds: durationSeconds,
            source: source,
            endedReason: endedReason,
            trackDetectedCount: trackDetectedCount
        )
    }
}

enum TuneAVMacListeningSessionOutbox {
    static func appending(
        _ session: TuneAVMacListeningSessionDraft,
        to sessions: [TuneAVMacListeningSessionDraft],
        maxCount: Int,
        maxAge: TimeInterval,
        now: Date
    ) -> [TuneAVMacListeningSessionDraft] {
        bounded(sessions + [session], maxCount: maxCount, maxAge: maxAge, now: now)
    }

    static func bounded(
        _ sessions: [TuneAVMacListeningSessionDraft],
        maxCount: Int,
        maxAge: TimeInterval,
        now: Date
    ) -> [TuneAVMacListeningSessionDraft] {
        guard maxCount > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-max(0, maxAge))
        var newestByID: [String: TuneAVMacListeningSessionDraft] = [:]
        for session in sessions where session.endedAt >= cutoff {
            if let existing = newestByID[session.id], existing.endedAt >= session.endedAt {
                continue
            }
            newestByID[session.id] = session
        }
        let boundedByUser = Dictionary(grouping: newestByID.values, by: \.userID)
            .values
            .flatMap { userSessions in
                userSessions.sorted(by: areListeningSessionsOrdered).suffix(maxCount)
            }
        return boundedByUser.sorted(by: areListeningSessionsOrdered)
    }

    static func sessions(
        in sessions: [TuneAVMacListeningSessionDraft],
        forUserID userID: String,
        limit: Int
    ) -> [TuneAVMacListeningSessionDraft] {
        guard limit > 0 else { return [] }
        return Array(
            sessions
                .filter { $0.userID == userID }
                .sorted(by: areListeningSessionsOrdered)
                .prefix(limit)
        )
    }

    private static func areListeningSessionsOrdered(
        _ lhs: TuneAVMacListeningSessionDraft,
        _ rhs: TuneAVMacListeningSessionDraft
    ) -> Bool {
        if lhs.endedAt == rhs.endedAt {
            return lhs.id < rhs.id
        }
        return lhs.endedAt < rhs.endedAt
    }
}

enum TuneAVMacListeningAnalyticsEligibility {
    static func canUpload(
        isEnabled: Bool,
        accessMode: AccessMode,
        userID: String?,
        accountServiceAvailable: Bool,
        apiConfigured: Bool
    ) -> Bool {
        isEnabled && accessMode == .signedInPro && userID != nil && accountServiceAvailable && apiConfigured
    }
}

struct TuneAVMacListeningSessionsRequest: Encodable {
    let deviceId: String
    let sessions: [TuneAVMacListeningSessionInput]
}

struct TuneAVMacListeningSessionInput: Encodable {
    let id: String
    let stationId: String
    let stationName: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
    let source: String
    let endedReason: TuneAVListeningEndedReason
    let trackDetectedCount: Int
}

struct TuneAVMacLibraryStorage {
    static let favoritesKey = "tuneav.mac.library.favorites"
    static let favoriteRecordsKey = "tuneav.mac.library.favoriteRecords.v1"
    static let recentsKey = "tuneav.mac.library.recents"
    static let discoveriesKey = "tuneav.mac.library.discoveries"
    static let stationFeedbackKey = "tuneav.mac.library.stationFeedback"
    static let trackFeedbackKey = "tuneav.mac.library.trackFeedback.v1"
    static let pendingLibraryOperationsKey = "tuneav.mac.library.pendingOperations.v1"
    static let pendingFeedbackUploadsKey = "tuneav.mac.feedback.pendingUploads.v1"
    static let pendingListeningSessionsKey = "tuneav.mac.analytics.pendingListeningSessions.v1"
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
            let canonicalRecords = TuneAVLocalFeedbackStore.canonicalizedTrackRecords(records)
            if canonicalRecords != records {
                saveTrackFeedbackRecords(canonicalRecords)
            }
            return canonicalRecords
        }
        let migrated = (try? decoder.decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
        let records = TuneAVLocalFeedbackStore.canonicalizedTrackRecords(
            TuneAVLocalFeedbackStore.records(fromLegacy: migrated, updatedAt: .now)
        )
        if !records.isEmpty {
            saveTrackFeedbackRecords(records)
        }
        return records
    }

    func saveTrackFeedbackRecords(_ feedback: [String: TuneAVLocalFeedbackRecord]) {
        guard !feedback.isEmpty else {
            defaults.removeObject(forKey: Self.trackFeedbackKey)
            return
        }
        guard let data = try? encoder.encode(feedback) else { return }
        defaults.set(data, forKey: Self.trackFeedbackKey)
    }

    func loadPendingLibraryOperations() -> [String: TuneAVMacPendingLibraryOperation] {
        guard let data = defaults.data(forKey: Self.pendingLibraryOperationsKey) else { return [:] }
        return (try? decoder.decode([String: TuneAVMacPendingLibraryOperation].self, from: data)) ?? [:]
    }

    func savePendingLibraryOperations(_ operations: [String: TuneAVMacPendingLibraryOperation]) {
        guard !operations.isEmpty else {
            defaults.removeObject(forKey: Self.pendingLibraryOperationsKey)
            return
        }
        guard let data = try? encoder.encode(operations) else { return }
        defaults.set(data, forKey: Self.pendingLibraryOperationsKey)
    }

    func loadPendingFeedbackUploads() -> [String: TuneAVMacPendingFeedbackUpload] {
        guard let data = defaults.data(forKey: Self.pendingFeedbackUploadsKey) else { return [:] }
        return (try? decoder.decode([String: TuneAVMacPendingFeedbackUpload].self, from: data)) ?? [:]
    }

    func savePendingFeedbackUploads(_ uploads: [String: TuneAVMacPendingFeedbackUpload]) {
        guard !uploads.isEmpty else {
            defaults.removeObject(forKey: Self.pendingFeedbackUploadsKey)
            return
        }
        guard let data = try? encoder.encode(uploads) else { return }
        defaults.set(data, forKey: Self.pendingFeedbackUploadsKey)
    }

    func loadPendingListeningSessions() -> [TuneAVMacListeningSessionDraft] {
        guard let data = defaults.data(forKey: Self.pendingListeningSessionsKey) else { return [] }
        return (try? decoder.decode([TuneAVMacListeningSessionDraft].self, from: data)) ?? []
    }

    func savePendingListeningSessions(_ sessions: [TuneAVMacListeningSessionDraft]) {
        guard !sessions.isEmpty else {
            defaults.removeObject(forKey: Self.pendingListeningSessionsKey)
            return
        }
        guard let data = try? encoder.encode(sessions) else { return }
        defaults.set(data, forKey: Self.pendingListeningSessionsKey)
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

struct TuneAVMacPendingLibraryOperation: Codable, Equatable {
    enum Resource: String, Codable {
        case favorites
        case savedDiscoveries
    }

    enum Action: String, Codable {
        case upsert
        case delete
    }

    let id: UUID
    let resource: Resource
    let action: Action
    let userID: String
    let identityKey: String
    let favoriteRecord: FavoriteStationRecord?
    let discoveryRecord: DiscoveredTrackRecord?
    let updatedAt: String

    init(
        id: UUID = UUID(),
        resource: Resource,
        action: Action,
        userID: String,
        identityKey: String,
        favoriteRecord: FavoriteStationRecord?,
        discoveryRecord: DiscoveredTrackRecord?,
        updatedAt: String
    ) {
        self.id = id
        self.resource = resource
        self.action = action
        self.userID = userID
        self.identityKey = identityKey
        self.favoriteRecord = favoriteRecord
        self.discoveryRecord = discoveryRecord
        self.updatedAt = updatedAt
    }

    var storageKey: String {
        "\(userID):\(resource.rawValue):\(identityKey)"
    }
}

enum TuneAVMacPendingLibraryOutbox {
    static func upserting(
        _ operation: TuneAVMacPendingLibraryOperation,
        into operations: [String: TuneAVMacPendingLibraryOperation]
    ) -> [String: TuneAVMacPendingLibraryOperation] {
        var nextOperations = operations
        nextOperations[operation.storageKey] = operation
        return nextOperations
    }
}

enum TuneAVMacPendingLibraryOperationError: Error {
    case invalidPayload
}

struct TuneAVMacPendingFeedbackUpload: Codable, Equatable {
    enum Kind: String, Codable {
        case station
        case track
    }

    let id: UUID
    let kind: Kind
    let userID: String
    let identityKey: String
    let feedback: TuneAVStationFeedback?
    let stationID: String?
    let title: String?
    let artist: String?
    let updatedAt: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        userID: String,
        identityKey: String,
        feedback: TuneAVStationFeedback?,
        stationID: String?,
        title: String?,
        artist: String?,
        updatedAt: String
    ) {
        self.id = id
        self.kind = kind
        self.userID = userID
        self.identityKey = identityKey
        self.feedback = feedback
        self.stationID = stationID
        self.title = title
        self.artist = artist
        self.updatedAt = updatedAt
    }

    var storageKey: String {
        "\(userID):\(kind.rawValue):\(identityKey)"
    }
}

enum TuneAVMacPendingFeedbackOutbox {
    static func upserting(
        _ upload: TuneAVMacPendingFeedbackUpload,
        into uploads: [String: TuneAVMacPendingFeedbackUpload]
    ) -> [String: TuneAVMacPendingFeedbackUpload] {
        var nextUploads = uploads
        nextUploads[upload.storageKey] = upload
        return nextUploads
    }
}

enum TuneAVMacSyncRetryPolicy {
    static func delay(
        retryCount: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        jitterFraction: Double,
        randomFraction: () -> Double = { Double.random(in: 0...1) }
    ) -> TimeInterval {
        guard baseDelay > 0, maxDelay > 0 else { return 0 }

        let boundedRetryCount = max(0, min(retryCount, 10))
        let exponentialDelay = baseDelay * pow(2, Double(boundedRetryCount))
        let cappedDelay = min(exponentialDelay, maxDelay)
        let boundedJitter = max(0, min(jitterFraction, 1))
        let jitterMultiplier = 1 + ((max(0, min(randomFraction(), 1)) * 2) - 1) * boundedJitter

        return min(cappedDelay * jitterMultiplier, maxDelay)
    }
}

struct TuneAVMacFeedbackRequest: Encodable {
    let deviceId: String
    let feedback: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case feedback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        if let feedback {
            try container.encode(feedback, forKey: .feedback)
        } else {
            try container.encodeNil(forKey: .feedback)
        }
    }
}

struct TuneAVMacTrackFeedbackRequest: Encodable {
    let deviceId: String
    let title: String
    let artist: String?
    let stationId: String?
    let feedback: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case title
        case artist
        case stationId
        case feedback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(stationId, forKey: .stationId)
        if let feedback {
            try container.encode(feedback, forKey: .feedback)
        } else {
            try container.encodeNil(forKey: .feedback)
        }
    }
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
    var trackKey: String?
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
        self.trackKey = TuneAVDiscoveredTrackSupport.trackKey(title: normalizedTitle, artist: normalizedArtist, locale: L10n.locale)
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
        self.trackKey = record.trackKey
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
            trackKey: trackKey,
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

private extension TuneAVMacModel.SubscriptionReconciliationSource {
    var diagnosticsOperation: String {
        switch self {
        case .purchase:
            return "purchase"
        case .restore:
            return "restore"
        case .redeemCode:
            return "redeem_code"
        }
    }
}
