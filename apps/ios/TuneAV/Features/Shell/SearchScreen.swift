import AVExternalLinkFoundation
import SwiftUI
import UIKit

struct SearchScreen: View {
    @Binding var query: String
    @Binding var activeTag: String?
    @Binding var selectedCountryCode: String?
    @Binding var discoveryMode: TuneAVStationDiscoveryMode

    let results: [Station]
    let isLoading: Bool
    let isLoadingMore: Bool
    let totalCount: Int?
    let hasMoreResults: Bool
    let errorMessage: String?
    let tags: [String]
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let loadMoreResults: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isShowingCountryPicker = false
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        TuneAdaptiveLayoutReader { layout in
            ScrollView {
                VStack(alignment: .leading, spacing: searchSpacing(for: layout)) {
                    searchHeader
                    searchControls
                    searchResultsSection
                }
                .shellScreenContentPadding(layout: layout, bottom: bottomContentPadding)
            }
            .shellScreenScrollBehavior()
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingCountryPicker) {
            SearchCountryPickerSheet(selectedCountryCode: $selectedCountryCode)
                .environmentObject(libraryStore)
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .onChange(of: selectedCountryCode) { _, newValue in
            libraryStore.setPreferredCountry(newValue)
        }
    }

    private var searchHeader: some View {
        AviScreenHeader(
            emotion: TuneAVAviEmotionResolver.searchEmotion(
                isLoading: isLoading,
                hasResults: !results.isEmpty,
                query: queryText,
                discoveryMode: discoveryMode
            ),
            title: L10n.string("shell.search.title"),
            summary: searchAviDetail,
            showsAviImage: false,
            accessibilityIdentifier: "search.aviHeader"
        )
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchField(query: $query)
            SearchCountryFilterButton(
                title: selectedCountryTitle,
                flag: selectedCountryFlag,
                isActive: selectedCountryCode != nil,
                clearAction: clearCountryFilter,
                openAction: { isShowingCountryPicker = true }
            )
            Picker(L10n.string("shell.search.discoveryMode"), selection: $discoveryMode) {
                Text(L10n.string("shell.search.discoveryMode.music")).tag(TuneAVStationDiscoveryMode.music)
                Text(L10n.string("shell.search.discoveryMode.allRadio")).tag(TuneAVStationDiscoveryMode.allRadio)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("search.discoveryMode")

            if queryText.isEmpty {
                GenreTagStrip(tags: visibleTags, activeTag: activeTag, toggleTag: toggleTag)
            }
        }
    }

    private var searchResultsSection: some View {
        StationSection(
            title: queryText.isEmpty && activeTag == nil && selectedCountryCode != nil
                ? L10n.string("shell.search.section.country.title", selectedCountryTitle)
                : queryText.isEmpty && activeTag == nil
                    ? L10n.string("shell.search.section.popularWorldwide.title")
                : queryText.isEmpty
                    ? L10n.string("shell.search.section.browse.title")
                    : L10n.string("shell.search.section.results.title"),
            subtitle: queryText.isEmpty
                ? browseSubtitle
                : L10n.plural(
                    singular: "shell.search.results.count.one",
                    plural: "shell.search.results.count.other",
                    count: totalCount ?? results.count,
                    totalCount ?? results.count,
                    queryText
                ),
            accessibilityIdentifier: "search.section.results"
        ) {
            searchResultsContent
        }
        .animation(.easeInOut(duration: 0.18), value: isLoading)
        .animation(.easeInOut(duration: 0.18), value: results.map(\.id))
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if !results.isEmpty {
            LazyVStack(spacing: 8) {
                if isLoading {
                    SearchUpdatingCard()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, station in
                    StationListActionRow(
                        station: station,
                        isFavorite: favoriteStationIDs.contains(station.id),
                        nowPlayingTrack: nowPlayingTracks[station.id],
                        stationFeedback: stationFeedback[station.id],
                        toggleFavorite: { toggleFavorite(station) },
                        playAction: { playStation(station, .searchResults, results) },
                        openWebsiteAction: { openStationWebsite(station) },
                        detailsAction: { showStationDetails(station, .searchResults, results) }
                    )
                    .opacity(isLoading ? 0.48 : 1)
                    .allowsHitTesting(!isLoading)
                    .zIndex(Double(results.count - index))
                }
                if hasMoreResults {
                    SearchLoadingCard()
                        .opacity(isLoadingMore ? 1 : 0.01)
                        .onAppear(perform: loadMoreResults)
                }
            }
        } else if isLoading {
            SearchLoadingCard()
        } else if let errorMessage {
            EmptyLibraryState(
                title: L10n.string("shell.search.error.title"),
                detail: errorMessage
            )
        } else if results.isEmpty {
            EmptyLibraryState(
                title: L10n.string("shell.search.empty.title"),
                detail: queryText.isEmpty && activeTag == nil
                    ? L10n.string("shell.search.empty.detail.initial")
                    : L10n.string("shell.search.empty.detail.retry")
            )
        }
    }

    private func searchSpacing(for layout: TuneLayoutContext) -> CGFloat {
        if layout.isTabletLike {
            return queryText.isEmpty ? 24 : 18
        }
        return queryText.isEmpty ? 20 : 14
    }

    private var queryText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleTag(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
    }

    private var visibleTags: [String] {
        switch discoveryMode {
        case .music:
            return tags
        case .allRadio:
            return tags + ["news", "sports", "talk", "culture", "local", "public", "religion"]
        }
    }

    private var searchAviDetail: String {
        if discoveryMode == .allRadio {
            return L10n.string("shell.search.avi.detail.allRadio")
        }
        if let activeTag {
            return L10n.string("shell.search.avi.detail.genre", L10n.genreLabel(for: activeTag))
        }
        return L10n.string("shell.search.avi.detail.music")
    }

    private var selectedCountryTitle: String {
        guard let selectedCountryCode else {
            return L10n.string("shell.search.country.all")
        }

        return L10n.countryName(for: selectedCountryCode)
    }

    private var browseSubtitle: String {
        if selectedCountryCode != nil {
            return L10n.string("shell.search.section.country.subtitle", selectedCountryTitle)
        }

        if activeTag == nil {
            return L10n.string("shell.search.section.popularWorldwide.subtitle")
        }

        return L10n.string("shell.search.section.browse.subtitle")
    }

    private func clearCountryFilter() {
        selectedCountryCode = nil
        libraryStore.setPreferredCountry(nil)
    }

    private func openStationWebsite(_ station: Station) {
        guard let url = station.resolvedHomepageURL else { return }
        if AVExternalWebOpenMode.resolved(from: libraryStore.settings.externalWebOpenMode) == .system {
            UIApplication.shared.open(url)
        } else {
            browserDestination = BrowserDestination(url: url)
        }
    }

    private var selectedCountryFlag: String? {
        guard let selectedCountryCode else { return nil }
        return CountryOption(code: selectedCountryCode, name: selectedCountryTitle).flag
    }
}
