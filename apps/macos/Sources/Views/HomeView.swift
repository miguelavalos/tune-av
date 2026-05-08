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
                            Text(L10n.string("shell.home.title"))
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                            Text(homeSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }

                        Spacer()

                        HeaderStatusPill(status: isLoading ? L10n.string("shell.status.refreshing") : (audioPlayer.currentStation == nil ? L10n.string("shell.status.live") : currentPlaybackStatus))
                    }

                    if !displayedRecentStations.isEmpty {
                        StationSection(title: L10n.string("shell.home.recents.title"), subtitle: L10n.string("shell.home.recents.subtitle")) {
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
                        StationSection(title: L10n.string("shell.home.favorites.title"), subtitle: L10n.string("shell.home.favorites.subtitle")) {
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
                        EmptyStateCard(title: L10n.string("shell.status.refreshing"), detail: L10n.string("shell.home.section.popularWorldwide.subtitle"))
                    } else if let errorMessage {
                        EmptyStateCard(title: L10n.string("shell.home.error.title"), detail: errorMessage)
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
                        EmptyStateCard(title: L10n.string("shell.home.empty.title"), detail: L10n.string("shell.home.empty.detail"))
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
            return L10n.string("shell.status.live")
        case .loading, .playing, .paused:
            return audioPlayer.playbackState.label
        case .failed:
            return L10n.string("mac.player.status.error")
        }
    }

    private var homeSubtitle: String {
        if !recents.isEmpty || !favorites.isEmpty {
            return "\(recents.count) \(L10n.string("shell.home.recents.title").lowercased(with: L10n.locale)) · \(favorites.count) \(L10n.string("shell.home.favorites.title").lowercased(with: L10n.locale))"
        }
        return sectionTitle
    }

    private var displayedRecentStations: [Station] {
        recents
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 124, maximum: 150), spacing: 12)
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
        case .preferredGenre(let tag):
            return L10n.string("shell.home.section.topGenre.title", genreLabel(for: tag))
        case .popularWorldwide:
            return L10n.string("shell.home.section.popularWorldwide.title")
        case .popularInCountry(let countryName):
            return L10n.string("shell.home.section.popularCountry.title", countryName)
        }
    }

    private var sectionSubtitle: String {
        switch feedContext {
        case .preferredGenre:
                return L10n.string("shell.home.section.topGenre.subtitle")
        case .popularWorldwide:
                return L10n.string("shell.home.section.popularWorldwide.subtitle")
        case .popularInCountry(let countryName):
                return L10n.string("shell.home.section.popularCountry.subtitle", countryName)
        }
    }

    private func genreLabel(for tag: String) -> String {
        switch tag {
        case "rock":
            return L10n.string("genre.rock")
        case "pop":
            return L10n.string("genre.pop")
        case "jazz":
            return L10n.string("genre.jazz")
        case "news":
            return L10n.string("genre.news")
        case "electronic":
            return L10n.string("genre.electronic")
        case "ambient":
            return L10n.string("genre.ambient")
        default:
            return tag.capitalized
        }
    }
}
