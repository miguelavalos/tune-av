import XCTest
import AccountAV
@testable import TuneAVMac

@MainActor
final class LibraryStoreSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: "tuneav.appLanguage")
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: "tuneav.appLanguage")
        super.tearDown()
    }

    func testUITestAccountDeletionScenariosResolveSharedBlockedProSummary() {
        let summary = TuneAVUITestAccountDeletionScenarios.summary(for: "blocked_pro")

        XCTAssertEqual(summary.id, "ui-test-user")
        XCTAssertEqual(summary.access.first?.appId, "tuneav")
        XCTAssertEqual(summary.access.first?.accessMode, .signedInPro)
        XCTAssertEqual(summary.deleteAccountEligibility?.status, .blocked)
        XCTAssertEqual(summary.deleteAccountEligibility?.blockers.first?.type, .activeProAccess)
    }

    func testAccessLimitPolicyMakesDailyProFeaturesUnlimitedAndAppliesUITestOverrides() {
        let limits = TuneAVAccessLimitPolicy.resolvedLimits(
            .forMode(.signedInFree),
            accessMode: .signedInPro,
            environment: [
                "TUNEAV_UI_TESTS": "1",
                "TUNEAV_UI_TEST_FAVORITE_LIMIT": "3",
                "TUNEAV_UI_TEST_LYRICS_LIMIT": "2"
            ]
        )

        XCTAssertEqual(limits.favoriteStations, 3)
        XCTAssertEqual(limits.lyricsSearchesPerDay, 2)
        XCTAssertNil(limits.webSearchesPerDay)
        XCTAssertNil(limits.discoverySharesPerDay)
    }

    func testUpgradePromptContentUsesSharedLimitCopy() {
        let content = TuneAVUpgradePromptContent.forLimitState(
            FeatureLimitState(feature: .savedTracks, currentUsage: 10, limit: 10)
        )

        XCTAssertEqual(content.feature, .savedTracks)
        XCTAssertEqual(content.title, L10n.string("limits.upgrade.savedTracks.title"))
        XCTAssertEqual(content.message, L10n.string("limits.upgrade.savedTracks.message", 10))
        XCTAssertEqual(TuneAVUpgradePromptContent.featureName(for: .savedTracks), L10n.string("mac.limits.feature.savedTracks"))
    }

    func testLaunchContextParsesSharedNavigationAndUITestFlags() {
        let context = TuneAVLaunchContext(environment: [
            "TUNEAV_UI_TESTS": "1",
            "TUNEAV_OPEN_TAB": "music",
            "TUNEAV_SEARCH_QUERY": " ambient radio ",
            "TUNEAV_DEMO_MODE": "1",
            "TUNEAV_SEED_FAVORITE": "1",
            "TUNEAV_UI_TEST_UPGRADE_PROMPT_FEATURE": "spotifySearch",
            "TUNEAV_UI_TEST_CLOUD_SYNC_STATUS": " conflict "
        ])

        XCTAssertEqual(context.preferredTab, .music)
        XCTAssertEqual(context.preferredSearchQuery, "ambient radio")
        XCTAssertEqual(context.demoStation?.id, "demo-groove-salad")
        XCTAssertTrue(context.seedFavorite)
        XCTAssertTrue(context.shouldDisableSplash)
        XCTAssertTrue(context.shouldDisableOnboarding)
        XCTAssertEqual(context.uiTestUpgradePromptFeature, .spotifySearch)
        XCTAssertEqual(context.uiTestCloudSyncStatus, "conflict")
    }

    func testExternalDiscoverySearchActionsResolveSharedDestinationsAndFeatures() {
        let youtube = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Nina Simone Feeling Good",
            destination: .youtube,
            feature: .youtubeSearch
        )
        let lyrics = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Nina Simone Feeling Good",
            destination: .web,
            feature: .lyricsSearch,
            suffix: "lyrics"
        )
        let appleMusic = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Nina Simone Feeling Good",
            destination: .appleMusic,
            feature: .appleMusicSearch
        )
        let spotify = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Nina Simone Feeling Good",
            destination: .spotify,
            feature: .spotifySearch
        )

        XCTAssertEqual(youtube?.feature, .youtubeSearch)
        XCTAssertEqual(youtube?.url.host, "www.youtube.com")
        XCTAssertEqual(queryValue("search_query", in: youtube?.url), "Nina Simone Feeling Good")
        XCTAssertEqual(lyrics?.feature, .lyricsSearch)
        XCTAssertEqual(lyrics?.url.host, "www.google.com")
        XCTAssertEqual(queryValue("q", in: lyrics?.url), "Nina Simone Feeling Good lyrics")
        XCTAssertEqual(appleMusic?.feature, .appleMusicSearch)
        XCTAssertEqual(appleMusic?.url.host, "music.apple.com")
        XCTAssertEqual(queryValue("term", in: appleMusic?.url), "Nina Simone Feeling Good")
        XCTAssertEqual(spotify?.feature, .spotifySearch)
        XCTAssertEqual(spotify?.url.host, "open.spotify.com")
    }

    func testMusicLibraryFiltersDiscoveriesBySavedHistoryArtistAndStation() {
        let firstStation = station(id: "first")
        let secondStation = station(id: "second")
        let savedFirst = DiscoveredTrack(title: "Blue Train", artist: "John Coltrane", station: firstStation, artworkURL: nil, markedInterestedAt: .now)
        let savedSecond = DiscoveredTrack(title: "Naima", artist: "John Coltrane", station: secondStation, artworkURL: nil, markedInterestedAt: .now)
        let historyOnly = DiscoveredTrack(title: "So What", artist: "Miles Davis", station: firstStation, artworkURL: nil)
        let hidden = DiscoveredTrack(title: "Hidden", artist: "Miles Davis", station: firstStation, artworkURL: nil, hiddenAt: .now)

        let discoveries = [savedFirst, savedSecond, historyOnly, hidden]

        XCTAssertEqual(
            TuneAVMusicLibraryLogic.filteredDiscoveries(discoveries, mode: .songs, query: "", selectedArtistName: nil).map(\.title),
            ["Blue Train", "Naima"]
        )
        XCTAssertEqual(
            TuneAVMusicLibraryLogic.filteredDiscoveries(discoveries, mode: .history, query: "", selectedArtistName: nil, historyStationID: firstStation.id).map(\.title),
            ["Blue Train", "So What"]
        )
        XCTAssertEqual(
            TuneAVMusicLibraryLogic.filteredDiscoveries(discoveries, mode: .artists, query: "", selectedArtistName: "John Coltrane").map(\.title),
            ["Blue Train", "Naima"]
        )
        XCTAssertEqual(
            TuneAVMusicLibraryLogic.filteredArtistSummaries(discoveries, mode: .songs, query: "", locale: Locale(identifier: "en_US")).map(\.name),
            ["John Coltrane"]
        )
    }

    func testPlaybackQueueLogicCyclesNextPreviousAndDeduplicatesCurrentQueue() {
        let first = station(id: "first")
        let second = station(id: "second")
        let third = station(id: "third")
        let sanitized = TuneAVPlaybackQueueLogic.sanitizedStations(
            [first, second, second, third],
            currentStation: first,
            currentStationID: first.id
        )
        let resolved = try! XCTUnwrap(TuneAVPlaybackQueueLogic.resolvedQueue(stations: sanitized, currentStation: second))

        XCTAssertEqual(sanitized.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(TuneAVPlaybackQueueLogic.nextStation(in: resolved).id, "third")
        XCTAssertEqual(TuneAVPlaybackQueueLogic.previousStation(in: resolved).id, "first")

        let end = try! XCTUnwrap(TuneAVPlaybackQueueLogic.resolvedQueue(stations: sanitized, currentStation: third))
        XCTAssertEqual(TuneAVPlaybackQueueLogic.nextStation(in: end).id, "first")
        XCTAssertEqual(TuneAVPlaybackQueueLogic.previousStation(in: end).id, "second")
    }

    func testDefaultMacAccountTokenProviderKeepsStartupLocalFirst() async throws {
        let provider = KeychainMacAccountTokenProvider(keychain: MockMacKeychainReader(data: nil))

        let token = try await provider.currentToken()

        XCTAssertNil(token)
    }

    func testGuestOnboardingPolicyUsesSharedCooldown() {
        let policy = GuestOnboardingPolicy(cooldown: 100)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(policy.shouldShowAutomatically(lastPromptAt: nil, now: now))
        XCTAssertFalse(policy.shouldShowAutomatically(lastPromptAt: Date(timeIntervalSince1970: 950), now: now))
        XCTAssertTrue(policy.shouldShowAutomatically(lastPromptAt: Date(timeIntervalSince1970: 899), now: now))
    }

    func testMacAccountControllerTracksGuestOnboardingPromptCooldown() {
        let defaults = isolatedUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        let controller = MacAccountController(
            accountService: MockAccountAVService(isAvailable: true),
            defaults: defaults,
            guestOnboardingPolicy: GuestOnboardingPolicy(cooldown: 100),
            now: { now }
        )

        XCTAssertTrue(controller.shouldAutoShowGuestOnboarding)

        controller.markGuestOnboardingPromptShown()

        XCTAssertFalse(controller.shouldAutoShowGuestOnboarding)
    }

    func testKeychainMacAccountTokenProviderReturnsTrimmedToken() async throws {
        let provider = KeychainMacAccountTokenProvider(
            service: "service",
            account: "account",
            keychain: MockMacKeychainReader(data: Data(" token \n".utf8))
        )

        let token = try await provider.currentToken()

        XCTAssertEqual(token, "token")
    }

    func testKeychainMacAccountTokenProviderIgnoresBlankToken() async throws {
        let provider = KeychainMacAccountTokenProvider(
            service: "service",
            account: "account",
            keychain: MockMacKeychainReader(data: Data(" \n".utf8))
        )

        let token = try await provider.currentToken()

        XCTAssertNil(token)
    }

    func testMacAppConfigOnlyAcceptsHTTPBaseURLs() {
        XCTAssertTrue(URL(string: "https://api.example.com")!.isSupportedAVAccountBaseURL)
        XCTAssertTrue(URL(string: "http://localhost:3000")!.isSupportedAVAccountBaseURL)
        XCTAssertFalse(URL(string: "api.example.com")!.isSupportedAVAccountBaseURL)
        XCTAssertFalse(URL(fileURLWithPath: "/tmp/avaccount").isSupportedAVAccountBaseURL)
    }

    func testSearchRequestNormalizesKeyAndModeLikeIOS() {
        let direct = AppShellSearchRequest(query: "  nova  ", tag: " jazz ", countryCode: " es ")
        let worldwide = AppShellSearchRequest(query: "   ", tag: nil, countryCode: nil)

        XCTAssertEqual(direct.key, "nova|jazz|ES")
        XCTAssertFalse(direct.usesWorldwideDiscovery)
        XCTAssertEqual(direct.searchLimit, 24)
        XCTAssertEqual(worldwide.key, "||")
        XCTAssertTrue(worldwide.usesWorldwideDiscovery)
        XCTAssertEqual(worldwide.searchLimit, 12)
    }

    func testSearchFiltersLocalUITestSamplesLikeIOS() {
        let jazz = Station(
            id: "jazz-es",
            name: "Jazz FM",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "jazz,live",
            streamURL: "https://example.com/jazz"
        )
        let news = Station(
            id: "news-us",
            name: "News Radio",
            country: "United States",
            countryCode: "US",
            language: "English",
            tags: "news",
            streamURL: "https://example.com/news"
        )
        let request = AppShellSearchRequest(query: "jazz", tag: "live", countryCode: "ES")

        XCTAssertEqual(
            AppShellSearch.localUITestSearchResults(samples: [jazz, news], request: request).map(\.id),
            ["jazz-es"]
        )
    }

    func testSearchBuildsOrderedDiscoveryCountryCodesLikeIOS() {
        let recent = Station(
            id: "recent",
            name: "Recent",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "live",
            streamURL: "https://example.com/recent"
        )
        let favorite = Station(
            id: "favorite",
            name: "Favorite",
            country: "France",
            countryCode: "FR",
            language: "French",
            tags: "live",
            streamURL: "https://example.com/favorite"
        )

        XCTAssertEqual(
            AppShellSearch.orderedDiscoveryCountryCodes(
                deviceCountryCode: "es",
                recentStations: [recent],
                favoriteStations: [favorite],
                fallbackCountryCodes: ["US", "ES", "EU"]
            ),
            ["ES", "FR", "US"]
        )
    }

    func testMacAccountAPIClientSendsDeletionRequestWithAccountTokenAndAppHeader() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let baseURL = URL(string: "https://account.example.com")!
        let client = MacAccountAPIClient(
            baseURL: baseURL,
            getToken: { "session-token" },
            urlSession: session
        )
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return Self.httpResponse(
                response: response,
                body: """
                {
                  "status": "inProgress",
                  "deletionJob": {
                    "id": "job_123",
                    "status": "awaitingIdentityDeletion",
                    "detail": "Confirm deletion with Account AV."
                  }
                }
                """
            )
        }

        let response = try await client.requestAccountDeletion()

        XCTAssertEqual(response.job?.id, "job_123")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://account.example.com/v1/me/delete-account-request")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "x-appsav-app-id"), "tuneav")
    }

    func testMacAccountDeletionEligibilityBlocksSharedAccountWithoutBackendEligibility() {
        let summary = MacAccountSummary(
            linkedApps: [
                MacLinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                MacLinkedAccountApp(appId: "avclips", label: "AV Clips")
            ],
            access: [
                macAppAccess(appId: "tuneav", accessMode: .signedInFree),
                macAppAccess(appId: "avclips", accessMode: .signedInPro)
            ],
            billing: MacAccountBillingSummary(
                subscriptions: [
                    MacAccountBillingSubscription(
                        id: "sub_123",
                        appId: "avclips",
                        provider: "Apple",
                        status: "active",
                        managementUrl: URL(string: "https://apps.apple.com/account/subscriptions")
                    )
                ]
            )
        )

        let eligibility = MacAccountDeletionViewModel.conservativeEligibility(from: summary)

        XCTAssertEqual(eligibility.status, .unavailable)
        XCTAssertEqual(
            eligibility.blockers.map(\.type),
            [.linkedApp, .activeProAccess, .activeBillingSubscription]
        )
    }

    func testMacAccountDeletionViewModelCanUnlinkTuneAVFromSharedFreeAccount() async {
        let api = MockMacAccountDeletionAPI(
            summary: MacAccountSummary(
                linkedApps: [
                    MacLinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                    MacLinkedAccountApp(appId: "avclips", label: "AV Clips")
                ],
                access: [
                    macAppAccess(appId: "tuneav", accessMode: .signedInFree),
                    macAppAccess(appId: "avclips", accessMode: .signedInFree)
                ]
            ),
            unlinkResponse: MacUnlinkAppResponse(
                link: MacUnlinkAppResult(appId: "tuneav", remainingLinkedApps: 1, unlinked: true),
                message: "Tune AV unlinked."
            )
        )
        var didSignOut = false
        let viewModel = MacAccountDeletionViewModel(api: api, signOut: {
            didSignOut = true
            return true
        })

        await viewModel.load()
        XCTAssertTrue(viewModel.canUnlinkCurrentApp)

        await viewModel.unlinkCurrentApp()

        XCTAssertTrue(api.didUnlinkCurrentApp)
        XCTAssertTrue(didSignOut)
        XCTAssertTrue(viewModel.didUnlinkCurrentApp)
        XCTAssertEqual(viewModel.unlinkMessage, "Tune AV unlinked.")
    }

    func testDiscoveryShareTextFormatterBuildsLimitedVisibleList() {
        let station = station(id: "share")
        let hidden = DiscoveredTrack(
            title: "Hidden Track",
            artist: "Hidden Artist",
            station: station,
            artworkURL: nil,
            hiddenAt: Date(timeIntervalSince1970: 1)
        )
        let discoveries = [hidden] + (1...26).map { index in
            DiscoveredTrack(
                title: " Song \(index) ",
                artist: index.isMultiple(of: 2) ? nil : " Artist \(index) ",
                station: station,
                artworkURL: nil
            )
        }

        let shareText = DiscoveryShareTextFormatter.text(for: discoveries)
        let lines = shareText.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "Tune AV discoveries")
        XCTAssertEqual(lines.count, 26)
        XCTAssertEqual(lines[1], "Artist 1 - Song 1 - Station share")
        XCTAssertEqual(lines[2], "Song 2 - Station share")
        XCTAssertFalse(shareText.contains("Hidden Track"))
        XCTAssertFalse(shareText.contains("Song 26"))
    }

    func testDiscoveryShareTextFormatterBuildsCurrentTrackText() {
        XCTAssertEqual(
            DiscoveryShareTextFormatter.text(
                title: " Song Title ",
                artist: " Artist Name ",
                stationName: " Station Name "
            ),
            "Artist Name - Song Title · Station Name"
        )

        XCTAssertEqual(
            DiscoveryShareTextFormatter.text(
                title: nil,
                artist: nil,
                stationName: " Station Name "
            ),
            "Station Name"
        )
    }

    func testDiscoveryShareTextFormatterReturnsEmptyForNoVisibleTracks() {
        let hidden = DiscoveredTrack(
            title: "Hidden Track",
            artist: nil,
            station: station(id: "hidden"),
            artworkURL: nil,
            hiddenAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(DiscoveryShareTextFormatter.text(for: [hidden]), "")
    }

    func testAudioStopKeepsCurrentStationAndExposesIOSStatusAlias() {
        let player = AudioPlayerService()
        let station = station(id: "audio-stop")

        player.play(station: station)
        player.stop()

        XCTAssertEqual(player.currentStation?.id, "audio-stop")
        XCTAssertEqual(player.playbackState, .idle)
        XCTAssertEqual(player.status, .idle)
    }

    func testBackendBootstrapAcceptsInjectedMacAccountTokenProvider() async {
        struct StubTokenProvider: MacAccountTokenProviding {
            func currentToken() async throws -> String? {
                "token"
            }
        }

        let store = LibraryStore(defaults: isolatedUserDefaults())
        let provider = StubTokenProvider()

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: provider.currentToken,
            urlSession: mockURLSession(statusCode: 200, body: Self.proAccessResponseJSON)
        )

        XCTAssertEqual(store.accessMode, .signedInPro)
        XCTAssertTrue(store.canRunCloudSync)
    }

    func testBackendBootstrapTreatsUnsupportedBaseURLAsMissingConfiguration() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: URL(fileURLWithPath: "/tmp/avaccount"),
            tokenProvider: { "token" },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .notConfigured)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertFalse(store.canRetryBackendConnection)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for backend config")
    }

    func testAccessModeSourceDistinguishesLocalFallbackFromBackendManagedAccess() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        XCTAssertFalse(store.accessModeIsBackendManaged)
        XCTAssertEqual(store.accessModeSourceTitle, "Local fallback")
        XCTAssertEqual(store.accountConnectionState, .localOnly)
        XCTAssertEqual(store.accountConnectionState.title, "Local mode")

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 200, body: Self.proAccessResponseJSON)
        )

        XCTAssertTrue(store.accessModeIsBackendManaged)
        XCTAssertEqual(store.accessModeSourceTitle, "Backend access")
        XCTAssertEqual(store.accountConnectionState, .connectedPro)
        XCTAssertEqual(store.accountConnectionState.title, "Pro")
    }

    func testAccessControllerResolvesBackendReadyStateByMode() {
        let defaults = isolatedUserDefaults()
        let controller = MacAccessController(defaults: defaults)

        XCTAssertEqual(controller.accessMode, .guest)
        XCTAssertEqual(controller.planTier, .free)
        XCTAssertFalse(controller.capabilities.canUseBackend)
        XCTAssertEqual(controller.limits.favoriteStations, 5)
        XCTAssertEqual(controller.limits.lyricsSearchesPerDay, 3)

        controller.updateAccessMode(.signedInPro)

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.capabilities.canUseBackend)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)
        XCTAssertNil(controller.limits.youtubeSearchesPerDay)
        XCTAssertEqual(defaults.string(forKey: "tuneav.mac.accessMode"), "signedInPro")
    }

    func testAccessControllerRefreshAppliesBackendAccessPayload() async {
        let defaults = isolatedUserDefaults()
        let controller = MacAccessController(defaults: defaults)
        let client = AVAccountMacAccessClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 200, body: """
            {
              "viewer": {
                "isAuthenticated": true,
                "userId": "user_123",
                "identityProvider": "clerk"
              },
              "apps": [
                {
                  "appId": "tuneav",
                  "accessMode": "signedInPro",
                  "planTier": "pro",
                  "capabilities": {
                    "isSignedIn": true,
                    "canUseBackend": true,
                    "canUsePremiumFeatures": true,
                    "canUseCloudSync": true,
                    "canManagePlan": true
                  },
                  "limits": {
                    "favoriteStations": 500,
                    "recentStations": 200,
                    "discoveredTracks": 1000,
                    "savedTracks": 1000,
                    "lyricsSearchesPerDay": null,
                    "youtubeSearchesPerDay": null,
                    "appleMusicSearchesPerDay": null,
                    "spotifySearchesPerDay": null,
                    "discoverySharesPerDay": null
                  }
                }
              ],
              "generatedAt": "2026-05-02T12:00:00.000Z"
            }
            """)
        )

        let didRefresh = await controller.refresh(using: client)

        XCTAssertTrue(didRefresh)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.capabilities.canUseBackend)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)
        XCTAssertNil(controller.limits.spotifySearchesPerDay)
        XCTAssertNil(controller.lastRefreshError)
        XCTAssertEqual(defaults.string(forKey: "tuneav.mac.accessMode"), "signedInPro")
    }

    func testAccessControllerRefreshKeepsLocalFallbackWhenBackendFails() async {
        let defaults = isolatedUserDefaults()
        let controller = MacAccessController(defaults: defaults)
        let client = AVAccountMacAccessClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 503, body: "{}")
        )

        let didRefresh = await controller.refresh(using: client)

        XCTAssertFalse(didRefresh)
        XCTAssertEqual(controller.accessMode, .guest)
        XCTAssertEqual(controller.planTier, .free)
        XCTAssertFalse(controller.capabilities.canUseBackend)
        XCTAssertEqual(controller.limits.favoriteStations, 5)
        XCTAssertEqual(controller.lastRefreshError as? MacAccessRefreshError, .requestFailed(statusCode: 503))
    }

    func testAccessClientRequiresTuneAVAppAccessFromBackendPayload() async {
        let client = AVAccountMacAccessClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 200, body: Self.missingTuneAVAccessResponseJSON)
        )

        do {
            _ = try await client.fetchAccessState()
            XCTFail("Expected missing Tune AV access to fail")
        } catch let error as MacAccessRefreshError {
            XCTAssertEqual(error, .avTunesysAccessMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppDataClientPullsLibraryFromResourceDocuments() async throws {
        var requestedPaths: [String] = []
        let client = MacTuneAVAppDataClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession { request in
                requestedPaths.append(request.url?.path ?? "")
                let resource = request.url?.lastPathComponent ?? ""
                return Self.appDataResourceResponse(resource: resource)
            }
        )

        let document = try await client.pullLibrary()

        XCTAssertEqual(requestedPaths, [
            "/v1/apps/tuneav/data/favorites",
            "/v1/apps/tuneav/data/recents",
            "/v1/apps/tuneav/data/discoveries",
            "/v1/apps/tuneav/data/settings"
        ])
        XCTAssertEqual(document.snapshot?.favorites.map(\.station.id), ["favorite"])
        XCTAssertEqual(document.snapshot?.recents.map(\.station.id), ["recent"])
        XCTAssertEqual(document.snapshot?.discoveries.map(\.discoveryID), ["track-recent"])
        XCTAssertEqual(document.snapshot?.settings.preferredCountry, "ES")
        XCTAssertEqual(document.revision, 8)
    }

    func testAppDataClientPushesLibraryAsSeparateResourceDocuments() async throws {
        var pushedResources: [String] = []
        var pushedDeviceIDs: [String] = []
        let client = MacTuneAVAppDataClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession { request in
                XCTAssertEqual(request.httpMethod, "PUT")
                let body = try XCTUnwrap(Self.requestBodyData(from: request))
                let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let resource = try XCTUnwrap(payload?["resource"] as? String)
                pushedResources.append(resource)
                pushedDeviceIDs.append(try XCTUnwrap(payload?["deviceId"] as? String))
                return Self.appDataResourceResponse(resource: resource)
            }
        )

        try await client.pushLibrary(testSnapshot())

        XCTAssertEqual(pushedResources, ["favorites", "recents", "discoveries", "settings"])
        XCTAssertEqual(pushedDeviceIDs, Array(repeating: "tuneav-macos", count: 4))
    }

    func testAppDataClientRetriesPushAfterRefreshingConflictedResourceVersion() async throws {
        var favoritePutIfMatchHeaders: [String?] = []
        var favoritePullCount = 0
        let client = MacTuneAVAppDataClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession { request in
                let resource = request.url?.lastPathComponent ?? ""
                if resource == "favorites", request.httpMethod == "PUT" {
                    favoritePutIfMatchHeaders.append(request.value(forHTTPHeaderField: "If-Match"))
                    if favoritePutIfMatchHeaders.count == 1 {
                        let response = HTTPURLResponse(
                            url: request.url!,
                            statusCode: 409,
                            httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"]
                        )!
                        return (response, Data("{}".utf8))
                    }
                }
                if resource == "favorites", request.httpMethod == "GET" {
                    favoritePullCount += 1
                }
                return Self.appDataResourceResponse(resource: resource)
            }
        )

        try await client.pushLibrary(testSnapshot())

        XCTAssertEqual(favoritePullCount, 1)
        XCTAssertEqual(favoritePutIfMatchHeaders, [nil, "\"revision-5\""])
    }

    func testAppDataClientThrowsSyncConflictWhenResourceRetryStillConflicts() async throws {
        var favoritePutCount = 0
        let client = MacTuneAVAppDataClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession { request in
                let resource = request.url?.lastPathComponent ?? ""
                if resource == "favorites", request.httpMethod == "PUT" {
                    favoritePutCount += 1
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 409,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, Data("{}".utf8))
                }
                return Self.appDataResourceResponse(resource: resource)
            }
        )

        do {
            try await client.pushLibrary(testSnapshot())
            XCTFail("Expected a sync conflict after the resource retry also conflicts.")
        } catch TuneAVAppDataError.conflict {
            XCTAssertEqual(favoritePutCount, 2)
        } catch {
            XCTFail("Expected TuneAVAppDataError.conflict, got \(error).")
        }
    }

    func testCloudSyncIsIdleWhenAccessDoesNotAllowCloudSync() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: testSnapshot(),
                updatedAt: .now,
                revision: 1,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertEqual(syncClient.pullCount, 0)
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func testManualProModeDoesNotMakeCloudSyncRunnableWithoutBackendClient() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)

        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
    }

    func testAccountSignOutReturnsAccessToGuestWithoutClearingLibrary() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let favorite = station(id: "favorite")
        store.toggleFavorite(favorite)
        store.recordPlayback(of: station(id: "recent"))
        store.setAppDataClient(
            MockMacLibrarySyncClient(
                remoteDocument: TuneAVLibraryDocument(
                    snapshot: nil,
                    updatedAt: .now,
                    revision: 1,
                    etag: nil
                )
            )
        )

        store.handleAccountSignedOut()

        XCTAssertEqual(store.accessMode, .guest)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertEqual(store.favorites.map(\.id), ["favorite"])
        XCTAssertEqual(store.recents.map(\.id), ["recent"])
    }

    func testCloudSyncAppliesRemoteSnapshotForProAccess() async {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        store.updateAccessMode(.signedInPro)
        let remoteUpdatedAt = TuneAVDateCoding.string(from: Date(timeIntervalSinceNow: 60))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: testSnapshot(settingsUpdatedAt: remoteUpdatedAt),
                updatedAt: Date(timeIntervalSinceNow: 60),
                revision: 2,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(store.favorites.map(\.id), ["favorite"])
        XCTAssertEqual(store.recents.map(\.id), ["recent"])
        XCTAssertEqual(store.discoveries.map(\.discoveryID), ["track-recent"])
        XCTAssertEqual(store.preferredCountryCode, "ES")
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
    }

    func testCloudSyncConflictSetsConflictStatus() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(syncClient.pushCount, 1)
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertEqual(store.cloudSyncConflictSummary?.localFavoritesCount, 1)
        XCTAssertEqual(store.cloudSyncConflictSummary?.localRecentsCount, 0)
        XCTAssertEqual(store.cloudSyncConflictSummary?.localDiscoveriesCount, 0)
        XCTAssertFalse(store.cloudSyncConflictSummary?.hasCloudSnapshot ?? true)
        XCTAssertEqual(store.favorites.map(\.id), ["local"])
    }

    func testLocalLibraryMutationClearsStaleCloudSyncStatus() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertNotNil(store.cloudSyncConflictSummary)

        store.toggleFavorite(station(id: "local-after-conflict"))

        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
        XCTAssertNil(store.cloudSyncFailureTitle)
    }

    func testClearingConfiguredCloudSyncClientClearsStaleConflictStatus() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)

        store.setAppDataClient(nil)

        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testReplaceLocalLibraryWithCloudDataResolvesConflictFromCloud() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let remoteUpdatedAt = Date(timeIntervalSinceNow: 60)
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: testSnapshot(settingsUpdatedAt: TuneAVDateCoding.string(from: remoteUpdatedAt)),
                updatedAt: remoteUpdatedAt,
                revision: 2,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertEqual(store.favorites.map(\.id), ["favorite", "local"])
        XCTAssertEqual(store.cloudSyncConflictSummary?.localFavoritesCount, 2)
        XCTAssertEqual(store.cloudSyncConflictSummary?.cloudFavoritesCount, 1)

        await store.replaceLocalLibraryWithCloudData()

        XCTAssertEqual(syncClient.pullCount, 2)
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
        XCTAssertNil(store.cloudSyncConflictSummary)
        XCTAssertEqual(store.favorites.map(\.id), ["favorite"])
        XCTAssertEqual(store.recents.map(\.id), ["recent"])
        XCTAssertEqual(store.discoveries.map(\.discoveryID), ["track-recent"])
        XCTAssertEqual(store.preferredCountryCode, "ES")
    }

    func testReplaceLocalLibraryWithEmptyCloudDataClearsLocalLibrary() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: Date(timeIntervalSinceNow: 60),
                revision: 3,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.replaceLocalLibraryWithCloudData()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
        XCTAssertNil(store.cloudSyncConflictSummary)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(store.recents.isEmpty)
        XCTAssertTrue(store.discoveries.isEmpty)
        XCTAssertNil(store.preferredCountryCode)
        XCTAssertEqual(store.preferredTag, "")
    }

    func testCloudAppliedSnapshotUsesStableUpdatedAtForGeneratedRecordDates() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let remoteUpdatedAt = TuneAVDateCoding.date(from: "2026-05-01T10:00:00.000Z")
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: TuneAVLibrarySnapshot(
                    favorites: [
                        FavoriteStationRecord(
                            station: stationRecord(id: "remote-favorite"),
                            createdAt: "2026-04-30T10:00:00.000Z"
                        )
                    ],
                    recents: [
                        RecentStationRecord(
                            station: stationRecord(id: "remote-recent"),
                            lastPlayedAt: "2026-04-30T11:00:00.000Z"
                        )
                    ],
                    settings: AppSettingsRecord(
                        preferredCountry: "ES",
                        preferredLanguage: "",
                        preferredTag: "ambient",
                        lastPlayedStationID: "remote-recent",
                        sleepTimerMinutes: nil,
                        updatedAt: "2026-04-30T12:00:00.000Z"
                    )
                ),
                updatedAt: remoteUpdatedAt,
                revision: 2,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.replaceLocalLibraryWithCloudData()

        let firstSnapshot = store.librarySnapshot()
        let secondSnapshot = store.librarySnapshot()

        XCTAssertEqual(firstSnapshot.favorites.first?.createdAt, "2026-04-30T10:00:00.000Z")
        XCTAssertEqual(firstSnapshot.recents.first?.lastPlayedAt, "2026-04-30T11:00:00.000Z")
        XCTAssertEqual(firstSnapshot.settings.updatedAt, "2026-05-01T10:00:00.000Z")
        XCTAssertEqual(secondSnapshot, firstSnapshot)
    }

    func testRecordPlaybackPersistsLastPlayedStationIDInSnapshot() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        store.recordPlayback(of: station(id: "first"))
        store.recordPlayback(of: station(id: "second"))

        XCTAssertEqual(store.lastPlayedStationID, "second")
        XCTAssertEqual(store.librarySnapshot().settings.lastPlayedStationID, "second")
        XCTAssertEqual(store.recentStations().map(\.id), ["second", "first"])
    }

    func testSetPreferredTagAndCountryMatchIOSNormalization() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)

        store.setPreferredTag("  jazz  ")
        store.setPreferredCountry("  ES  ")

        XCTAssertEqual(store.librarySnapshot().settings.preferredTag, "jazz")
        XCTAssertEqual(store.librarySnapshot().settings.preferredCountry, "ES")

        store.setPreferredTag(nil)
        store.setPreferredCountry("   ")

        XCTAssertEqual(store.librarySnapshot().settings.preferredTag, "")
        XCTAssertEqual(store.librarySnapshot().settings.preferredCountry, "")
        XCTAssertEqual(LibraryStore(defaults: defaults).preferredTag, "")
        XCTAssertNil(LibraryStore(defaults: defaults).preferredCountryCode)
    }

    func testClearLocalDataKeepsAccessModeAndPropagatesTombstonesOnlyWhenRequested() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInFree)
        let favorite = station(id: "favorite")
        let recent = station(id: "recent")
        store.toggleFavorite(favorite)
        store.recordPlayback(of: recent)
        store.recordDiscoveredTrack(title: "Track", artist: "Artist", station: recent, artworkURL: nil)

        store.clearLocalData(propagatesToCloud: true)

        let propagatedSnapshot = store.librarySnapshot()
        XCTAssertEqual(store.accessMode, .signedInFree)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(propagatedSnapshot.favorites.first?.deletedAt?.isEmpty, false)
        XCTAssertEqual(propagatedSnapshot.recents.first?.deletedAt?.isEmpty, false)
        XCTAssertEqual(propagatedSnapshot.discoveries.first?.deletedAt?.isEmpty, false)
        XCTAssertEqual(propagatedSnapshot.settings.preferredTag, "")
        XCTAssertNil(propagatedSnapshot.settings.lastPlayedStationID)

        store.clearLocalData(propagatesToCloud: false)

        let localOnlySnapshot = store.librarySnapshot()
        XCTAssertTrue(localOnlySnapshot.favorites.isEmpty)
        XCTAssertTrue(localOnlySnapshot.recents.isEmpty)
        XCTAssertTrue(localOnlySnapshot.discoveries.isEmpty)
    }

    func testPreferenceChangesAdvanceLocalSnapshotTimestampForSyncPlanning() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let remoteUpdatedAtString = "2026-05-01T10:00:00.000Z"
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: TuneAVLibrarySnapshot(
                    favorites: [],
                    recents: [],
                    settings: AppSettingsRecord(
                        preferredCountry: "ES",
                        preferredLanguage: "",
                        preferredTag: "ambient",
                        lastPlayedStationID: nil,
                        sleepTimerMinutes: nil,
                        updatedAt: remoteUpdatedAtString
                    )
                ),
                updatedAt: TuneAVDateCoding.date(from: remoteUpdatedAtString),
                revision: 2,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.replaceLocalLibraryWithCloudData()
        XCTAssertEqual(store.librarySnapshot().settings.updatedAt, remoteUpdatedAtString)

        store.updatePreferredTag("jazz")

        let updatedSnapshot = store.librarySnapshot()
        XCTAssertEqual(updatedSnapshot.settings.preferredTag, "jazz")
        XCTAssertNotEqual(updatedSnapshot.settings.updatedAt, remoteUpdatedAtString)
    }

    func testSleepTimerSettingRoundTripsThroughSnapshotAndDefaults() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)

        store.updateSleepTimerMinutes(30)

        XCTAssertEqual(store.librarySnapshot().settings.sleepTimerMinutes, 30)
        XCTAssertEqual(LibraryStore(defaults: defaults).sleepTimerMinutes, 30)

        let remoteSnapshot = TuneAVLibrarySnapshot(
            favorites: [],
            recents: [],
            discoveries: [],
            settings: AppSettingsRecord(
                preferredCountry: "",
                preferredLanguage: "",
                preferredTag: "ambient",
                lastPlayedStationID: nil,
                sleepTimerMinutes: 45,
                updatedAt: "2026-04-30T12:00:00.000Z"
            )
        )

        store.applyLibrarySnapshot(remoteSnapshot)

        XCTAssertEqual(store.sleepTimerMinutes, 45)
        XCTAssertEqual(LibraryStore(defaults: defaults).sleepTimerMinutes, 45)

        store.updateSleepTimerMinutes(nil)

        XCTAssertNil(store.librarySnapshot().settings.sleepTimerMinutes)
        XCTAssertNil(LibraryStore(defaults: defaults).sleepTimerMinutes)
    }

    func testReplaceLocalLibraryWithCloudDataWithoutBackendClearsStaleConflictSummary() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertNotNil(store.cloudSyncConflictSummary)
        XCTAssertTrue(store.canResolveCloudConflict)

        store.setAppDataClient(nil)
        XCTAssertFalse(store.canResolveCloudConflict)
        await store.replaceLocalLibraryWithCloudData()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testRefreshWithoutBackendClearsStaleConflictSummary() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertNotNil(store.cloudSyncConflictSummary)
        XCTAssertTrue(store.canResolveCloudConflict)

        store.setAppDataClient(nil)
        XCTAssertFalse(store.canResolveCloudConflict)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testOverwriteWithoutBackendClearsStaleConflictSummary() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertNotNil(store.cloudSyncConflictSummary)
        XCTAssertTrue(store.canResolveCloudConflict)

        store.setAppDataClient(nil)
        XCTAssertFalse(store.canResolveCloudConflict)
        await store.overwriteCloudLibraryWithLocalData()

        XCTAssertEqual(syncClient.overwriteCount, 0)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testCloudSyncMissingTokenClearsConfiguredBackendClient() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pullError: MacAppDataClientError.missingToken
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(syncClient.pullCount, 1)
        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertNil(store.backendConnectionFailureTitle)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testCloudSyncUnauthorizedOverwriteClearsConfiguredBackendClient() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: MacAppDataClientError.requestFailed(statusCode: 403)
        )

        store.setAppDataClient(syncClient)
        await store.overwriteCloudLibraryWithLocalData()

        XCTAssertEqual(syncClient.overwriteCount, 1)
        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertEqual(store.backendConnectionFailureTitle, "Sync request failed (403)")
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
    }

    func testOverwriteCloudLibraryWithLocalDataUsesConfiguredProClient() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        await store.overwriteCloudLibraryWithLocalData()

        XCTAssertEqual(syncClient.overwriteCount, 1)
        XCTAssertEqual(syncClient.pushedSnapshots.first?.favorites.map(\.station.id), ["local"])
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
    }

    func testOverwriteCloudLibraryWithoutConfiguredBackendStaysIdle() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))

        await store.overwriteCloudLibraryWithLocalData()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncFailureTitle)
        XCTAssertFalse(store.canRunCloudSync)
    }

    func testCloudSyncFailureStoresDisplayableReason() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pullError: MacAppDataClientError.requestFailed(statusCode: 503)
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.cloudSyncStatus, .failed)
        XCTAssertTrue(store.canClearCloudSyncStatus)
        XCTAssertEqual(store.cloudSyncFailureTitle, "Sync request failed (503)")

        store.clearCloudSyncStatus()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertFalse(store.canClearCloudSyncStatus)
        XCTAssertNil(store.cloudSyncFailureTitle)
    }

    func testCloudSyncStatusCannotBeClearedWhileSyncing() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        let syncClient = BlockingMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            )
        )

        store.setAppDataClient(syncClient)
        let syncTask = Task {
            await store.refreshCloudLibraryIfNeeded()
        }

        while syncClient.pullCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(store.cloudSyncStatus, .syncing)
        XCTAssertFalse(store.canClearCloudSyncStatus)

        store.clearCloudSyncStatus()

        XCTAssertEqual(store.cloudSyncStatus, .syncing)

        syncClient.resumePull()
        await syncTask.value

        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
        XCTAssertTrue(store.canClearCloudSyncStatus)
    }

    func testBackendBootstrapTracksMissingBackendConfiguration() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: nil,
            tokenProvider: { "token" },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .notConfigured)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertFalse(store.canRetryBackendConnection)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for backend config")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Backend configuration is missing for this build.")
    }

    func testBackendBootstrapConfiguresAccessAndCloudSyncClient() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let remoteUpdatedAt = TuneAVDateCoding.string(from: Date(timeIntervalSinceNow: 60))
        let session = mockURLSession { request in
            switch request.url?.path {
            case "/v1/me/access":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(Self.proAccessResponseJSON.utf8))
            default:
                let resource = request.url?.lastPathComponent ?? ""
                var (response, data) = Self.appDataResourceResponse(resource: resource)
                if resource == "settings", let body = String(data: data, encoding: .utf8) {
                    data = Data(body.replacingOccurrences(
                        of: "2026-04-30T12:00:00.000Z",
                        with: remoteUpdatedAt
                    ).utf8)
                }
                return (response, data)
            }
        }

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: session
        )
        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.accessMode, .signedInPro)
        XCTAssertEqual(store.planTier, .pro)
        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertEqual(store.accountConnectionState, .connectedPro)
        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertTrue(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Ready")
        XCTAssertNil(store.cloudSyncBlockerDescription)
        XCTAssertEqual(store.favorites.map(\.id), ["favorite"])
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
    }

    func testSuccessfulBackendBootstrapClearsStaleSyncConflictState() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.toggleFavorite(station(id: "local"))
        let syncClient = MockMacLibrarySyncClient(
            remoteDocument: TuneAVLibraryDocument(
                snapshot: nil,
                updatedAt: .distantPast,
                revision: 0,
                etag: nil
            ),
            pushError: TuneAVAppDataError.conflict
        )

        store.setAppDataClient(syncClient)
        await store.refreshCloudLibraryIfNeeded()
        XCTAssertEqual(store.cloudSyncStatus, .conflict)
        XCTAssertNotNil(store.cloudSyncConflictSummary)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 200, body: Self.proAccessResponseJSON)
        )

        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertNil(store.cloudSyncConflictSummary)
        XCTAssertTrue(store.isCloudSyncConfigured)
        XCTAssertTrue(store.canRunCloudSync)
    }

    func testBackendBootstrapAppliesRefreshedAccessLimitsToLocalCollections() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        for index in 0..<60 {
            let station = station(id: "station-\(index)")
            store.toggleFavorite(station)
            store.recordDiscoveredTrack(
                title: "Saved Track \(index)",
                artist: "Artist",
                station: station,
                artworkURL: nil
            )
            store.markTrackInteresting(
                title: "Saved Track \(index)",
                artist: "Artist",
                station: station,
                artworkURL: nil
            )
        }
        XCTAssertEqual(store.favorites.count, 60)
        XCTAssertEqual(store.discoveries.filter(\.isMarkedInteresting).count, 60)

        let session = mockURLSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(Self.freeAccessResponseJSON.utf8))
        }

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: session
        )

        XCTAssertEqual(store.accessMode, .signedInFree)
        XCTAssertEqual(store.planTier, .free)
        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertEqual(store.accountConnectionState, .connectedFree)
        XCTAssertFalse(store.capabilities.canUseCloudSync)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Pro only")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Cloud Sync is available with Pro access.")
        XCTAssertEqual(store.favorites.count, 50)
        XCTAssertEqual(store.discoveries.filter(\.isMarkedInteresting).count, 20)

        store.updateAccessMode(.signedInPro)

        XCTAssertEqual(store.accessMode, .signedInFree)
        XCTAssertEqual(store.planTier, .free)
        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertEqual(store.accountConnectionState, .connectedFree)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Pro only")
    }

    func testBackendBootstrapRequiresInitialTokenBeforeConfiguringCloudSync() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "" },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertEqual(store.accountConnectionState, .waitingForToken)
        XCTAssertNil(store.backendConnectionFailureTitle)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for account token")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Connect an account before syncing this Mac.")

        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
    }

    func testRetryBackendConnectionUsesStoredBootstrapAfterTokenAppears() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        var token = ""

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { token },
            urlSession: mockURLSession(expectedAuthorization: "Bearer token") { request in
                XCTAssertEqual(request.url?.path, "/v1/me/access")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(Self.proAccessResponseJSON.utf8))
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertFalse(store.canRunCloudSync)

        token = "token"
        await store.retryBackendConnection()

        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertEqual(store.accessMode, .signedInPro)
        XCTAssertTrue(store.canRunCloudSync)
    }

    func testRetryBackendConnectionCTARequiresStoredBootstrapAttempt() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertFalse(store.canRetryBackendConnection)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "" },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertTrue(store.canRetryBackendConnection)
    }

    func testLeavingProFallbackClearsStoredBackendRetryContext() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "" },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertTrue(store.canRetryBackendConnection)

        store.updateAccessMode(.guest)
        store.updateAccessMode(.signedInPro)

        XCTAssertEqual(store.backendConnectionStatus, .notConfigured)
        XCTAssertFalse(store.canRetryBackendConnection)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for backend config")
    }

    func testBackendBootstrapRequiresSuccessfulAccessRefreshBeforeConfiguringCloudSync() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(expectedAuthorization: "Bearer token") { request in
                XCTAssertEqual(request.url?.path, "/v1/me/access")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{}".utf8))
            }
        )

        XCTAssertEqual(store.accessMode, .signedInPro)
        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .accessRefreshFailed)
        XCTAssertEqual(store.accountConnectionState, .accessRefreshFailed)
        XCTAssertEqual(store.backendConnectionFailureTitle, "Access request failed (503)")
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Access refresh failed")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Refresh backend access before syncing this Mac.")

        await store.refreshCloudLibraryIfNeeded()

        XCTAssertEqual(store.cloudSyncStatus, .idle)
    }

    func testBackendRetryAvailableAfterAccessRefreshFailureFromLocalFallback() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(expectedAuthorization: "Bearer token") { request in
                XCTAssertEqual(request.url?.path, "/v1/me/access")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{}".utf8))
            }
        )

        XCTAssertEqual(store.accessMode, .guest)
        XCTAssertFalse(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .accessRefreshFailed)
        XCTAssertTrue(store.canRetryBackendConnection)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Access refresh failed")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Refresh backend access before syncing this Mac.")
    }

    func testBackendBootstrapHandlesMissingTuneAVAccessAsRefreshFailure() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(statusCode: 200, body: Self.missingTuneAVAccessResponseJSON)
        )

        XCTAssertEqual(store.accessMode, .guest)
        XCTAssertFalse(store.accessModeIsBackendManaged)
        XCTAssertFalse(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .accessRefreshFailed)
        XCTAssertEqual(store.accountConnectionState, .accessRefreshFailed)
        XCTAssertEqual(store.backendConnectionFailureTitle, "Tune AV access missing")
        XCTAssertTrue(store.canRetryBackendConnection)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Access refresh failed")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Refresh backend access before syncing this Mac.")
    }

    func testBackendRetryAvailableAfterMissingTokenFromLocalFallback() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { nil },
            urlSession: mockURLSession(expectedAuthorization: nil) { request in
                XCTFail("Unexpected backend request: \(request.url?.absoluteString ?? "")")
                return Self.appDataResourceResponse(resource: "settings")
            }
        )

        XCTAssertEqual(store.accessMode, .guest)
        XCTAssertFalse(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertTrue(store.canRetryBackendConnection)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for account token")
        XCTAssertEqual(store.cloudSyncBlockerDescription, "Connect an account before syncing this Mac.")
    }

    func testBackendBootstrapMapsUnauthorizedAccessRefreshToMissingToken() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "expired-token" },
            urlSession: mockURLSession(expectedAuthorization: "Bearer expired-token") { request in
                XCTAssertEqual(request.url?.path, "/v1/me/access")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{}".utf8))
            }
        )

        XCTAssertEqual(store.accessMode, .signedInPro)
        XCTAssertTrue(store.capabilities.canUseCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .missingToken)
        XCTAssertEqual(store.backendConnectionFailureTitle, "Access request failed (401)")
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.cloudSyncReadinessTitle, "Waiting for account token")
    }

    func testRetryBackendConnectionCanRecoverAfterAccessRefreshFailure() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        var shouldFailAccessRefresh = true

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { "token" },
            urlSession: mockURLSession(expectedAuthorization: "Bearer token") { request in
                XCTAssertEqual(request.url?.path, "/v1/me/access")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: shouldFailAccessRefresh ? 503 : 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let body = shouldFailAccessRefresh ? "{}" : Self.proAccessResponseJSON
                return (response, Data(body.utf8))
            }
        )

        XCTAssertEqual(store.backendConnectionStatus, .accessRefreshFailed)
        XCTAssertEqual(store.backendConnectionFailureTitle, "Access request failed (503)")
        XCTAssertFalse(store.canRunCloudSync)

        shouldFailAccessRefresh = false
        await store.retryBackendConnection()

        XCTAssertEqual(store.backendConnectionStatus, .ready)
        XCTAssertNil(store.backendConnectionFailureTitle)
        XCTAssertTrue(store.canRunCloudSync)
    }

    func testBackendClientsUseLiveTokenProviderAfterBootstrap() async {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        var token = "bootstrap-token"
        var appDataAuthorizations: [String] = []
        let session = mockURLSession(expectedAuthorization: nil) { request in
            switch request.url?.path {
            case "/v1/me/access":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bootstrap-token")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(Self.proAccessResponseJSON.utf8))
            default:
                appDataAuthorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                return Self.appDataResourceResponse(resource: request.url?.lastPathComponent ?? "")
            }
        }

        await store.configureBackendClients(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: { token },
            urlSession: session
        )
        token = "rotated-token"

        await store.refreshCloudLibraryIfNeeded()

        XCTAssertFalse(appDataAuthorizations.isEmpty)
        XCTAssertTrue(appDataAuthorizations.allSatisfy { $0 == "Bearer rotated-token" })
        XCTAssertEqual(store.cloudSyncStatus.isSynced, true)
    }

    func testChangingAccessModeTrimsLocalCollectionsToGuestLimits() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        store.updateAccessMode(.signedInPro)
        store.setAppDataClient(
            MockMacLibrarySyncClient(
                remoteDocument: TuneAVLibraryDocument(
                    snapshot: nil,
                    updatedAt: .distantPast,
                    revision: 0,
                    etag: nil
                )
            )
        )

        for index in 0..<12 {
            let station = station(id: "station-\(index)")
            store.toggleFavorite(station)
            store.recordPlayback(of: station)
        }
        for index in 0..<24 {
            store.recordDiscoveredTrack(
                title: "Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index % 12)"),
                artworkURL: nil
            )
        }
        for index in 0..<12 {
            store.markTrackInteresting(
                title: "Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index % 12)"),
                artworkURL: nil
            )
        }

        store.updateAccessMode(.guest)

        XCTAssertEqual(store.favorites.count, 5)
        XCTAssertEqual(store.recents.count, 10)
        XCTAssertEqual(store.discoveries.count, 20)
        XCTAssertEqual(store.discoveries.filter(\.isMarkedInteresting).count, 5)
        XCTAssertEqual(store.backendConnectionStatus, .notConfigured)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertFalse(store.canRunCloudSync)
    }

    func testRecordingDiscoveriesHonorsExplicitDiscoveryLimit() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        for index in 0..<5 {
            store.recordDiscoveredTrack(
                title: "Limited Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index)"),
                artworkURL: nil,
                discoveryLimit: 3
            )
        }

        XCTAssertEqual(store.discoveries.count, 3)
    }

    func testSavingDiscoveryHonorsExplicitDiscoveryLimit() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        for index in 0..<4 {
            store.markTrackInteresting(
                title: "Saved Limited Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index)"),
                artworkURL: nil,
                discoveryLimit: 2
            )
        }

        XCTAssertEqual(store.discoveries.count, 2)
        XCTAssertEqual(store.discoveries.filter(\.isMarkedInteresting).count, 2)
    }

    func testTogglingExistingDiscoverySavedHonorsExplicitSavedLimit() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let firstStation = station(id: "saved-limit-1")
        let secondStation = station(id: "saved-limit-2")

        XCTAssertTrue(
            store.toggleDiscoveredTrackSaved(
                title: "Saved Track 1",
                artist: "Artist",
                station: firstStation,
                artworkURL: nil,
                savedLimit: 1,
                discoveryLimit: 10
            )
        )
        store.recordDiscoveredTrack(
            title: "Saved Track 2",
            artist: "Artist",
            station: secondStation,
            artworkURL: nil,
            discoveryLimit: 10
        )

        XCTAssertFalse(
            store.toggleDiscoveredTrackSaved(
                title: "Saved Track 2",
                artist: "Artist",
                station: secondStation,
                artworkURL: nil,
                savedLimit: 1,
                discoveryLimit: 10
            )
        )
        XCTAssertFalse(store.isSavedDiscoveredTrack(title: "Saved Track 2", artist: "Artist", station: secondStation))
        XCTAssertEqual(store.savedDiscoveriesCount, 1)
    }

    func testToggleDiscoveredTrackSavedSavesAndUnsavesCurrentTrack() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let station = station(id: "toggle-saved-track")

        let didSave = store.toggleDiscoveredTrackSaved(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 25
        )

        XCTAssertTrue(didSave)
        XCTAssertTrue(store.isSavedDiscoveredTrack(title: "Sweet Song", artist: "The Tests", station: station))
        XCTAssertEqual(store.savedDiscoveriesCount, 1)

        let didUnsave = store.toggleDiscoveredTrackSaved(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 25
        )

        XCTAssertTrue(didUnsave)
        XCTAssertFalse(store.isSavedDiscoveredTrack(title: "Sweet Song", artist: "The Tests", station: station))
        XCTAssertEqual(store.savedDiscoveriesCount, 0)
    }

    func testLoadingGuestStateTrimsPersistedSavedTracksToLimit() {
        let defaults = isolatedUserDefaults()
        let proStore = LibraryStore(defaults: defaults)
        proStore.updateAccessMode(.signedInPro)

        for index in 0..<8 {
            proStore.recordDiscoveredTrack(
                title: "Saved Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index)"),
                artworkURL: nil
            )
            proStore.markTrackInteresting(
                title: "Saved Track \(index)",
                artist: "Artist",
                station: station(id: "station-\(index)"),
                artworkURL: nil
            )
        }
        XCTAssertEqual(proStore.discoveries.filter(\.isMarkedInteresting).count, 8)
        defaults.set("guest", forKey: "tuneav.mac.accessMode")

        let reloadedStore = LibraryStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.accessMode, .guest)
        XCTAssertEqual(reloadedStore.discoveries.filter(\.isMarkedInteresting).count, 5)
    }

    func testClearLocalStateResetsAccessControllerAndCloudSyncState() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        store.updateAccessMode(.signedInPro)
        store.setAppDataClient(
            MockMacLibrarySyncClient(
                remoteDocument: TuneAVLibraryDocument(
                    snapshot: nil,
                    updatedAt: .distantPast,
                    revision: 0,
                    etag: nil
                )
            )
        )
        store.toggleFavorite(station(id: "local"))
        store.clearLocalState()

        XCTAssertEqual(store.accessMode, .guest)
        XCTAssertFalse(store.capabilities.canUseCloudSync)
        XCTAssertFalse(store.canRunCloudSync)
        XCTAssertEqual(store.backendConnectionStatus, .notConfigured)
        XCTAssertFalse(store.isCloudSyncConfigured)
        XCTAssertEqual(store.cloudSyncStatus, .idle)
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func testClearLocalStateResetsDailyCountersAndUpgradePrompt() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/1"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/2"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/3"))
        XCTAssertFalse(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/4"))
        XCTAssertNotNil(store.upgradePrompt)

        store.clearLocalState()

        XCTAssertNil(store.upgradePrompt)
        XCTAssertEqual(store.dailyUsage(for: .youtubeSearch), LimitUsageSummary(used: 0, limit: 3))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/4"))
    }

    func testGuestDailyCountersPromptAtBackendAlignedLimit() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/1"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/2"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/3"))
        XCTAssertFalse(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/4"))

        XCTAssertEqual(store.upgradePrompt?.title, "Daily YouTube opens limit reached")
        XCTAssertEqual(store.upgradePrompt?.progressText, "3 of 3 used today")
    }

    func testLimitUsageSummariesTrackCollectionsAndDailyCounters() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let firstStation = station(id: "usage-1")
        let secondStation = station(id: "usage-2")

        store.toggleFavorite(firstStation)
        store.toggleFavorite(secondStation)
        store.recordPlayback(of: firstStation)
        store.recordDiscoveredTrack(
            title: "Track 1",
            artist: "Artist",
            station: firstStation,
            artworkURL: nil
        )
        store.markTrackInteresting(
            title: "Track 1",
            artist: "Artist",
            station: firstStation,
            artworkURL: nil
        )
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/1"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.youtubeSearch, usageKey: "https://example.com/2"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.webSearch, usageKey: "https://example.com/search?q=ambient"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.discoveryShare, usageKey: "Artist - Track"))

        XCTAssertEqual(store.favoritesUsage, LimitUsageSummary(used: 2, limit: 5))
        XCTAssertEqual(store.favoritesUsage.title, "2 of 5")
        XCTAssertEqual(store.recentsUsage, LimitUsageSummary(used: 1, limit: 10))
        XCTAssertEqual(store.discoveriesUsage, LimitUsageSummary(used: 1, limit: 20))
        XCTAssertEqual(store.savedTracksUsage, LimitUsageSummary(used: 1, limit: 5))
        XCTAssertEqual(store.dailyUsage(for: .webSearch), LimitUsageSummary(used: 1, limit: 3))
        XCTAssertEqual(store.dailyUsage(for: .youtubeSearch), LimitUsageSummary(used: 2, limit: 3))
        XCTAssertEqual(store.dailyUsage(for: .discoveryShare), LimitUsageSummary(used: 1, limit: 1))
    }

    func testFavoriteLimitShowsUpgradePrompt() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        for index in 0..<5 {
            store.toggleFavorite(station(id: "favorite-\(index)"))
        }

        store.toggleFavorite(station(id: "favorite-over-limit"))

        XCTAssertEqual(store.favorites.count, 5)
        XCTAssertEqual(store.upgradePrompt?.title, "Favorites limit reached")
        XCTAssertEqual(store.upgradePrompt?.progressText, "5 of 5 favorites used")
    }

    func testSavedTrackLimitShowsNonDailyUpgradePrompt() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        for index in 0..<5 {
            store.markTrackInteresting(
                title: "Track \(index)",
                artist: "Artist",
                station: station(id: "saved-\(index)"),
                artworkURL: nil
            )
        }

        store.markTrackInteresting(
            title: "Track over limit",
            artist: "Artist",
            station: station(id: "saved-over-limit"),
            artworkURL: nil
        )

        XCTAssertEqual(store.savedTracksUsage, LimitUsageSummary(used: 5, limit: 5))
        XCTAssertEqual(store.upgradePrompt?.title, "Saved songs limit reached")
        XCTAssertEqual(store.upgradePrompt?.progressText, "5 of 5 saved tracks used")
    }

    func testApplyLibrarySnapshotPersistsRoundTripState() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        let favorite = stationRecord(id: "favorite")
        let recent = stationRecord(id: "recent")
        let snapshot = TuneAVLibrarySnapshot(
            favorites: [
                FavoriteStationRecord(
                    station: favorite,
                    createdAt: "2026-04-30T10:00:00.000Z"
                )
            ],
            recents: [
                RecentStationRecord(
                    station: recent,
                    lastPlayedAt: "2026-04-30T11:00:00.000Z"
                )
            ],
            discoveries: [
                DiscoveredTrackRecord(
                    discoveryID: "track-recent",
                    title: "Midnight Signal",
                    artist: "AV Artist",
                    stationID: "recent",
                    stationName: "Station recent",
                    artworkURL: "https://example.com/track.jpg",
                    stationArtworkURL: "https://example.com/station.jpg",
                    playedAt: "2026-04-30T11:30:00.000Z",
                    markedInterestedAt: "2026-04-30T11:31:00.000Z",
                    hiddenAt: nil
                )
            ],
            settings: AppSettingsRecord(
                preferredCountry: "ES",
                preferredLanguage: "",
                preferredTag: "ambient",
                lastPlayedStationID: "recent",
                sleepTimerMinutes: nil,
                updatedAt: "2026-04-30T12:00:00.000Z"
            )
        )

        store.applyLibrarySnapshot(snapshot)
        let reloadedStore = LibraryStore(defaults: defaults)
        let reloadedSnapshot = reloadedStore.librarySnapshot()

        XCTAssertEqual(reloadedSnapshot.favorites.map(\.station.id), ["favorite"])
        XCTAssertEqual(reloadedSnapshot.recents.map(\.station.id), ["recent"])
        XCTAssertEqual(reloadedSnapshot.discoveries.map(\.discoveryID), ["track-recent"])
        XCTAssertEqual(reloadedSnapshot.discoveries.first?.title, "Midnight Signal")
        XCTAssertEqual(reloadedSnapshot.discoveries.first?.artist, "AV Artist")
        XCTAssertEqual(reloadedSnapshot.settings.preferredCountry, "ES")
        XCTAssertEqual(reloadedSnapshot.settings.preferredTag, "ambient")
        XCTAssertEqual(reloadedSnapshot.settings.lastPlayedStationID, "recent")
    }

    func testRemovedDiscoveryPersistsTombstoneAndWinsOverOlderRemoteSavedTrack() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        let station = station(id: "music-station")

        store.markTrackInteresting(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: nil
        )

        let existingRecord = try! XCTUnwrap(store.discoveries.first?.appDataRecord)
        let existingDiscovery = try! XCTUnwrap(store.discoveries.first)
        store.removeDiscovery(existingDiscovery)

        let localSnapshot = store.librarySnapshot()
        let deletionRecord = try! XCTUnwrap(localSnapshot.discoveries.first)
        let remoteSnapshot = TuneAVLibrarySnapshot(
            favorites: [],
            recents: [],
            discoveries: [
                DiscoveredTrackRecord(
                    discoveryID: existingRecord.discoveryID,
                    title: existingRecord.title,
                    artist: existingRecord.artist,
                    stationID: existingRecord.stationID,
                    stationName: existingRecord.stationName,
                    artworkURL: existingRecord.artworkURL,
                    stationArtworkURL: existingRecord.stationArtworkURL,
                    playedAt: "2026-04-30T10:00:00.000Z",
                    markedInterestedAt: "2026-04-30T10:05:00.000Z"
                )
            ],
            settings: .empty
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
        store.applyLibrarySnapshot(merged)
        let reloadedSnapshot = LibraryStore(defaults: defaults).librarySnapshot()

        XCTAssertTrue(store.discoveries.isEmpty)
        XCTAssertNotNil(deletionRecord.deletedAt)
        XCTAssertEqual(merged.discoveries.first?.deletedAt, deletionRecord.deletedAt)
        XCTAssertTrue(LibraryStore(defaults: defaults).discoveries.isEmpty)
        XCTAssertEqual(reloadedSnapshot.discoveries.first?.deletedAt, deletionRecord.deletedAt)
    }

    func testRemovedFavoritePersistsTombstoneAndWinsOverOlderRemoteFavorite() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        let favoriteStation = station(id: "favorite-radio")

        store.toggleFavorite(favoriteStation)
        store.toggleFavorite(favoriteStation)

        let localSnapshot = store.librarySnapshot()
        let deletionRecord = try! XCTUnwrap(localSnapshot.favorites.first)
        let remoteSnapshot = TuneAVLibrarySnapshot(
            favorites: [
                FavoriteStationRecord(
                    station: favoriteStation.appDataRecord,
                    createdAt: "2026-04-30T10:00:00.000Z"
                )
            ],
            recents: [],
            discoveries: [],
            settings: .empty
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
        store.applyLibrarySnapshot(merged)
        let reloadedSnapshot = LibraryStore(defaults: defaults).librarySnapshot()

        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertNotNil(deletionRecord.deletedAt)
        XCTAssertEqual(merged.favorites.first?.deletedAt, deletionRecord.deletedAt)
        XCTAssertTrue(LibraryStore(defaults: defaults).favorites.isEmpty)
        XCTAssertEqual(reloadedSnapshot.favorites.first?.deletedAt, deletionRecord.deletedAt)
    }

    func testTrimmedRecentPersistsTombstoneAndWinsOverOlderRemoteRecent() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)

        for index in 0..<11 {
            store.recordPlayback(of: station(id: "recent-\(index)"))
        }

        let localSnapshot = store.librarySnapshot()
        let deletionRecord = try! XCTUnwrap(localSnapshot.recents.first { $0.station.id == "recent-0" })
        let remoteSnapshot = TuneAVLibrarySnapshot(
            favorites: [],
            recents: [
                RecentStationRecord(
                    station: stationRecord(id: "recent-0"),
                    lastPlayedAt: "2026-04-30T10:00:00.000Z"
                )
            ],
            discoveries: [],
            settings: .empty
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
        store.applyLibrarySnapshot(merged)
        let reloadedSnapshot = LibraryStore(defaults: defaults).librarySnapshot()

        XCTAssertFalse(store.recents.contains { $0.id == "recent-0" })
        XCTAssertNotNil(deletionRecord.deletedAt)
        XCTAssertEqual(merged.recents.first { $0.station.id == "recent-0" }?.deletedAt, deletionRecord.deletedAt)
        XCTAssertFalse(LibraryStore(defaults: defaults).recents.contains { $0.id == "recent-0" })
        XCTAssertEqual(reloadedSnapshot.recents.first { $0.station.id == "recent-0" }?.deletedAt, deletionRecord.deletedAt)
    }

    func testApplyLibrarySnapshotClearsEmptyCountryAndDefaultsEmptyTag() {
        let defaults = isolatedUserDefaults()
        let store = LibraryStore(defaults: defaults)
        let snapshot = TuneAVLibrarySnapshot(
            favorites: [],
            recents: [],
            discoveries: [],
            settings: AppSettingsRecord(
                preferredCountry: "",
                preferredLanguage: "",
                preferredTag: "",
                lastPlayedStationID: nil,
                sleepTimerMinutes: nil,
                updatedAt: "2026-04-30T12:00:00.000Z"
            )
        )

        store.applyLibrarySnapshot(snapshot)
        let reloadedStore = LibraryStore(defaults: defaults)

        XCTAssertNil(reloadedStore.preferredCountryCode)
        XCTAssertEqual(reloadedStore.preferredTag, "")
    }

    func testDailyFeatureUsageKeysOnlyCountUniqueUses() {
        let store = LibraryStore(defaults: isolatedUserDefaults())
        let lyricsURL = "https://www.google.com/search?q=artist%20song%20lyrics"

        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: lyricsURL))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: lyricsURL))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: "  \(lyricsURL.uppercased())  "))

        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: "https://www.google.com/search?q=artist%20song%202%20lyrics"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: "https://www.google.com/search?q=artist%20song%203%20lyrics"))
        XCTAssertTrue(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: lyricsURL))
        XCTAssertFalse(store.useDailyFeatureIfAllowed(.lyricsSearch, usageKey: "https://www.google.com/search?q=artist%20song%204%20lyrics"))
    }

    func testCollectionFeaturesDoNotUseDailyCounters() {
        let store = LibraryStore(defaults: isolatedUserDefaults())

        XCTAssertEqual(store.dailyUsage(for: .savedTracks), LimitUsageSummary(used: 0, limit: nil))

        for index in 0..<10 {
            XCTAssertTrue(store.useDailyFeatureIfAllowed(.savedTracks, usageKey: "saved-\(index)"))
        }

        XCTAssertNil(store.upgradePrompt)
        XCTAssertEqual(store.dailyUsage(for: .savedTracks), LimitUsageSummary(used: 0, limit: nil))
    }

    private func isolatedUserDefaults() -> UserDefaults {
        let suiteName = "LibraryStoreSnapshotTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func macAppAccess(appId: String, accessMode: AccessMode) -> MacAppAccess {
        MacAppAccess(
            appId: appId,
            accessMode: accessMode,
            planTier: accessMode == .signedInPro ? .pro : .free,
            capabilities: AccessCapabilities.forMode(accessMode),
            limits: AccessLimits.forMode(accessMode)
        )
    }

    private func mockURLSession(statusCode: Int, body: String) -> URLSession {
        mockURLSession { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
    }

    private static func httpResponse(response: HTTPURLResponse, body: String) -> (HTTPURLResponse, Data) {
        (response, Data(body.utf8))
    }

    private func mockURLSession(
        expectedAuthorization: String? = "Bearer token",
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.requestHandler = { request in
            if let expectedAuthorization {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expectedAuthorization)
            }
            return try requestHandler(request)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private struct MockMacKeychainReader: MacKeychainReading {
        let data: Data?

        func passwordData(service: String, account: String) -> Data? {
            data
        }
    }

    private static func appDataResourceResponse(resource: String) -> (HTTPURLResponse, Data) {
        let entriesJSON: String
        let updatedAt: String
        let revision: Int

        switch resource {
        case "favorites":
            entriesJSON = """
            [
              {
                "station": \(stationRecordJSON(id: "favorite")),
                "createdAt": "2026-04-30T10:00:00.000Z"
              }
            ]
            """
            updatedAt = "2026-04-30T10:00:00.000Z"
            revision = 5
        case "recents":
            entriesJSON = """
            [
              {
                "station": \(stationRecordJSON(id: "recent")),
                "lastPlayedAt": "2026-04-30T11:00:00.000Z"
              }
            ]
            """
            updatedAt = "2026-04-30T11:00:00.000Z"
            revision = 6
        case "discoveries":
            entriesJSON = """
            [
              {
                "discoveryID": "track-recent",
                "title": "Midnight Signal",
                "artist": "AV Artist",
                "stationID": "recent",
                "stationName": "Station recent",
                "artworkURL": "https://example.com/track.jpg",
                "stationArtworkURL": "https://example.com/station.jpg",
                "playedAt": "2026-04-30T11:30:00.000Z",
                "markedInterestedAt": "2026-04-30T11:31:00.000Z",
                "hiddenAt": null
              }
            ]
            """
            updatedAt = "2026-04-30T11:30:00.000Z"
            revision = 7
        case "settings":
            entriesJSON = """
            [
              {
                "preferredCountry": "ES",
                "preferredLanguage": "",
                "preferredTag": "ambient",
                "lastPlayedStationID": "recent",
                "sleepTimerMinutes": null,
                "updatedAt": "2026-04-30T12:00:00.000Z"
              }
            ]
            """
            updatedAt = "2026-04-30T12:00:00.000Z"
            revision = 8
        default:
            entriesJSON = "[]"
            updatedAt = "2026-04-30T09:00:00.000Z"
            revision = 1
        }

        let body = """
        {
          "data": {
            "appId": "tuneav",
            "resource": "\(resource)",
            "deviceId": "backend",
            "sentAt": "\(updatedAt)",
            "entries": \(entriesJSON)
          },
          "updatedAt": "\(updatedAt)",
          "revision": \(revision),
          "etag": "\\"revision-\(revision)\\""
        }
        """
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/apps/tuneav/data/\(resource)")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer {
            bodyStream.close()
        }

        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        var data = Data()
        while bodyStream.hasBytesAvailable {
            let byteCount = bodyStream.read(buffer, maxLength: bufferSize)
            if byteCount < 0 {
                return nil
            }
            if byteCount == 0 {
                break
            }
            data.append(buffer, count: byteCount)
        }
        return data
    }

    private static let proAccessResponseJSON = """
    {
      "viewer": {
        "isAuthenticated": true,
        "userId": "user_123",
        "identityProvider": "clerk"
      },
      "apps": [
        {
          "appId": "tuneav",
          "accessMode": "signedInPro",
          "planTier": "pro",
          "capabilities": {
            "isSignedIn": true,
            "canUseBackend": true,
            "canUsePremiumFeatures": true,
            "canUseCloudSync": true,
            "canManagePlan": true
          },
          "limits": {
            "favoriteStations": 500,
            "recentStations": 200,
            "discoveredTracks": 1000,
            "savedTracks": 1000,
            "lyricsSearchesPerDay": null,
            "webSearchesPerDay": null,
            "youtubeSearchesPerDay": null,
            "appleMusicSearchesPerDay": null,
            "spotifySearchesPerDay": null,
            "discoverySharesPerDay": null
          }
        }
      ],
      "generatedAt": "2026-05-02T12:00:00.000Z"
    }
    """

    private static let freeAccessResponseJSON = """
    {
      "viewer": {
        "isAuthenticated": true,
        "userId": "user_123",
        "identityProvider": "clerk"
      },
      "apps": [
        {
          "appId": "tuneav",
          "accessMode": "signedInFree",
          "planTier": "free",
          "capabilities": {
            "isSignedIn": true,
            "canUseBackend": true,
            "canUsePremiumFeatures": false,
            "canUseCloudSync": false,
            "canManagePlan": true
          },
          "limits": {
            "favoriteStations": 50,
            "recentStations": 100,
            "discoveredTracks": 200,
            "savedTracks": 20,
            "lyricsSearchesPerDay": 10,
            "webSearchesPerDay": 10,
            "youtubeSearchesPerDay": 10,
            "appleMusicSearchesPerDay": 10,
            "spotifySearchesPerDay": 10,
            "discoverySharesPerDay": 3
          }
        }
      ],
      "generatedAt": "2026-05-02T12:00:00.000Z"
    }
    """

    private static let missingTuneAVAccessResponseJSON = """
    {
      "viewer": {
        "isAuthenticated": true,
        "userId": "user_123",
        "identityProvider": "clerk"
      },
      "apps": [
        {
          "appId": "avclips",
          "accessMode": "signedInPro",
          "planTier": "pro",
          "capabilities": {
            "isSignedIn": true,
            "canUseBackend": true,
            "canUsePremiumFeatures": true,
            "canUseCloudSync": true,
            "canManagePlan": true
          },
          "limits": {
            "favoriteStations": 500,
            "recentStations": 200,
            "discoveredTracks": 1000,
            "savedTracks": 1000,
            "lyricsSearchesPerDay": null,
            "webSearchesPerDay": null,
            "youtubeSearchesPerDay": null,
            "appleMusicSearchesPerDay": null,
            "spotifySearchesPerDay": null,
            "discoverySharesPerDay": null
          }
        }
      ],
      "generatedAt": "2026-05-02T12:00:00.000Z"
    }
    """

    private static func stationRecordJSON(id: String) -> String {
        """
        {
          "id": "\(id)",
          "name": "Station \(id)",
          "country": "Spain",
          "countryCode": "ES",
          "state": null,
          "language": "Spanish",
          "languageCodes": "es",
          "tags": "ambient,radio",
          "streamURL": "https://example.com/\(id).mp3",
          "faviconURL": "https://example.com/\(id).png",
          "bitrate": 128,
          "codec": "MP3",
          "homepageURL": "https://example.com/\(id)",
          "votes": null,
          "clickCount": null,
          "clickTrend": null,
          "isHLS": false,
          "hasExtendedInfo": false,
          "hasSSLError": false,
          "lastCheckOKAt": null,
          "geoLatitude": null,
          "geoLongitude": null
        }
        """
    }

    private func stationRecord(id: String) -> StationRecord {
        StationRecord(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            countryCode: "ES",
            state: nil,
            language: "Spanish",
            languageCodes: "es",
            tags: "ambient,radio",
            streamURL: "https://example.com/\(id).mp3",
            faviconURL: "https://example.com/\(id).png",
            bitrate: 128,
            codec: "MP3",
            homepageURL: "https://example.com/\(id)",
            votes: nil,
            clickCount: nil,
            clickTrend: nil,
            isHLS: false,
            hasExtendedInfo: false,
            hasSSLError: false,
            lastCheckOKAt: nil,
            geoLatitude: nil,
            geoLongitude: nil
        )
    }

    private func station(id: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "ambient,radio",
            streamURL: "https://example.com/\(id).mp3"
        )
    }

    private func queryValue(_ name: String, in url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?.first { $0.name == name }?.value
    }

    private func testSnapshot(settingsUpdatedAt: String = "2026-04-30T12:00:00.000Z") -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: [
                FavoriteStationRecord(
                    station: stationRecord(id: "favorite"),
                    createdAt: "2026-04-30T10:00:00.000Z"
                )
            ],
            recents: [
                RecentStationRecord(
                    station: stationRecord(id: "recent"),
                    lastPlayedAt: "2026-04-30T11:00:00.000Z"
                )
            ],
            discoveries: [
                DiscoveredTrackRecord(
                    discoveryID: "track-recent",
                    title: "Midnight Signal",
                    artist: "AV Artist",
                    stationID: "recent",
                    stationName: "Station recent",
                    artworkURL: "https://example.com/track.jpg",
                    stationArtworkURL: "https://example.com/station.jpg",
                    playedAt: "2026-04-30T11:30:00.000Z",
                    markedInterestedAt: "2026-04-30T11:31:00.000Z",
                    hiddenAt: nil
                )
            ],
            settings: AppSettingsRecord(
                preferredCountry: "ES",
                preferredLanguage: "",
                preferredTag: "ambient",
                lastPlayedStationID: "recent",
                sleepTimerMinutes: nil,
                updatedAt: settingsUpdatedAt
            )
        )
    }
}

