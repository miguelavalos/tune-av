import XCTest
@testable import TuneAV

final class SharedAppleSupportTests: XCTestCase {
    func testUITestAccountDeletionScenariosResolveSharedBlockedProSummary() {
        let summary = TuneAVUITestAccountDeletionScenarios.summary(for: "blocked_pro")

        XCTAssertEqual(summary.id, "ui-test-user")
        XCTAssertEqual(summary.access.first?.appId, "tuneav")
        XCTAssertEqual(summary.access.first?.accessMode, .signedInPro)
        XCTAssertEqual(summary.deleteAccountEligibility?.status, .blocked)
        XCTAssertEqual(summary.deleteAccountEligibility?.blockers.first?.type, .activeProAccess)
    }

    func testAccountDeletionPolicyPrefersBackendEligibilityOverConservativeFallback() {
        let backendEligibility = AccountDeletionEligibility(status: .eligible, blockers: [], currentJob: nil)
        let summary = AccountSummary(
            linkedApps: [
                LinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                LinkedAccountApp(appId: "other", label: "Other")
            ],
            deleteAccountEligibility: backendEligibility
        )

        XCTAssertEqual(
            TuneAVAccountDeletionPolicy.resolvedEligibility(from: summary, copy: accountDeletionCopy),
            backendEligibility
        )
    }

    func testAccountDeletionPolicyFallsBackToConservativeEligibilityWhenBackendOmitsIt() {
        let summary = AccountSummary(
            linkedApps: [
                LinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                LinkedAccountApp(appId: "other", label: "Other")
            ]
        )

        let eligibility = TuneAVAccountDeletionPolicy.resolvedEligibility(from: summary, copy: accountDeletionCopy)

        XCTAssertEqual(eligibility.status, .unavailable)
        XCTAssertEqual(eligibility.blockers.first?.type, .linkedApp)
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
            FeatureLimitState(feature: .youtubeSearch, currentUsage: 3, limit: 3)
        )

