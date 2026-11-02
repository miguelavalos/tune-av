import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    func focusedTrackInfo(_ discovery: DiscoveredTrack) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            focusedTrackSummaryCard(discovery)
            focusedTrackQuickActions(discovery)
            AviFocusedTrackStats(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                feedbackLabel: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
            )
            focusedMusicAviServices(for: .track(discovery))
            AviFocusedTrackArticle(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                lastSeenLabel: discovery.playedAt.formatted(date: .abbreviated, time: .shortened),
                feedbackLabel: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
            )
            trackStationsBlock(discovery)
        }
    }

    func focusedTrackSummaryCard(_ discovery: DiscoveredTrack) -> some View {
        AviFocusedTrackSummaryCard(
            discovery: discovery,
            feedback: libraryStore.feedback(for: discovery)
        )
    }

    func focusedTrackQuickActions(_ discovery: DiscoveredTrack) -> some View {
        AviFocusedTrackQuickActions(
            discovery: discovery,
            selectedFeedback: libraryStore.feedback(for: discovery),
            toggleSaved: {
                toggleDiscoverySaved(discovery)
            },
            openArtist: {
                nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery))
            },
            selectFeedback: { feedback in
                let nextFeedback = libraryStore.feedback(for: discovery) == feedback ? nil : feedback
                libraryStore.setFeedbackForDiscoveredTrack(nextFeedback, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
                AVHaptics.perform(stationFeedbackHapticEvent(for: nextFeedback))
            },
            clearFeedback: {
                guard libraryStore.feedback(for: discovery) != nil else { return }
                libraryStore.setFeedbackForDiscoveredTrack(nil, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
                AVHaptics.perform(.clear)
            }
        )
    }

    func discoveryArtistSummary(for discovery: DiscoveredTrack) -> DiscoveryArtistSummary {
        DiscoveryArtistSummary(
            name: discovery.artistDisplayText,
            trackCount: 1,
            artistArtworkURL: discovery.resolvedArtworkURL,
            fallbackArtworkURL: discovery.resolvedStationArtworkURL
        )
    }

    func focusedArtistInfo(_ summary: DiscoveryArtistSummary) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            focusedArtistSectionPicker(for: summary)

            switch selectedArtistDetailSection {
            case .info:
                focusedArtistInfoContent(summary)
            case .songs:
                artistSongsBlock(summary)
            }
        }
    }

    func focusedArtistInfoContent(_ summary: DiscoveryArtistSummary) -> some View {
        let discoveries = artistDiscoveries(for: summary)
        let savedSongs = discoveries.filter(\.isMarkedInteresting)
        let stationCount = artistStationSummaries(for: summary).count

        return AviFocusedArtistArticle {
            focusedArtistSummaryCard(summary, discoveries: discoveries)
        } stats: {
            AviFocusedArtistStats(
                savedSongsCount: savedSongs.count,
                stationCount: stationCount,
                latestSeenLabel: latestDiscovery(for: summary)?.playedAt.formatted(date: .numeric, time: .omitted) ?? L10n.string("shell.avi.music.feedback.empty")
            )
        } services: {
            focusedMusicAviServices(for: .artist(summary))
        } savedSongs: {
            EmptyView()
        } stations: {
            artistStationsBlock(summary)
        }
    }

    func focusedArtistSectionPicker(for summary: DiscoveryArtistSummary) -> some View {
        let artistDiscoveries = artistDiscoveries(for: summary)

        return HStack(spacing: 6) {
            focusedArtistSectionButton(
                .info,
                title: L10n.string("shell.stationDetail.section.about"),
                systemImage: "info.circle.fill",
                badge: nil
            )
            focusedArtistSectionButton(
                .songs,
                title: L10n.string("shell.music.mode.songs"),
                systemImage: "music.note.list",
                badge: artistDiscoveries.isEmpty ? nil : "\(artistDiscoveries.count)"
            )
        }
        .padding(4)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("avi.artistDetail.sections")
    }

    func focusedArtistSectionButton(
        _ section: ArtistDetailSection,
        title: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedArtistDetailSection == section

        return Button {
            AVHaptics.perform(.impactLight)
            selectedArtistDetailSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.cardSurface),
                            in: Capsule(style: .continuous)
                        )
                }
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle.opacity(0.78),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.artistDetail.section.\(section.accessibilityID)")
    }

    func focusedArtistSummaryCard(_ summary: DiscoveryArtistSummary, discoveries: [DiscoveredTrack]) -> some View {
        AviFocusedArtistSummaryCard(
            summary: summary,
            summaryLine: artistSummaryLine(summary),
            latestDiscoveryTitle: latestDiscovery(for: summary)?.title
        )
    }

    func artistSummaryLine(_ summary: DiscoveryArtistSummary) -> String {
        let songCount = L10n.plural(
            singular: "shell.library.discoveries.artistSongs.one",
            plural: "shell.library.discoveries.artistSongs.other",
            count: summary.trackCount,
            summary.trackCount
        )
        guard let latestDiscovery = latestDiscovery(for: summary) else { return songCount }
        return "\(songCount) · \(latestDiscovery.stationName)"
    }

    func focusedMusicAviServices(for detail: SelectedMusicAviDetail) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                TuneAviPopoverActionsPanel(close: closeAviActions) {
                    focusedMusicPrimaryCommands(for: detail)
                }
                .transition(.opacity)
            } else {
                detailAskAviCollapsedContent {
                    applyAviTransientState(currentAviTransientState.openingActions(resetPage: false))
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 316 : 168, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    func focusedAviServices(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station, showsStationDetailAction: false)
                    .transition(.opacity)
            } else {
                detailAskAviCollapsedContent {
                    applyAviTransientState(currentAviTransientState.openingActions())
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 316 : 168, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    func detailAskAviCollapsedContent(open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("shell.avi.actions.ask"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviPrimaryLine)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    open()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .black))
                    Text(L10n.string("player.avi.moreWithAvi"))
                        .font(.system(size: 15, weight: .black))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(TuneAVTheme.brandBlack)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("avi.actions.toggle")
        }
    }

    @ViewBuilder
    func artistSongsBlock(_ summary: DiscoveryArtistSummary) -> some View {
        let artistDiscoveries = artistDiscoveries(for: summary)
        let visibleSongs = Array(artistDiscoveries.prefix(visibleArtistSongLimit))
        let remainingCount = max(0, artistDiscoveries.count - visibleSongs.count)

        if !artistDiscoveries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleSongs) { discovery in
                    artistDiscoveryTrackCard(discovery)
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.music.mode.songs"),
                        remainingCount: remainingCount,
                        action: {
                            visibleArtistSongLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Text(L10n.string("shell.library.discoveries.empty"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    func artistDiscoveryTrackCard(_ discovery: DiscoveredTrack) -> some View {
        DiscoveryTrackCard(
            discovery: discovery,
            stationArtworkURL: nil,
            feedback: libraryStore.feedback(for: discovery),
            showsSaveButton: false,
            openAviActionsID: $openArtistDetailAviActionsID,
            openTrackInfo: { nestedMusicDetail = .track(discovery) },
            openArtistInfo: { nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery)) },
            openStationInfo: { openDiscoveryStation(discovery) },
            toggleSaved: { toggleDiscoverySaved(discovery) },
            openYouTube: {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
            },
            openLyrics: {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
            },
            openAppleMusic: {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .appleMusic)
            },
            openSpotify: {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .spotify)
            },
            hideAction: nil,
            removeAction: nil
        )
    }

    @ViewBuilder
    func artistStationsBlock(_ summary: DiscoveryArtistSummary) -> some View {
        let stations = artistStationSummaries(for: summary)
        let visibleStations = Array(stations.prefix(visibleArtistStationLimit))
        let resolvedVisibleStations = visibleStations.compactMap { station -> (station: Station, count: Int, latestDiscovery: DiscoveredTrack?)? in
            guard let resolvedStation = artistStation(for: station.id) else { return nil }
            return (resolvedStation, station.count, station.latestDiscovery)
        }
        let remainingCount = max(0, stations.count - visibleStations.count)
        if !resolvedVisibleStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.music.artist.radios"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(resolvedVisibleStations, id: \.station.id) { station in
                    StationListActionRow(
                        station: station.station,
                        isFavorite: favoriteStations.contains { $0.id == station.station.id },
                        nowPlayingTrack: station.latestDiscovery.map {
                            NowPlayingTrack(title: $0.title, artist: $0.artistDisplayText)
                        },
                        stationFeedback: stationFeedback[station.station.id],
                        toggleFavorite: { toggleFavorite(station.station) },
                        playAction: { playStation(station.station, [station.station]) },
                        openWebsiteAction: {
                            if let url = station.station.resolvedHomepageURL {
                                browserRouter.openURL(url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station], .about) }
                    )
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.avi.music.artist.radios"),
                        remainingCount: remainingCount,
                        action: {
                            visibleArtistStationLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    func trackStationsBlock(_ discovery: DiscoveredTrack) -> some View {
        let stations = trackStationSummaries(for: discovery)
        let resolvedStations = stations.compactMap { station -> (station: Station, count: Int)? in
            guard let resolvedStation = artistStation(for: station.id) else { return nil }
            return (resolvedStation, station.count)
        }
        if !resolvedStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.music.artist.radios"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(resolvedStations, id: \.station.id) { station in
                    StationListActionRow(
                        station: station.station,
                        isFavorite: favoriteStations.contains { $0.id == station.station.id },
                        nowPlayingTrack: nil,
                        stationFeedback: stationFeedback[station.station.id],
                        toggleFavorite: { toggleFavorite(station.station) },
                        playAction: { playStation(station.station, [station.station]) },
                        openWebsiteAction: {
                            if let url = station.station.resolvedHomepageURL {
                                browserRouter.openURL(url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station], .about) }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    func discoveryArtwork(_ discovery: DiscoveredTrack, size: CGFloat) -> some View {
        if let artworkURL = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    TuneAVMusicArtworkFallback(systemImage: "music.note", size: size, iconSize: 22)
                }
            }
        } else {
            TuneAVMusicArtworkFallback(systemImage: "music.note", size: size, iconSize: 22)
        }
    }

    @ViewBuilder
    func artistArtwork(_ summary: DiscoveryArtistSummary, size: CGFloat) -> some View {
        if let artworkURL = summary.displayArtworkURL {
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    TuneAVMusicArtworkFallback(systemImage: "person.fill", size: size, iconSize: 22)
                }
            }
        } else {
            TuneAVMusicArtworkFallback(systemImage: "person.fill", size: size, iconSize: 22)
        }
    }

    func latestDiscovery(for summary: DiscoveryArtistSummary) -> DiscoveredTrack? {
        artistDiscoveries(for: summary).first
    }

    func artistDiscoveries(for summary: DiscoveryArtistSummary) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
            .filter { normalizedArtistID($0.artistDisplayText) == summary.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    func artistStationSummaries(for summary: DiscoveryArtistSummary) -> [(id: String, name: String, count: Int, latestDiscovery: DiscoveredTrack?)] {
        let grouped = Dictionary(grouping: artistDiscoveries(for: summary), by: \.stationID)
        return grouped
            .map { stationID, discoveries in
                let latestDiscovery = discoveries.sorted { $0.playedAt > $1.playedAt }.first
                return (
                    id: stationID,
                    name: latestDiscovery?.stationName ?? stationID,
                    count: discoveries.count,
                    latestDiscovery: latestDiscovery
                )
            }
            .sorted {
                if let lhsDate = $0.latestDiscovery?.playedAt,
                   let rhsDate = $1.latestDiscovery?.playedAt,
                   lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func artistStation(for stationID: String) -> Station? {
        if let station = libraryStore.station(for: stationID) {
            return station
        }
        return stations.first { $0.id == stationID }
            ?? recentStations.first { $0.id == stationID }
            ?? favoriteStations.first { $0.id == stationID }
    }

    func trackStationSummaries(for discovery: DiscoveredTrack) -> [(id: String, name: String, count: Int)] {
        let key = focusedTrackIdentityKey(discovery)
        let grouped = Dictionary(
            grouping: TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries).filter {
                focusedTrackIdentityKey($0) == key
            },
            by: \.stationID
        )
        return grouped
            .map { stationID, discoveries in
                (id: stationID, name: discoveries.first?.stationName ?? stationID, count: discoveries.count)
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func focusedTrackIdentityKey(_ discovery: DiscoveredTrack) -> String {
        let artist = TuneAVText.normalizedValue(discovery.artistDisplayText) ?? discovery.artistDisplayText.lowercased()
        let title = TuneAVText.normalizedValue(discovery.title) ?? discovery.title.lowercased()
        return "\(artist)|\(title)"
    }

    func normalizedArtistID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: L10n.locale)
            .lowercased()
    }
}