private extension CloudSyncStatus {
    var isSynced: Bool {
        if case .synced = self {
            return true
        }
        return false
    }
}

@MainActor
private final class MockMacAccountDeletionAPI: MacAccountDeletionAPI {
    private let summary: MacAccountSummary
    private let requestResponse: MacDeleteAccountRequestResponse
    private let finalizeResponse: MacDeleteAccountFinalizeResponse
    private let unlinkResponse: MacUnlinkAppResponse
    private(set) var didUnlinkCurrentApp = false

    init(
        summary: MacAccountSummary,
        requestResponse: MacDeleteAccountRequestResponse? = nil,
        finalizeResponse: MacDeleteAccountFinalizeResponse? = nil,
        unlinkResponse: MacUnlinkAppResponse
    ) {
        self.summary = summary
        self.requestResponse = requestResponse ?? Self.defaultRequestResponse
        self.finalizeResponse = finalizeResponse ?? Self.defaultFinalizeResponse
        self.unlinkResponse = unlinkResponse
    }

    func fetchAccountSummary() async throws -> MacAccountSummary {
        summary
    }

    func requestAccountDeletion() async throws -> MacDeleteAccountRequestResponse {
        requestResponse
    }

    func finalizeAccountDeletion() async throws -> MacDeleteAccountFinalizeResponse {
        finalizeResponse
    }

