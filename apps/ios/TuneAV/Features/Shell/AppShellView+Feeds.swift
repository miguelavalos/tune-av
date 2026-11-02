import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    func refreshHomeFeed(forceRemote: Bool = false) async {
        let preferredTag = libraryStore.settings.preferredTag
        homeErrorMessage = nil

        if !forceRemote {
            let immediateStations = immediateHomeFeedStations(preferredTag: preferredTag)
            if !immediateStations.stations.isEmpty {
                homeStations = immediateStations.stations
                homeFeedContext = immediateStations.context
                refreshHomePresentation()
            }
        }

        homeIsLoading = homeStations.isEmpty

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestDiscovery {
            homeStations = Array(Station.samples.prefix(AppShellHomeFeed.defaultFeedLimit))
            homeFeedContext = .popularWorldwide
            refreshHomePresentation()
            homeIsLoading = false
            return
        }

        do {
            let feed = forceRemote
                ? try await homeFeed.refresh(preferredTag: preferredTag)
                : try await homeFeed.load(preferredTag: preferredTag)
            guard preferredTag == libraryStore.settings.preferredTag else {
                homeIsLoading = false
                return
            }
            rememberBackendStations(feed.stations)
            homeStations = feed.stations
            homeFeedContext = feed.context
            refreshHomePresentation()
            homeIsLoading = false
        } catch is CancellationError {
            homeIsLoading = false
        } catch {
            homeStations = defaultEditorialStations
            homeFeedContext = .popularWorldwide
            homeErrorMessage = defaultEditorialStations.isEmpty ? L10n.string("shell.error.home") : nil
            refreshHomePresentation()
            homeIsLoading = false
        }
    }

    func immediateHomeFeedStations(preferredTag: String) -> HomeFeedResult {
        if let cached = homeFeed.cachedResult(preferredTag: preferredTag) {
            return cached
        }

        return HomeFeedResult(
            stations: defaultEditorialStations,
            context: .popularWorldwide
        )
    }

    func refreshHomePresentation() {
        let snapshot = HomeFeedSnapshot(
            stations: homeStations,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            feedContext: homeFeedContext
        )
        guard homeSnapshot != snapshot else { return }
        homeSnapshot = snapshot
    }

    func refreshHomePresentationAndFeed() async {
        refreshHomePresentation()
        let hadCachedFeed = homeFeed.cachedResult(preferredTag: libraryStore.settings.preferredTag) != nil
        await refreshHomeFeed()
        if hadCachedFeed {
            await refreshHomeFeed(forceRemote: true)
        }
    }

    func loadSearchResults() async {
        let request = searchRequest
        let requestKey = searchRequestKey

        guard shouldLoadSearchResults(for: request) else {
            searchPresentation.finishCancelled()
            return
        }

        seedSearchResultsIfNeeded(for: request)
        searchPresentation.beginLoading()
        searchLogger.debug(
            "Search load started has_query=\(!request.query.isEmpty, privacy: .public) has_tag=\(request.tag != nil, privacy: .public) has_country=\(request.countryCode != nil, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
        )

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            let results = AppShellSearch.localUITestSearchResults(request: request)
            searchPresentation.finishLoading(results: results)
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()

            let page = try await appSearch.load(
                request: request,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
            guard requestKey == searchRequestKey else { return }

            let results = page.stations
            rememberBackendStations(results)
            searchPresentation.finishLoading(page: page)
            searchLogger.info(
                "Search load completed result_count=\(results.count, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
            )
        } catch is CancellationError {
            guard requestKey == searchRequestKey else { return }
            searchPresentation.finishCancelled()
            searchLogger.debug("Search load cancelled")
        } catch {
            guard requestKey == searchRequestKey else { return }
            let fallback = searchFallbackStations(for: request)
            searchPresentation.finishWithFallback(fallback, emptyErrorMessage: L10n.string("shell.error.search"))
            searchLogger.error(
                "Search load failed fallback_count=\(fallback.count, privacy: .public) error=\(Self.safeErrorCode(error), privacy: .public)"
            )
        }
    }

    func loadMoreSearchResults() async {
        let request = searchRequest
        let requestKey = searchRequestKey
        guard !request.usesWorldwideDiscovery, let cursor = searchPresentation.beginLoadingMore() else { return }

        do {
            let page = try await appSearch.loadSearchPage(request: request, cursor: cursor)
            guard requestKey == searchRequestKey else { return }
            rememberBackendStations(page.stations)
            searchPresentation.finishLoadingMore(page: page)
            searchLogger.info(
                "Search next page completed result_count=\(page.stations.count, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
            )
        } catch {
            guard requestKey == searchRequestKey else { return }
            searchPresentation.finishCancelled()
            searchLogger.error("Search next page failed error=\(Self.safeErrorCode(error), privacy: .public)")
        }
    }

    func seedSearchResultsIfNeeded(for request: AppShellSearchRequest) {
        let fallback = searchFallbackStations(for: request)
        searchPresentation.seedResultsIfEmpty(fallback)
    }

    func searchFallbackStations(for request: AppShellSearchRequest) -> [Station] {
        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            return AppShellSearch.localUITestSearchResults(request: request)
        }
        guard request.query.isEmpty else { return [] }

        let candidates = AppShellHomeFeed.mergeUniqueStations(
            primary: homeSnapshot.stations,
            secondary: defaultEditorialStations,
            limit: request.searchLimit
        )
        let filtered = AppShellSearch.localUITestSearchResults(samples: candidates, request: request)
        if !filtered.isEmpty {
            return filtered
        }
        return request.tag == nil && request.countryCode == nil ? candidates : []
    }

    func shouldLoadSearchResults(for request: AppShellSearchRequest) -> Bool {
        selectedTab == .search ||
            !request.query.isEmpty ||
            request.tag != nil ||
            request.countryCode != nil
    }

    static func safeErrorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    var defaultEditorialStations: [Station] {
        AppShellHomeFeed.defaultEditorialStations(
            currentStation: audioPlayer.currentStation.map(enrichedStation),
            recentStations: enrichedRecentStations,
            favoriteStations: enrichedFavoriteStations
        )
    }

    func resolvedDeviceCountryCode() -> String? {
        AppShellHomeFeed.resolvedDeviceCountryCode()
    }

    func hasResolvedCountry(_ station: Station) -> Bool {
        station.hasResolvedCountry(
            unknownCountryValues: Station.unknownCountryValues,
            locale: L10n.locale
        )
    }
}
