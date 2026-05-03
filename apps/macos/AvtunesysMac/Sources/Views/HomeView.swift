import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let stations: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let favorites: [Station]
    let recents: [Station]
    let feedContext: HomeFeedContext
    let playAction: (Station) -> Void
    let toggleFavorite: (Station) -> Void
    let showDetails: (Station) -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 860

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home")
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(AvtunesysTheme.textPrimary)
                            Text(homeSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AvtunesysTheme.textSecondary)
                        }

                        Spacer()

                        HeaderStatusPill(status: isLoading ? "Refreshing" : (audioPlayer.currentStation == nil ? "Live" : currentPlaybackStatus))
                    }

                    if !displayedRecentStations.isEmpty {
                        StationSection(title: "Recents", subtitle: "Resume recent playback.") {
                            LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                ForEach(displayedRecentStations) { station in
                                    StationRowCard(
                                        station: station,
                                        isFavorite: favorites.contains(where: { $0.id == station.id }),
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playAction(station) },
                                        detailsAction: { showDetails(station) }
                                    )
                                }
                            }
                        }
                    }

                    if !displayedFavoriteStations.isEmpty {
                        StationSection(title: "Favorites", subtitle: "Pinned stations.") {
                            LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                ForEach(displayedFavoriteStations) { station in
                                    StationRowCard(
                                        station: station,
                                        isFavorite: true,
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playAction(station) },
                                        detailsAction: { showDetails(station) }
                                    )
                                }
                            }
                        }
                    }

                    if isLoading && displayedPopularStations.isEmpty {
                        EmptyStateCard(title: "Refreshing stations", detail: "Fetching the latest live feed.")
                    } else if let errorMessage {
                        EmptyStateCard(title: "Feed unavailable", detail: errorMessage)
                    } else if !stations.isEmpty {
                        if !displayedPopularStations.isEmpty {
                            StationSection(title: sectionTitle, subtitle: sectionSubtitle) {
                                LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                    ForEach(displayedPopularStations) { station in
                                        StationRowCard(
                                            station: station,
                                            isFavorite: favorites.contains(where: { $0.id == station.id }),
                                            toggleFavorite: { toggleFavorite(station) },
                                            playAction: { playAction(station) },
                                            detailsAction: { showDetails(station) }
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        EmptyStateCard(title: "Nothing to play yet", detail: "Try a genre search or wait for the feed to refresh.")
                    }
                }
                .frame(maxWidth: compact ? 760 : 1040, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.top, compact ? 18 : 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var currentPlaybackStatus: String {
        switch audioPlayer.playbackState {
        case .idle:
            return "Live"
        case .loading:
            return "Loading"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .failed:
            return "Error"
        }
    }

    private var homeSubtitle: String {
        if !recents.isEmpty || !favorites.isEmpty {
            return "\(recents.count) recent stations · \(favorites.count) favorites"
        }
        return sectionTitle
    }

    private var displayedRecentStations: [Station] {
        recents
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 12)
        ]
    }

    private var displayedFavoriteStations: [Station] {
        Array(favorites.prefix(6))
    }

    private var displayedPopularStations: [Station] {
        let excludedIDs = Set(displayedRecentStations.map(\.id) + displayedFavoriteStations.map(\.id))
        return stations.filter { !excludedIDs.contains($0.id) }
    }

    private var sectionTitle: String {
        switch feedContext {
        case .popularWorldwide:
            return "Popular Worldwide"
        case .popularInCountry(let countryName):
            return "Popular in \(countryName)"
        }
    }

    private var sectionSubtitle: String {
        switch feedContext {
        case .popularWorldwide:
                return "Live catalogue update."
        case .popularInCountry(let countryName):
                return "Live catalogue update for \(countryName)."
        }
    }
}