    func unlinkCurrentApp() async throws -> MacUnlinkAppResponse {
        didUnlinkCurrentApp = true
        return unlinkResponse
    }

    private static var defaultRequestResponse: MacDeleteAccountRequestResponse {
        try! JSONDecoder().decode(MacDeleteAccountRequestResponse.self, from: Data(#"{"status":"accepted"}"#.utf8))
    }

    private static var defaultFinalizeResponse: MacDeleteAccountFinalizeResponse {
        try! JSONDecoder().decode(MacDeleteAccountFinalizeResponse.self, from: Data(#"{"status":"completed"}"#.utf8))
    }
}

@MainActor
private final class BlockingMacLibrarySyncClient: MacTuneAVLibrarySyncing {
    private let remoteDocument: TuneAVLibraryDocument
    private var pullContinuation: CheckedContinuation<TuneAVLibraryDocument, Never>?
    private(set) var pullCount = 0

    init(remoteDocument: TuneAVLibraryDocument) {
        self.remoteDocument = remoteDocument
    }

    func isConfigured() -> Bool {
        true
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        pullCount += 1
        return await withCheckedContinuation { continuation in
            pullContinuation = continuation
        }
    }

    func resumePull() {
        pullContinuation?.resume(returning: remoteDocument)
        pullContinuation = nil
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {}

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {}
}

@MainActor
private final class MockMacLibrarySyncClient: MacTuneAVLibrarySyncing {
    var pullCount = 0
    var pushCount = 0
    var overwriteCount = 0
    var pushedSnapshots: [TuneAVLibrarySnapshot] = []

    private let configured: Bool
    private let remoteDocument: TuneAVLibraryDocument
    private let pullError: Error?
    private let pushError: Error?

    init(
        configured: Bool = true,
        remoteDocument: TuneAVLibraryDocument,
        pullError: Error? = nil,
        pushError: Error? = nil
    ) {
        self.configured = configured
        self.remoteDocument = remoteDocument
        self.pullError = pullError
        self.pushError = pushError
    }

    func isConfigured() -> Bool {
        configured
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        pullCount += 1
        if let pullError {
            throw pullError
        }
        return remoteDocument
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        pushCount += 1
        if let pushError {
            throw pushError
        }
        pushedSnapshots.append(snapshot)
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        overwriteCount += 1
        if let pushError {
            throw pushError
        }
        pushedSnapshots.append(snapshot)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class MockAccountAVService: AccountAVService {
    let isAvailable: Bool
    private(set) var currentUser: AccountAVUser?

    init(isAvailable: Bool, currentUser: AccountAVUser? = nil) {
        self.isAvailable = isAvailable
        self.currentUser = currentUser
    }

    func getToken() async throws -> String? {
        currentUser == nil ? nil : "token"
    }

    func signInWithApple() async throws {
        currentUser = AccountAVUser(id: "apple", displayName: "Apple User", emailAddress: "apple@example.com")
    }

    func signInWithGoogle() async throws {
        currentUser = AccountAVUser(id: "google", displayName: "Google User", emailAddress: "google@example.com")
    }

    func signOut() async throws {
        currentUser = nil
    }
}