        XCTAssertEqual(content.feature, .youtubeSearch)
        XCTAssertEqual(content.title, L10n.string("limits.upgrade.youtube.title"))
        XCTAssertEqual(content.message, L10n.string("limits.upgrade.youtube.message", 3))
    }

    func testUpgradePromptContextUsesSharedLimitCopyAndProgress() {
        let favorites = TuneAVUpgradePromptContext.favorites(current: 5, limit: 5)
        XCTAssertEqual(favorites.title, L10n.string("limits.upgrade.favoriteStations.title"))
        XCTAssertEqual(favorites.message, L10n.string("limits.upgrade.favoriteStations.message", 5))
        XCTAssertEqual(favorites.benefit, L10n.string("limits.upgrade.default.message"))
        XCTAssertEqual(favorites.progressText, L10n.string("mac.limits.progress.favorites", 5, 5))

        let daily = TuneAVUpgradePromptContext.dailyFeature(.youtubeSearch, current: 3, limit: 3)
        XCTAssertEqual(daily.title, L10n.string("mac.limits.daily.title", TuneAVUpgradePromptContent.featureName(for: .youtubeSearch)))
        XCTAssertEqual(daily.progressText, L10n.string("mac.limits.progress.today", 3, 3))
    }

    @MainActor
    func testSleepTimerControllerSetsAndClearsSharedDescription() {
        let controller = TuneAVSleepTimerController()
        var description: String?
        var didFire = false

        controller.setTimer(
            minutes: 5,
            setDescription: { description = $0 },
            onFire: { didFire = true }
        )

        XCTAssertEqual(description, L10n.string("audio.sleep.inMinutes", 5))
        XCTAssertFalse(didFire)

        controller.clearNoticeIfIdle(isIdle: false, setDescription: { description = $0 })
        XCTAssertEqual(description, L10n.string("audio.sleep.inMinutes", 5))

        controller.clearNoticeIfIdle(isIdle: true, setDescription: { description = $0 })
        XCTAssertNil(description)

        controller.setTimer(minutes: nil, setDescription: { description = $0 }, onFire: { didFire = true })
        XCTAssertNil(description)
        XCTAssertFalse(didFire)
    }

    func testTrackMetadataParserSplitsArtistAndTitleWithCommonSeparators() {
        let hyphen = TuneAVTrackMetadataParser.parse("Massive Attack - Teardrop")
        let enDash = TuneAVTrackMetadataParser.parse("Rosalia – Malamente")
        let emDash = TuneAVTrackMetadataParser.parse("Daft Punk — Digital Love")

        XCTAssertEqual(hyphen.artist, "Massive Attack")
        XCTAssertEqual(hyphen.title, "Teardrop")
        XCTAssertEqual(enDash.artist, "Rosalia")
        XCTAssertEqual(enDash.title, "Malamente")
        XCTAssertEqual(emDash.artist, "Daft Punk")
        XCTAssertEqual(emDash.title, "Digital Love")
    }

    func testTrackMetadataParserRejectsBlockedAndLargeNumericMetadata() {
        XCTAssertNil(TuneAVTrackMetadataParser.sanitizeTitle("unknown", artist: nil))
        XCTAssertNil(TuneAVTrackMetadataParser.sanitizeArtist("--"))
        XCTAssertNil(TuneAVTrackMetadataParser.sanitizeTitle("123456", artist: "Artist"))
        XCTAssertNil(TuneAVTrackMetadataParser.sanitizeTitle("1234", artist: nil))
        XCTAssertEqual(TuneAVTrackMetadataParser.sanitizeTitle("1234", artist: "Artist"), "1234")
    }

    func testTrackMetadataParserCleansStreamTitleWrapper() {
        let parsed = TuneAVTrackMetadataParser.parse("StreamTitle='Air - La femme d'argent';")

        XCTAssertEqual(parsed.artist, "Air")
        XCTAssertEqual(parsed.title, "La femme d'argent")
    }

    func testTrackMetadataParserIdentifiesStationNamesAsNotSongs() {
        XCTAssertTrue(TuneAVTrackMetadataParser.titleLooksLikeStationName("Rock FM", stationName: "ROCK FM"))
        XCTAssertTrue(TuneAVTrackMetadataParser.titleLooksLikeStationName("Los 40 Classic", stationName: "LOS40 Classic"))
        XCTAssertTrue(TuneAVTrackMetadataParser.titleLooksLikeStationName("Classic Rock", stationName: "RADIO BOB! Classic Rock"))
        XCTAssertTrue(TuneAVTrackMetadataParser.titleLooksLikeStationName("Dance Hits", stationName: "Capital Dance Hits UK"))
        XCTAssertTrue(TuneAVTrackMetadataParser.titleLooksLikeStationName("Alternative", stationName: "KEXP Alternative"))
        XCTAssertFalse(TuneAVTrackMetadataParser.titleLooksLikeStationName("Riot!", stationName: "ROCK FM"))
        XCTAssertFalse(TuneAVTrackMetadataParser.titleLooksLikeStationName("Coffee & TV", stationName: "ROCK FM"))
        XCTAssertFalse(TuneAVTrackMetadataParser.titleLooksLikeStationName("One", stationName: "BBC Radio One"))
    }

    func testTrackMetadataParserIdentifiesBroadcastPlaceholdersAsNotSongs() {
        XCTAssertTrue(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("LIVE", stationName: "KEXP"))
        XCTAssertTrue(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("On Air", stationName: "Radio Nova"))
        XCTAssertTrue(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("Radio Online", stationName: "Radio Nova"))
        XCTAssertTrue(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("En Directo", stationName: "Los 40 Classic"))
        XCTAssertTrue(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("Now Playing", stationName: "KEXP"))
        XCTAssertFalse(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("Live Forever", stationName: "Rock FM"))
        XCTAssertFalse(TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata("Radio Song", stationName: "Rock FM"))
    }

    func testDisplayMetadataNormalizesAndRejectsBroadcastPlaceholders() {
        XCTAssertEqual(TuneAVDisplayMetadata.normalized("  Teardrop  "), "Teardrop")
        XCTAssertEqual(TuneAVDisplayMetadata.plausibleTitle("Teardrop", stationName: "Radio Nova"), "Teardrop")
        XCTAssertNil(TuneAVDisplayMetadata.plausibleTitle("Now Playing", stationName: "Radio Nova"))
        XCTAssertEqual(TuneAVDisplayMetadata.plausibleArtist("Massive Attack", stationName: "Radio Nova"), "Massive Attack")
        XCTAssertNil(TuneAVDisplayMetadata.plausibleArtist("Radio Nova", stationName: "Radio Nova"))
    }

    func testStationDisplayLinesResolveSharedCurrentCachedAndFallbackMetadata() {
        let station = Station(
            id: "nova",
            name: "Radio Nova",
            country: "France",
            language: "French",
            tags: "jazz, eclectic",
            streamURL: "https://example.com/nova"
        )

        let current = TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: true,
            currentArtist: "  Massive Attack  ",
            currentTitle: " Teardrop ",
            currentAlbumTitle: "Mezzanine",
            nowPlayingTrack: TuneAVNowPlayingTrack(title: "Cached title", artist: "Cached artist"),
            detailText: "France",
            liveFallback: "Live"
        )
        XCTAssertEqual(current.artistLine, "Massive Attack")
        XCTAssertEqual(current.titleLine, "Teardrop")

        let cached = TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: false,
            currentArtist: "Ignored artist",
            currentTitle: "Ignored title",
            currentAlbumTitle: "Ignored album",
            nowPlayingTrack: TuneAVNowPlayingTrack(title: "Cached title", artist: "Cached artist"),
            detailText: "France",
            liveFallback: "Live"
        )
        XCTAssertEqual(cached.artistLine, "Cached artist")
        XCTAssertEqual(cached.titleLine, "Cached title")

        let fallback = TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: false,
            currentArtist: nil,
            currentTitle: nil,
            currentAlbumTitle: nil,
            nowPlayingTrack: nil,
            detailText: "France",
            liveFallback: "Live"
        )
        XCTAssertEqual(fallback.artistLine, "France")
        XCTAssertEqual(fallback.titleLine, "jazz")
    }

    func testStationCardDetailIgnoresSharedUnknownLocalizedValues() {
        let station = Station(
            id: "unknown",
            name: "Unknown Detail Radio",
            country: "Unknown country",
            state: "País desconocido",
            language: "Unknown language",
            tags: "radio",
            streamURL: "https://example.com/unknown"
        )

        XCTAssertNil(
            station.cardDetailText(
                preferCountryName: true,
                unknownValues: Station.unknownDetailValues,
                locale: L10n.locale
            )
        )
    }

    func testStationDecodesAVALSYSEnrichmentFields() throws {
        let json = #"""
        {
          "id": "692a3b69-0f68-11ea-a87e-52543be04c81",
          "name": "Cadena SER España",
          "country": "Spain",
          "countryCode": "ES",
          "state": null,
          "language": "Spanish",
          "languageCodes": "es",
          "tags": "news,talk,sports",
          "streamURL": "https://example.com/ser.mp3",
          "faviconURL": null,
          "bitrate": 128,
          "codec": "MP3",
          "homepageURL": "https://cadenaser.com/",
          "votes": 10,
          "clickCount": 20,
          "clickTrend": 1,
          "isHLS": false,
          "hasExtendedInfo": false,
          "hasSSLError": false,
          "lastCheckOKAt": "2026-05-09T10:00:00Z",
          "geoLatitude": 40.4168,
          "geoLongitude": -3.7038,
          "canonicalStationId": "st_rb_692a3b69_0f68_11ea_a87e_52543be04c81",
          "category": "news",
          "visibility": "public",
          "qualityScore": 84,
          "enrichmentStatus": "enriched",
          "artwork": {
            "status": "none",
            "url": null,
            "version": null
          },
          "editorial": {
            "summary": "Spanish-language news and talk radio from Spain.",
            "primaryFormat": "newsTalk",
            "secondaryFormats": ["sports", "culture"],
            "musicIntensity": "low",
            "speechIntensity": "high",
            "languages": ["Spanish"],
            "audience": ["Spain"],
            "programming": ["current affairs", "sports"],
            "sourceUrls": ["https://cadenaser.com/"],
            "discoveryProfile": {
              "musicDiscoveryScore": 18,
              "musicLevel": "low",
              "speechLevel": "high",
              "newsLevel": "high",
              "sportsLevel": "high",
              "adLoad": "unknown",
              "metadataQuality": "fair",
              "attentionMode": "active",
              "bestFor": ["Spanish current affairs", "sports coverage"],
              "notIdealFor": ["discovering songs", "continuous music"],
              "genres": [],
              "moods": ["informative", "conversational"],
              "reasons": [
                "Spoken programming is the main listening experience.",
                "Music appears secondary to news, interviews, and sports."
              ]
            },
            "confidence": "medium",
            "reviewStatus": "seeded",
            "updatedAt": "2026-05-09T10:00:00Z"
          }
        }
        """#.data(using: .utf8)!

        let station = try JSONDecoder().decode(Station.self, from: json)

        XCTAssertEqual(station.id, "692a3b69-0f68-11ea-a87e-52543be04c81")
        XCTAssertEqual(station.canonicalStationId, "st_rb_692a3b69_0f68_11ea_a87e_52543be04c81")
        XCTAssertEqual(station.category, "news")
        XCTAssertEqual(station.qualityScore, 84)
        XCTAssertEqual(station.artwork?.status, "none")
        XCTAssertEqual(station.editorial?.primaryFormat, "newsTalk")
        XCTAssertEqual(station.editorial?.programming, ["current affairs", "sports"])
        XCTAssertEqual(station.editorial?.discoveryProfile?.musicDiscoveryScore, 18)
        XCTAssertEqual(station.editorial?.discoveryProfile?.notIdealFor, ["discovering songs", "continuous music"])
    }

    func testStationServiceUsesAVALSYSResponse() async throws {
        TuneAVTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "api.test")
            XCTAssertEqual(self.queryValue("q", in: request.url), "Cadena SER")
            XCTAssertEqual(self.queryValue("countryCode", in: request.url), "ES")
            XCTAssertNil(self.queryValue("locale", in: request.url))

            let body = #"""
            {
              "stations": [
                {
                  "id": "ser",
                  "name": "Cadena SER España",
                  "country": "Spain",
                  "countryCode": "ES",
                  "state": null,
                  "language": "Spanish",
                  "languageCodes": "es",
                  "tags": "news,talk",
                  "streamURL": "https://example.com/ser.mp3",
                  "faviconURL": null,
                  "bitrate": 128,
                  "codec": "MP3",
                  "homepageURL": "https://cadenaser.com/",
                  "votes": 10,
                  "clickCount": 20,
                  "clickTrend": 1,
                  "isHLS": false,
                  "hasExtendedInfo": false,
                  "hasSSLError": false,
                  "lastCheckOKAt": null,
                  "geoLatitude": null,
                  "geoLongitude": null,
                  "canonicalStationId": "st_rb_ser",
                  "category": "news",
                  "visibility": "public",
                  "qualityScore": 84,
                  "enrichmentStatus": "enriched",
                  "artwork": { "status": "none", "url": null, "version": null },
                  "editorial": {
                    "summary": "Spanish-language news and talk radio from Spain.",
                    "primaryFormat": "newsTalk",
                    "secondaryFormats": [],
                    "musicIntensity": "low",
                    "speechIntensity": "high",
                    "languages": ["Spanish"],
                    "audience": ["Spain"],
                    "programming": ["current affairs"],
                    "sourceUrls": ["https://cadenaser.com/"],
                    "discoveryProfile": {
                      "musicDiscoveryScore": 18,
                      "musicLevel": "low",
                      "speechLevel": "high",
                      "newsLevel": "high",
                      "sportsLevel": "high",
                      "adLoad": "unknown",
                      "metadataQuality": "fair",
                      "attentionMode": "active",
                      "bestFor": ["Spanish current affairs", "sports coverage"],
                      "notIdealFor": ["discovering songs", "continuous music"],
                      "genres": [],
                      "moods": ["informative", "conversational"],
                      "reasons": ["Spoken programming is the main listening experience."]
                    },
                    "confidence": "medium",
                    "reviewStatus": "seeded",
                    "updatedAt": "2026-05-09T10:00:00Z"
                  }
                }
              ],
              "provider": "radioBrowser",
              "generatedAt": "2026-05-09T10:00:00Z"
            }
            """#.data(using: .utf8)!

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let service = TuneAVStationService(
            session: testURLSession(),
            avalsysBaseURL: URL(string: "https://api.test/v1/tune/stations/search")!
        )

        let stations = try await service.searchStations(
            filters: TuneAVStationSearchFilters(query: "Cadena SER", countryCode: "ES", limit: 5)
        )

        XCTAssertEqual(stations.map(\.id), ["ser"])
        XCTAssertEqual(stations.first?.editorial?.summary, "Spanish-language news and talk radio from Spain.")
        XCTAssertEqual(stations.first?.editorial?.discoveryProfile?.musicDiscoveryScore, 18)
    }

    func testStationServiceDecodesAVALSYSLanguageCodesArray() async throws {
        TuneAVTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "api.test")

            let body = #"""
            {
              "stations": [
                {
                  "id": "ser",
                  "name": "Cadena SER España",
                  "country": "Spain",
                  "countryCode": "ES",
                  "state": null,
                  "language": "Spanish",
                  "languageCodes": ["es"],
                  "tags": "news,talk",
                  "streamURL": "https://example.com/ser.mp3",
                  "faviconURL": null,
                  "bitrate": 128,
                  "codec": "MP3",
                  "homepageURL": "https://cadenaser.com/",
                  "votes": 10,
                  "clickCount": 20,
                  "clickTrend": 1,
                  "isHLS": false,
                  "hasExtendedInfo": false,
                  "hasSSLError": false,
                  "lastCheckOKAt": null,
                  "geoLatitude": null,
                  "geoLongitude": null,
                  "canonicalStationId": "st_rb_ser",
                  "category": "news",
                  "visibility": "public",
                  "qualityScore": 84,
                  "enrichmentStatus": "enriched",
                  "artwork": { "status": "none", "url": null, "version": null },
                  "editorial": {
                    "summary": "Radio española de noticias y conversación.",
                    "primaryFormat": "newsTalk",
                    "secondaryFormats": [],
                    "musicIntensity": "low",
                    "speechIntensity": "high",
                    "languages": ["Español"],
                    "audience": ["España"],
                    "programming": ["noticias"],
                    "sourceUrls": ["https://cadenaser.com/"],
                    "discoveryProfile": {
                      "musicDiscoveryScore": 18,
                      "musicLevel": "low",
                      "speechLevel": "high",
                      "newsLevel": "high",
                      "sportsLevel": "high",
                      "adLoad": "unknown",
                      "metadataQuality": "fair",
                      "attentionMode": "active",
                      "bestFor": ["actualidad española", "deportes"],
                      "notIdealFor": ["descubrir canciones", "música continua"],
                      "genres": [],
                      "moods": ["informativa", "conversacional"],
                      "reasons": ["Predomina la voz sobre la música."]
                    },
                    "confidence": "medium",
                    "reviewStatus": "seeded",
                    "updatedAt": "2026-05-09T10:00:00Z"
                  }
                }
              ],
              "provider": "radioBrowser",
              "generatedAt": "2026-05-09T10:00:00Z"
            }
            """#.data(using: .utf8)!

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let service = TuneAVStationService(
            session: testURLSession(),
            avalsysBaseURL: URL(string: "https://api.test/v1/tune/stations/search")!
        )

        let stations = try await service.searchStations(
            filters: TuneAVStationSearchFilters(query: "Cadena SER", limit: 5)
        )

        XCTAssertEqual(stations.first?.languageCodes, "es")
        XCTAssertEqual(stations.first?.editorial?.summary, "Radio española de noticias y conversación.")
        XCTAssertEqual(stations.first?.editorial?.discoveryProfile?.notIdealFor, ["descubrir canciones", "música continua"])
    }

    func testStationServiceSendsLocaleToAVALSYS() async throws {
        TuneAVTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(self.queryValue("locale", in: request.url), "es")

            let body = #"""
            {
              "stations": [],
              "provider": "radioBrowser",
              "generatedAt": "2026-05-09T10:00:00Z"
            }
            """#.data(using: .utf8)!

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let service = TuneAVStationService(
            session: testURLSession(),
            avalsysBaseURL: URL(string: "https://api.test/v1/tune/stations/search")!
        )

        _ = try await service.searchStations(
            filters: TuneAVStationSearchFilters(query: "Cadena SER", locale: "es", limit: 5)
        )
    }

    func testStationServiceUsesPopularEndpointBeforeSearchFallback() async throws {
        TuneAVTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/tune/stations/popular")
            XCTAssertNil(self.queryValue("q", in: request.url))
            XCTAssertEqual(self.queryValue("countryCode", in: request.url), "ES")
            XCTAssertEqual(self.queryValue("locale", in: request.url), "es")

            let body = #"""
            {
              "stations": [
                {
                  "id": "popular-ser",
                  "name": "Popular SER",
                  "country": "Spain",
                  "countryCode": "ES",
                  "state": null,
                  "language": "Spanish",
                  "languageCodes": ["es"],
                  "tags": "news,talk",
                  "streamURL": "https://example.com/popular-ser.mp3",
                  "faviconURL": null,
                  "bitrate": 128,
                  "codec": "MP3",
                  "homepageURL": null,
                  "votes": 10,
                  "clickCount": 20,
                  "clickTrend": 1,
                  "isHLS": false,
                  "hasExtendedInfo": false,
                  "hasSSLError": false,
                  "lastCheckOKAt": null,
                  "geoLatitude": null,
                  "geoLongitude": null,
                  "canonicalStationId": "st_rb_popular_ser",
                  "category": "news",
                  "visibility": "public",
                  "qualityScore": 84,
                  "enrichmentStatus": "enriched",
                  "artwork": { "status": "none", "url": null, "version": null }
                }
              ],
              "provider": "radioBrowser",
              "generatedAt": "2026-05-09T10:00:00Z"
            }
            """#.data(using: .utf8)!

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let service = TuneAVStationService(
            session: testURLSession(),
            avalsysBaseURL: URL(string: "https://api.test/v1/tune/stations/search")!,
            avalsysPopularBaseURL: URL(string: "https://api.test/v1/tune/stations/popular")!
        )

        let stations = try await service.popularStations(
            filters: TuneAVStationSearchFilters(query: "ignored", countryCode: "ES", locale: "es", limit: 12)
        )

        XCTAssertEqual(stations.map(\.id), ["popular-ser"])
    }

    func testStationServiceFallsBackToRadioBrowserWhenAVALSYSFails() async throws {
        var requestedHosts: [String] = []
        TuneAVTestURLProtocol.requestHandler = { request in
            requestedHosts.append(request.url?.host ?? "")

            if request.url?.host == "api.test" {
                return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
            }

            let body = #"""
            [
              {
                "stationuuid": "fallback",
                "name": "Fallback Radio",
                "country": "Spain",
                "countrycode": "ES",
                "state": "",
                "language": "Spanish",
                "languagecodes": "es",
                "tags": "news",
                "url": "https://example.com/fallback.mp3",
                "url_resolved": "https://example.com/fallback.mp3",
                "favicon": "",
                "bitrate": 128,
                "codec": "MP3",
                "homepage": "https://example.com/",
                "votes": 1,
                "clickcount": 2,
                "clicktrend": 0,
                "hls": 0,
                "has_extended_info": false,
                "ssl_error": 0,
                "lastcheckoktime_iso8601": null,
                "geo_lat": null,
                "geo_long": null,
                "lastcheckok": 1
              }
            ]
            """#.data(using: .utf8)!

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let service = TuneAVStationService(
            session: testURLSession(),
            avalsysBaseURL: URL(string: "https://api.test/v1/tune/stations/search")!,
            radioBrowserBaseURL: URL(string: "https://radio.test/json/stations/search")!
        )

        let stations = try await service.searchStations(
            filters: TuneAVStationSearchFilters(query: "Fallback", countryCode: "ES", limit: 5)
        )

        XCTAssertEqual(requestedHosts, ["api.test", "radio.test"])
        XCTAssertEqual(stations.map(\.id), ["fallback"])
        XCTAssertNil(stations.first?.editorial)
    }

    func testNowPlayingDisplayLinesPreferAlbumFallbackBeforeStationTags() {
        let station = Station(
            id: "album-fallback",
            name: "Album Fallback Radio",
            country: "United States",
            language: "English",
            tags: "jazz, live",
            streamURL: "https://example.com/album"
        )

        let display = TuneAVNowPlayingDisplayLines.resolve(
            station: station,
            currentTitle: "Now Playing",
            currentArtist: "Live Stream",
            currentAlbumTitle: "Blue Note Sessions",
            liveNowFallback: "Live now",
            liveStreamFallback: "Live stream"
        )

        XCTAssertEqual(display.stationMetaLine, station.shortMeta)
        XCTAssertEqual(display.trackTitleLine, station.name)
        XCTAssertEqual(display.trackSupportingLine, "Blue Note Sessions")
        XCTAssertFalse(display.hasDiscoverableTrack)
    }

    func testCurrentDiscoveryResolvesSearchAndLocalizedShareText() throws {
        let station = Station(
            id: "nova",
            name: "Radio Nova",
            country: "France",
            language: "French",
            tags: "radio",
            streamURL: "https://example.com/nova"
        )

        let discovery = try XCTUnwrap(
            TuneAVCurrentDiscovery.resolve(
                title: " Teardrop ",
                artist: " Massive Attack ",
                station: station
            )
        )

        XCTAssertEqual(discovery.title, "Teardrop")
        XCTAssertEqual(discovery.artist, "Massive Attack")
        XCTAssertEqual(discovery.searchQuery, "Massive Attack Teardrop")
        XCTAssertEqual(
            discovery.localizedShareText,
            L10n.string("player.discovery.shareText", "Teardrop", "Massive Attack", "Radio Nova")
        )
        XCTAssertNil(TuneAVCurrentDiscovery.resolve(title: "Now Playing", artist: "Live Stream", station: station))
    }

    func testDiscoveredTrackSupportBuildsSharedDisplayAndSearchValues() {
        XCTAssertEqual(
            TuneAVDiscoveredTrackSupport.artistDisplayText(" Massive Attack ", liveFallback: "Live now"),
            "Massive Attack"
        )
        XCTAssertEqual(
            TuneAVDiscoveredTrackSupport.artistDisplayText("  ", liveFallback: "Live now"),
            "Live now"
        )
        XCTAssertEqual(
            TuneAVDiscoveredTrackSupport.searchQuery(title: "Teardrop", artist: " Massive Attack "),
            "Massive Attack Teardrop"
        )
        XCTAssertEqual(
            TuneAVDiscoveredTrackSupport.searchQuery(title: "Teardrop", artist: nil),
            "Teardrop"
        )
    }

    func testTrackMetadataParserIdentifiesStationLikeArtistsAsNotArtists() {
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("ROCK FM", stationName: "Rock FM"))
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Radio Nova", stationName: "Radio Nova"))
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Live Stream", stationName: "KEXP"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Radiohead", stationName: "KEXP"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("R.E.M.", stationName: "Rock FM"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Linkin Park", stationName: "Linkin Park"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Five Finger Death Punch", stationName: "Five Finger Death Punch"))
    }

    func testNowPlayingMetadataParsesICYStreamTitle() {
        let bytes = Array("StreamTitle='Massive Attack - Teardrop';\0\0".utf8)
        let track = TuneAVNowPlayingMetadata.parseICYMetadata(bytes)

        XCTAssertEqual(track?.artist, "Massive Attack")
        XCTAssertEqual(track?.title, "Teardrop")
    }

    func testNowPlayingMetadataReadsCaseInsensitiveIntervalHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/stream")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Icy-MetaInt": "16000"]
        )

        XCTAssertEqual(TuneAVNowPlayingMetadata.metadataInterval(from: response!), 16000)
    }

    func testAlternateMetadataStreamResolverPrefersDirectEquivalentStream() {
        let station = Station(
            id: "station-hls",
            name: "Example Radio",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example-radio.test/live/chunks.m3u8",
            homepageURL: "https://www.example-radio.test/",
            isHLS: true
        )
        let candidates = [
            RadioBrowserMetadataCandidate(
                name: "Example Radio",
                url: "https://example-radio.test/live/chunks.m3u8",
                url_resolved: "https://example-radio.test/live/chunks.m3u8",
                homepage: "https://www.example-radio.test/",
                codec: "UNKNOWN",
                hls: 1,
                lastcheckok: 1
            ),
            RadioBrowserMetadataCandidate(
                name: "Example Radio",
                url: "http://stream.example-radio.test/live.mp3",
                url_resolved: "http://stream.example-radio.test/live.mp3",
                homepage: "https://example-radio.test/",
                codec: "MP3",
                hls: 0,
                lastcheckok: 1
            )
        ]

        XCTAssertEqual(
            TuneAVAlternateMetadataStreamResolver.bestAlternateStreamURL(for: station, candidates: candidates)?.absoluteString,
            "http://stream.example-radio.test/live.mp3"
        )
    }

    func testAlternateMetadataStreamResolverRejectsUnrelatedDirectStream() {
        let station = Station(
            id: "station-hls",
            name: "Example Radio",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example-radio.test/live/chunks.m3u8",
            homepageURL: "https://www.example-radio.test/",
            isHLS: true
        )
        let candidates = [
            RadioBrowserMetadataCandidate(
                name: "Other Radio",
                url: "http://stream.other-radio.test/live.mp3",
                url_resolved: "http://stream.other-radio.test/live.mp3",
                homepage: "https://other-radio.test/",
                codec: "MP3",
                hls: 0,
                lastcheckok: 1
            )
        ]

        XCTAssertNil(TuneAVAlternateMetadataStreamResolver.bestAlternateStreamURL(for: station, candidates: candidates))
    }

    func testEighties80sNowPlayingMatchesStationByHomepageSlug() {
        let station = Station(
            id: "80s80s-dm",
            name: "80s80s Depeche Mode",
            country: "Germany",
            countryCode: "DE",
            language: "German",
            tags: "80s",
            streamURL: "https://streams.80s80s.de/dm/mp3-192",
            faviconURL: nil,
            homepageURL: "https://www.80s80s.de/dm"
        )
        let html = #"""
        stream:"LIVE"
        song_title:"A-ha - Take On Me"
        artist_name:"A-ha"
        stream:"DM"
        song_title:"Enjoy the Silence"
        artist_name:"Depeche Mode"
        """#

        let track = TuneAVEighties80sNowPlaying.parseTrack(for: station, from: html)

        XCTAssertTrue(TuneAVEighties80sNowPlaying.supports(station))
        XCTAssertEqual(TuneAVEighties80sNowPlaying.resolvedURL(for: station)?.host, "www.80s80s.de")
        XCTAssertEqual(track?.title, "Enjoy the Silence")
        XCTAssertEqual(track?.artist, "Depeche Mode")
    }

    func testExternalSearchURLsUseExpectedHostsAndQueryItems() {
        let google = TuneAVExternalSearchURL.web(query: "Boards of Canada Dayvan Cowboy", youtube: false)
        let youtube = TuneAVExternalSearchURL.web(query: "Boards of Canada Dayvan Cowboy", youtube: true)
        let appleMusic = TuneAVExternalSearchURL.appleMusic(query: "Nina Simone Feeling Good")

        XCTAssertEqual(google?.host, "www.google.com")
        XCTAssertEqual(google?.path, "/search")
        XCTAssertEqual(queryValue("q", in: google), "Boards of Canada Dayvan Cowboy")

        XCTAssertEqual(youtube?.host, "www.youtube.com")
        XCTAssertEqual(youtube?.path, "/results")
        XCTAssertEqual(queryValue("search_query", in: youtube), "Boards of Canada Dayvan Cowboy")

        XCTAssertEqual(appleMusic?.host, "music.apple.com")
        XCTAssertEqual(appleMusic?.path, "/search")
        XCTAssertEqual(queryValue("term", in: appleMusic), "Nina Simone Feeling Good")
    }

    func testExternalSearchStationSearchUsesGoogleRadioQuery() {
        let url = TuneAVExternalSearchURL.stationSearch(stationName: "  Radio Nova  ")

        XCTAssertEqual(url?.host, "www.google.com")
        XCTAssertEqual(url?.path, "/search")
        XCTAssertEqual(queryValue("q", in: url), "Radio Nova radio")
    }

    func testExternalSearchQueryNormalizesPartsAndSuffix() {
        let query = TuneAVExternalSearchURL.query(
            parts: ["  artist  ", nil, "", " title "],
            suffix: " lyrics "
        )

        XCTAssertEqual(query, "artist title lyrics")
    }

    func testExternalSearchFeatureRequestsResolveURLAndLimitFeature() {
        let lyrics = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Boards of Canada Dayvan Cowboy",
            suffix: "lyrics",
            youtube: false
        )
        let youtube = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: "Boards of Canada Dayvan Cowboy",
            suffix: nil,
            youtube: true
        )
        let spotify = TuneAVExternalSearchURL.artistSearch(
            artist: "Nina Simone",
            destination: .spotify,
            feature: .spotifySearch
        )

        XCTAssertEqual(lyrics?.feature, .lyricsSearch)
        XCTAssertEqual(queryValue("q", in: lyrics?.url), "Boards of Canada Dayvan Cowboy lyrics")
        XCTAssertEqual(youtube?.feature, .youtubeSearch)
        XCTAssertEqual(queryValue("search_query", in: youtube?.url), "Boards of Canada Dayvan Cowboy")
        XCTAssertEqual(spotify?.feature, .spotifySearch)
        XCTAssertEqual(spotify?.url.host, "open.spotify.com")
    }

    func testTextNormalizesValuesAndBuildsJoinedQueries() {
        XCTAssertEqual(TuneAVText.normalizedValue("  Radio Nova  "), "Radio Nova")
        XCTAssertNil(TuneAVText.normalizedValue("   "))
        XCTAssertEqual(
            TuneAVText.joinedQuery(parts: ["  artist  ", nil, " title "], suffix: " live "),
            "artist title live"
        )
    }

    func testCountrySanitizesCodesAndBuildsFlags() {
        XCTAssertEqual(TuneAVCountry.sanitizedCode(" es "), "ES")
        XCTAssertNil(TuneAVCountry.sanitizedCode("EU"))
        XCTAssertNil(TuneAVCountry.sanitizedCode("1A"))

        XCTAssertEqual(TuneAVCountry(code: "ES", name: "Spain").flag, "🇪🇸")
    }

    func testCountryBuildsSortedOptionsAndFiltersByNameOrCode() {
        let countries = [
            TuneAVCountry(code: "ES", name: "Spain"),
            TuneAVCountry(code: "FR", name: "France"),
            TuneAVCountry(code: "US", name: "United States")
        ]

        XCTAssertEqual(
            TuneAVCountry.filtered(countries, query: " fr ").map(\.code),
            ["FR"]
        )
        XCTAssertEqual(
            TuneAVCountry.filtered(countries, query: "states").map(\.code),
            ["US"]
        )
        XCTAssertFalse(TuneAVCountry.all(localizedName: { $0 }).contains { $0.code == "EU" })
    }

    func testHomeFeedMergesStationsAndBuildsEditorialFallback() {
        let first = Station(
            id: "first",
            name: "First",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://example.com/first"
        )
        let second = Station(
            id: "second",
            name: "Second",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://example.com/second"
        )
        let third = Station(
            id: "third",
            name: "Third",
            country: "France",
            language: "French",
            tags: "live",
            streamURL: "https://example.com/third"
        )

        XCTAssertEqual(
            AppShellHomeFeed.mergeUniqueStations(primary: [first, second], secondary: [first, third], limit: 3).map(\.id),
            ["first", "second", "third"]
        )
        XCTAssertEqual(
            AppShellHomeFeed.defaultEditorialStations(
                currentStation: first,
                recentStations: [second, first],
                favoriteStations: [third],
                samples: []
            ).map(\.id),
            ["first", "second", "third"]
        )
    }

    func testHomeFeedResolvesDeviceCountryCode() {
        XCTAssertEqual(
            AppShellHomeFeed.resolvedDeviceCountryCode(
                locale: Locale(identifier: "en_ES"),
                fallback: Locale(identifier: "en_US")
            ),
            "ES"
        )
        XCTAssertNil(
            AppShellHomeFeed.resolvedDeviceCountryCode(
                locale: Locale(identifier: "en_001"),
                fallback: Locale(identifier: "en_EU")
            )
        )
    }

    func testHomeFeedCacheEncodesDecodesAndExpiresPayloads() {
        let suiteName = "tuneav.homeFeedCache.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let cache = HomeFeedCache(userDefaults: userDefaults, maxAge: 60)
        let station = Station(
            id: "cached",
            name: "Cached Radio",
            country: "Spain",
            language: "Spanish",
            tags: "news",
            streamURL: "https://example.com/cached"
        )
        let key = HomeFeedCache.Key(
            localeIdentifier: "es",
            countryCode: "ES",
            preferredTag: " news ",
            language: nil,
            limit: 12
        )

        cache.save(
            HomeFeedResult(stations: [station], context: .popularInCountry("ES")),
            for: key,
            now: Date(timeIntervalSince1970: 1_000)
        )

        let cached = cache.load(for: key, now: Date(timeIntervalSince1970: 1_030))
        XCTAssertEqual(cached?.stations.map(\.id), ["cached"])
        XCTAssertEqual(cached?.context, .popularInCountry("ES"))
        XCTAssertEqual(cached?.cachedAt, Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(cache.load(for: key, now: Date(timeIntervalSince1970: 1_061)))
    }

    func testSearchRequestNormalizesKeyAndMode() {
        let direct = AppShellSearchRequest(query: "  nova  ", tag: " jazz ", countryCode: " es ")
        let worldwide = AppShellSearchRequest(query: "   ", tag: nil, countryCode: nil)

        XCTAssertEqual(direct.key, "nova|jazz|ES")
        XCTAssertFalse(direct.usesWorldwideDiscovery)
        XCTAssertEqual(direct.searchLimit, 24)
        XCTAssertEqual(worldwide.key, "||")
        XCTAssertTrue(worldwide.usesWorldwideDiscovery)
        XCTAssertEqual(worldwide.searchLimit, 12)
    }

    func testAppShellTabResolvesLaunchContextDefaults() {
        XCTAssertEqual(AppShellTab(nil, preferredSearchQuery: nil), .home)
        XCTAssertEqual(AppShellTab(nil, preferredSearchQuery: "jazz"), .search)
        XCTAssertEqual(AppShellTab(.search, preferredSearchQuery: nil), .search)
        XCTAssertEqual(AppShellTab(.library, preferredSearchQuery: nil), .library)
        XCTAssertEqual(AppShellTab(.music, preferredSearchQuery: nil), .music)
        XCTAssertEqual(AppShellTab(.settings, preferredSearchQuery: nil), .profile)
        XCTAssertEqual(AppShellTab(.player, preferredSearchQuery: nil), .home)
    }

    func testSearchFiltersLocalUITestSamples() {
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

    func testSearchBuildsOrderedDiscoveryCountryCodes() {
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

    func testNowPlayingPreviewCandidatesFollowSelectedTabAndDeduplicate() {
        let first = station(id: "first", countryCode: "ES")
        let second = station(id: "second", countryCode: "FR")
        let third = station(id: "third", countryCode: "US")
        let homeSnapshot = HomeFeedSnapshot(
            stations: [first, third],
            recentStations: [first, second],
            favoriteStations: [second],
            feedContext: .popularWorldwide
        )

        XCTAssertEqual(
            AppShellNowPlayingPreviews.candidateStations(
                selectedTab: .home,
                homeSnapshot: homeSnapshot,
                searchResults: [third],
                favoriteStations: [second],
                recentStations: [first],
                isEnabled: true
            ).map(\.id),
            ["first", "second", "third"]
        )
        XCTAssertEqual(
            AppShellNowPlayingPreviews.candidateStations(
                selectedTab: .library,
                homeSnapshot: homeSnapshot,
                searchResults: [],
                favoriteStations: [second, first],
                recentStations: [first, third],
                isEnabled: true
            ).map(\.id),
            ["second", "first", "third"]
        )
        XCTAssertTrue(
            AppShellNowPlayingPreviews.candidateStations(
                selectedTab: .search,
                homeSnapshot: homeSnapshot,
                searchResults: [first],
                favoriteStations: [],
                recentStations: [],
                isEnabled: false
            ).isEmpty
        )
    }

    func testMusicLibraryFiltersAndGroupsDiscoveries() {
        let station = Station(
            id: "station",
            name: "Station",
            country: "Spain",
            language: "Spanish",
            tags: "live",
            streamURL: "https://example.com/station"
        )
        let saved = DiscoveredTrack(
            title: "Song A",
            artist: "Artist One",
            station: station,
            artworkURL: URL(string: "https://example.com/a.jpg"),
            markedInterestedAt: Date()
        )
        let hidden = DiscoveredTrack(
            title: "Song B",
            artist: "Artist Two",
            station: station,
            artworkURL: nil,
            markedInterestedAt: Date(),
            hiddenAt: Date()
        )
        let history = DiscoveredTrack(
            title: "News Theme",
            artist: nil,
            station: station,
            artworkURL: nil
        )

        XCTAssertEqual(AppShellMusicLibrary.visibleDiscoveries([saved, hidden, history]).map(\.title), ["Song A", "News Theme"])
        XCTAssertEqual(
            AppShellMusicLibrary.filteredDiscoveries(
                [saved, hidden, history],
                mode: .songs,
                query: "artist",
                selectedArtistName: nil
            ).map(\.title),
            ["Song A"]
        )
        XCTAssertEqual(
            AppShellMusicLibrary.filteredDiscoveries(
                [saved, hidden, history],
                mode: .history,
                query: "theme",
                selectedArtistName: nil
            ).map(\.title),
            ["News Theme"]
        )
        XCTAssertEqual(
            AppShellMusicLibrary.filteredArtistSummaries([saved, hidden, history], mode: .songs, query: "").map(\.name),
            ["Artist One"]
        )
    }

    func testMusicLibraryShareTextAndInitialMode() {
        let station = Station(
            id: "station",
            name: "Station",
            country: "Spain",
            language: "Spanish",
            tags: "live",
            streamURL: "https://example.com/station"
        )
        let history = DiscoveredTrack(
            title: "Live Segment",
            artist: nil,
            station: station,
            artworkURL: nil
        )

        let shareText = AppShellMusicLibrary.shareText(title: "Discoveries", discoveries: [history])

        XCTAssertTrue(shareText.hasPrefix("Discoveries\n"))
        XCTAssertTrue(shareText.contains("Live Segment"))
        XCTAssertTrue(shareText.contains("Station"))
        XCTAssertEqual(
            AppShellMusicLibrary.normalizedInitialMode(.songs, discoveries: [history]),
            .history
        )
    }

    func testLibraryStationLogicFiltersByNameCountryAndTags() {
        let rock = Station(
            id: "rock",
            name: "Rock Central",
            country: "United Kingdom",
            language: "English",
            tags: "guitar,classic",
            streamURL: "https://example.com/rock"
        )
        let jazz = Station(
            id: "jazz",
            name: "Blue Night",
            country: "France",
            language: "French",
            tags: "jazz,late night",
            streamURL: "https://example.com/jazz"
        )
        let news = Station(
            id: "news",
            name: "Morning Brief",
            country: "Spain",
            language: "Spanish",
            tags: "news,talk",
            streamURL: "https://example.com/news"
        )
        let stations = [rock, jazz, news]

        XCTAssertEqual(TuneAVLibraryStationLogic.filteredStations(stations, query: " rock "), [rock])
        XCTAssertEqual(TuneAVLibraryStationLogic.filteredStations(stations, query: "france"), [jazz])
        XCTAssertEqual(TuneAVLibraryStationLogic.filteredStations(stations, query: "talk"), [news])
        XCTAssertEqual(TuneAVLibraryStationLogic.filteredStations(stations, query: "   "), stations)
    }

    func testPlaybackQueueLogicDeduplicatesAndCyclesStations() throws {
        XCTAssertEqual(TuneAVPlaybackQueueSource.homeRecents, AudioPlayerService.PlaybackQueue.Source.homeRecents)
        XCTAssertEqual(TuneAVPlaybackQueueSource.homeFavorites, AudioPlayerService.PlaybackQueue.Source.homeFavorites)
        XCTAssertEqual(TuneAVPlaybackQueueSource.homeDiscovery, AudioPlayerService.PlaybackQueue.Source.homeDiscovery)
        XCTAssertEqual(TuneAVPlaybackQueueSource.searchResults, AudioPlayerService.PlaybackQueue.Source.searchResults)
        XCTAssertEqual(TuneAVPlaybackQueueSource.libraryRecents, AudioPlayerService.PlaybackQueue.Source.libraryRecents)
        XCTAssertEqual(TuneAVPlaybackQueueSource.libraryFavorites, AudioPlayerService.PlaybackQueue.Source.libraryFavorites)
        XCTAssertEqual(TuneAVPlaybackQueueSource.singleStation, AudioPlayerService.PlaybackQueue.Source.singleStation)

        let current = Station(id: "current", name: "Current", country: "Spain", language: "Spanish", tags: "pop", streamURL: "https://example.com/current")
        let first = Station(id: "first", name: "First", country: "France", language: "French", tags: "jazz", streamURL: "https://example.com/first")
        let second = Station(id: "second", name: "Second", country: "Germany", language: "German", tags: "rock", streamURL: "https://example.com/second")

        let sanitized = TuneAVPlaybackQueueLogic.sanitizedStations(
            [first, second, first],
            currentStation: current,
            currentStationID: current.id
        )

        XCTAssertEqual(sanitized.map(\.id), ["current", "first", "second"])

        let resolved = try XCTUnwrap(TuneAVPlaybackQueueLogic.resolvedQueue(stations: sanitized, currentStation: current))
        XCTAssertEqual(TuneAVPlaybackQueueLogic.nextStation(in: resolved).id, "first")
        XCTAssertEqual(TuneAVPlaybackQueueLogic.previousStation(in: resolved).id, "second")
    }

    func testAudioPlaybackPolicyRetriesOnlyAfterRequestedNetworkRecovery() {
        XCTAssertEqual(TuneAVAudioPlaybackPolicy.loadingTimeoutSeconds, .seconds(12))
        XCTAssertEqual(TuneAVAudioPlaybackPolicy.nowPlayingFallbackInitialDelay, .seconds(4))
        XCTAssertEqual(TuneAVAudioPlaybackPolicy.nowPlayingFallbackPollingInterval, .seconds(25))

        XCTAssertTrue(
            TuneAVAudioPlaybackPolicy.shouldRetryAfterNetworkRestored(
                isNetworkSatisfied: true,
                hadPreviousNetworkStatus: true,
                wasPreviouslyUnsatisfied: true,
                userRequestedPlayback: true,
                hasCurrentStation: true,
                isRecoverablePlaybackState: true
            )
        )

        XCTAssertFalse(
            TuneAVAudioPlaybackPolicy.shouldRetryAfterNetworkRestored(
                isNetworkSatisfied: true,
                hadPreviousNetworkStatus: true,
                wasPreviouslyUnsatisfied: true,
                userRequestedPlayback: false,
                hasCurrentStation: true,
                isRecoverablePlaybackState: true
            )
        )

        XCTAssertFalse(
            TuneAVAudioPlaybackPolicy.shouldRetryAfterNetworkRestored(
                isNetworkSatisfied: true,
                hadPreviousNetworkStatus: true,
                wasPreviouslyUnsatisfied: false,
                userRequestedPlayback: true,
                hasCurrentStation: true,
                isRecoverablePlaybackState: true
            )
        )
    }

    func testStationResolvesHomepageAndBuildsShareText() {
        let station = Station(
            id: "nova",
            name: "Radio Nova",
            country: "France",
            language: "French",
            tags: "eclectic",
            streamURL: "https://stream.example.com/nova",
            homepageURL: " https://www.nova.fr "
        )

        XCTAssertEqual(station.resolvedHomepageURL?.host, "www.nova.fr")
        XCTAssertEqual(station.shareText, "Radio Nova\nhttps://www.nova.fr")
    }

    func testStationDisplayArtworkURLDoesNotReturnFaviconOrProxyURL() {
        let station = Station(
            id: "australian-digital-radio",
            name: "Australian Digital Radio Network",
            country: "Australia",
            countryCode: "AU",
            language: "English",
            tags: "radio",
            streamURL: "https://example.com/stream",
            faviconURL: "http://www.australiandigitalradio.com/favicon.ico",
            homepageURL: "http://www.australiandigitalradio.com/"
        )

        XCTAssertNil(station.displayArtworkURL)
        XCTAssertFalse(station.displayArtworkUsesFaviconProxy)
    }

    func testStationFallbackArtworkSelectionIsDeterministic() {
        let station = Station(
            id: "stable-station-id",
            name: "Stable Station",
            country: "United States",
            language: "English",
            tags: "radio",
            streamURL: "https://example.com/stream"
        )

        XCTAssertEqual(TuneAVFallbackArtwork.select(for: station), TuneAVFallbackArtwork.select(for: station))
        XCTAssertEqual(TuneAVFallbackArtwork.stableHash(station.id), TuneAVFallbackArtwork.stableHash(station.id))
    }

    func testStationFallbackInitialsGeneration() {
        let station = Station(
            id: "radio-nova",
            name: "Radio Nova",
            country: "France",
            language: "French",
            tags: "eclectic",
            streamURL: "https://example.com/stream"
        )

        XCTAssertEqual(station.initials, "RN")
    }

    func testFallbackArtworkMapsRockAndJazzTags() {
        let rockStation = Station(
            id: "rock",
            name: "Rock Station",
            country: "United States",
            language: "English",
            tags: "classic rock,alternative",
            streamURL: "https://example.com/rock"
        )
        let jazzStation = Station(
            id: "jazz",
            name: "Jazz Station",
            country: "United States",
            language: "English",
            tags: "jazz,chill,blues",
            streamURL: "https://example.com/jazz"
        )

        XCTAssertTrue([.rockAlternativeA, .rockAlternativeB].contains(rockStation.fallbackArtwork))
        XCTAssertEqual(jazzStation.fallbackArtwork, .jazzBluesSoul)
    }

    func testStationShareTextFallsBackToStreamURL() {
        let station = Station(
            id: "stream-only",
            name: "Stream Only",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://stream.example.com/live",
            homepageURL: " "
        )

        XCTAssertNil(station.resolvedHomepageURL)
        XCTAssertEqual(station.shareText, "Stream Only\nhttps://stream.example.com/live")
    }

    func testStationPresentationFiltersUnknownDetailsAndResolvedCountry() {
        let station = Station(
            id: "unknown-country",
            name: "Unknown Country",
            country: "Unknown country",
            language: "  Jazz  ",
            tags: "jazz",
            streamURL: "https://stream.example.com/jazz"
        )

        XCTAssertEqual(
            station.cardDetailText(
                preferCountryName: true,
                unknownValues: ["Unknown country"],
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Jazz"
        )
        XCTAssertFalse(
            station.hasResolvedCountry(
                unknownCountryValues: ["Unknown country"],
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
    }

    func testDateCodingRoundTripsFractionalISO8601() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let encoded = TuneAVDateCoding.string(from: date)

        XCTAssertEqual(TuneAVDateCoding.date(from: encoded), date)
        XCTAssertEqual(TuneAVDateCoding.date(from: "not-a-date"), .distantPast)
    }

    func testDateCodingBuildsDayIdentifier() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let utc = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(TuneAVDateCoding.dayIdentifier(for: date, timeZone: utc), "2023-11-14")
    }

    func testCollectionRulesTrimAndOverflowByRecency() {
        let values = [1, 2, 3, 4]

        XCTAssertEqual(TuneAVCollectionRules.trimmed(values, limit: 2), [1, 2])
        XCTAssertEqual(
            TuneAVCollectionRules.overflow(in: values, limit: 2, sortedBy: >),
            [2, 1]
        )
    }

    func testCollectionRulesMoveIdentifiableItemToFront() {
        let first = Station(
            id: "first",
            name: "First",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://example.com/first"
        )
        let second = Station(
            id: "second",
            name: "Second",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://example.com/second"
        )
        let updatedFirst = Station(
            id: "first",
            name: "First Updated",
            country: "United States",
            language: "English",
            tags: "live",
            streamURL: "https://example.com/first-updated"
        )

        let reordered = TuneAVCollectionRules.movingToFront(updatedFirst, in: [first, second], limit: 2)

        XCTAssertEqual(reordered.map(\.id), ["first", "second"])
        XCTAssertEqual(reordered.first?.name, "First Updated")
    }

    func testDiscoveredTrackSupportBuildsStableNormalizedID() {
        let id = TuneAVDiscoveredTrackSupport.makeID(
            title: "  Malamente  ",
            artist: "Rosalia",
            stationID: "station/one",
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(id, "rosalia-malamente-station-one")
    }

    func testDiscoveredTrackSupportResolvesOptionalArtworkURL() {
        XCTAssertEqual(
            TuneAVDiscoveredTrackSupport.resolvedURL("https://example.com/artwork.jpg")?.absoluteString,
            "https://example.com/artwork.jpg"
        )
        XCTAssertNil(TuneAVDiscoveredTrackSupport.resolvedURL(nil))
    }

    func testResolvedAccessLocalFallbackMatchesAccessPolicy() {
        let guest = TuneAVResolvedAccess.localFallback(for: .guest)
        XCTAssertEqual(guest.planTier, .free)
        XCTAssertEqual(guest.accessMode, .guest)
        XCTAssertEqual(guest.capabilities, .forMode(.guest))
        XCTAssertEqual(
            guest.limits,
            TuneAVAccessLimitPolicy.resolvedLimits(.forMode(.guest), accessMode: .guest)
        )

        let pro = TuneAVResolvedAccess.localFallback(for: .signedInPro)
        XCTAssertEqual(pro.planTier, .pro)
        XCTAssertEqual(pro.accessMode, .signedInPro)
        XCTAssertEqual(pro.capabilities, .forMode(.signedInPro))
        XCTAssertEqual(
            pro.limits,
            TuneAVAccessLimitPolicy.resolvedLimits(.forMode(.signedInPro), accessMode: .signedInPro)
        )
    }

    func testInitialsUseSharedTwoWordFallbackRule() {
        XCTAssertEqual(TuneAVInitials.make(from: "Massive Attack"), "MA")
        XCTAssertEqual(TuneAVInitials.make(from: "  Rosalia  "), "R")
        XCTAssertEqual(TuneAVInitials.make(from: "Exclusively - Bon Jovi Hits"), "EB")
        XCTAssertEqual(TuneAVInitials.make(from: "0-9 Radio"), "R")
        XCTAssertEqual(TuneAVInitials.make(from: "--- 101"), "AV")
        XCTAssertEqual(TuneAVInitials.make(from: "   "), "AV")

        let accountUser = AccountUser(id: "user", displayName: "Boards of Canada", emailAddress: nil)
        XCTAssertEqual(accountUser.initials, "BO")

        let station = Station(
            id: "station",
            name: "Radio Nova",
            country: "France",
            language: "French",
            tags: "radio",
            streamURL: "https://example.com/stream"
        )
        XCTAssertEqual(station.initials, "RN")
    }

    func testLocalRecommendationScorerPrioritizesPositiveFeedback() {
        let liked = recommendationStation(id: "liked", tags: "jazz")
        let disliked = recommendationStation(id: "disliked", tags: "jazz")
        let scorer = TuneAVLocalRecommendationScorer(
            currentStation: nil,
            recentStations: [],
            favoriteStations: [],
            discoveries: [],
            stationFeedback: [
                liked.id: .liked,
                disliked.id: .disliked
            ],
            feedContext: .popularWorldwide,
            preferredTag: ""
        )

        let likedRank = scorer.rank(liked)
        let dislikedRank = scorer.rank(disliked)

        XCTAssertGreaterThan(likedRank.score, dislikedRank.score)
        XCTAssertEqual(likedRank.primaryReason, .likedStation)
        XCTAssertEqual(dislikedRank.primaryReason, .dislikedStation)
    }

    func testLocalRecommendationScorerExplainsRecentTagMatches() {
        let recent = recommendationStation(id: "recent", tags: "jazz, soul")
        let candidate = recommendationStation(id: "candidate", tags: "ambient, jazz")
        let scorer = TuneAVLocalRecommendationScorer(
            currentStation: nil,
            recentStations: [recent],
            favoriteStations: [],
            discoveries: [],
            stationFeedback: [:],
            feedContext: .popularWorldwide,
            preferredTag: ""
        )

        let rank = scorer.rank(candidate)

        XCTAssertTrue(rank.reasons.contains(.recentTag))
        XCTAssertEqual(
            TuneAVLocalRecommendationScorer.localizedSummary(for: .recentTag),
            L10n.string("recommendations.reason.recentTag")
        )
    }

    private func queryValue(_ name: String, in url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }

    private func testURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TuneAVTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func station(id: String, countryCode: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Country \(countryCode)",
            countryCode: countryCode,
            language: "English",
            tags: "live",
            streamURL: "https://example.com/\(id)"
        )
    }

    private func recommendationStation(id: String, tags: String, countryCode: String = "US") -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Country \(countryCode)",
            countryCode: countryCode,
            language: "English",
            tags: tags,
            streamURL: "https://example.com/\(id)"
        )
    }

    private var accountDeletionCopy: TuneAVAccountDeletionPolicy.Copy {
        TuneAVAccountDeletionPolicy.Copy(
            linkedAppTitle: "Linked app",
            linkedAppDetail: "Linked app detail",
            proTitle: "Pro",
            proDetail: "Pro detail",
            subscriptionTitle: "Subscription",
            subscriptionDetail: "Subscription detail",
            jobTitle: "Job",
            unavailableTitle: "Unavailable",
            unavailableDetail: "Unavailable detail"
        )
    }
}

private final class TuneAVTestURLProtocol: URLProtocol {
    nonisolated(unsafe)
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
