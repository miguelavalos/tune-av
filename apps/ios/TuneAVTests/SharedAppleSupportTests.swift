import XCTest
@testable import TuneAV

final class SharedAppleSupportTests: XCTestCase {
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

    func testTrackMetadataParserIdentifiesStationLikeArtistsAsNotArtists() {
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("ROCK FM", stationName: "Rock FM"))
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Radio Nova", stationName: "Radio Nova"))
        XCTAssertTrue(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Live Stream", stationName: "KEXP"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("Radiohead", stationName: "KEXP"))
        XCTAssertFalse(TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata("R.E.M.", stationName: "Rock FM"))
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

    private func queryValue(_ name: String, in url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
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
}
