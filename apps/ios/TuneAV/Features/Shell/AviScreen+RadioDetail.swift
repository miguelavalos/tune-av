import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    func focusedRadioInfoCard(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.common.radio"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .textCase(.uppercase)

            Text(defaultPublicSignalInfo(for: station))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            listenToFocusedStationButton
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 10, y: 6)
    }

    func focusedRadioSummaryCard(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)

        let metadata: String? = if let latestDiscovery = stationDiscoveries.first {
            "\(L10n.string("shell.avi.music.latestSong")) · \(latestDiscovery.title)"
        } else if libraryStore.isFavorite(station) {
            L10n.string("shell.library.favorites.title")
        } else {
            nil
        }

        return AVAviFocusedSummaryCard(
            title: station.name,
            subtitle: defaultPublicSignalInfo(for: station),
            metadata: metadata
        ) {
            StationArtworkView(station: station, size: 62)
        }
    }

    func focusedRadioStats(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let latestDate = stationDiscoveries.first?.playedAt.formatted(date: .numeric, time: .omitted)
            ?? L10n.string("shell.avi.music.feedback.empty")

        return HStack(spacing: 7) {
            AVAviStatPill(
                title: L10n.string("shell.library.discoveries.title"),
                value: "\(stationDiscoveries.count)",
                systemImage: "music.note"
            )

            AVAviStatPill(
                title: L10n.string("shell.library.favorites.title"),
                value: libraryStore.isFavorite(station) ? L10n.string("common.yes") : L10n.string("common.no"),
                systemImage: "dot.radiowaves.left.and.right"
            )

            AVAviStatPill(
                title: L10n.string("shell.avi.music.lastSeen"),
                value: latestDate,
                systemImage: "clock.fill"
            )
        }
    }

    func focusedRadioSectionPicker(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)

        return HStack(spacing: 6) {
            focusedRadioSectionButton(
                .about,
                title: L10n.string("shell.stationDetail.section.about"),
                systemImage: "info.circle.fill",
                badge: nil
            )
            focusedRadioSectionButton(
                .history,
                title: L10n.string("shell.stationDetail.tab.history"),
                systemImage: "clock.arrow.circlepath",
                badge: stationDiscoveries.isEmpty ? nil : "\(stationDiscoveries.count)"
            )
        }
        .padding(4)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("avi.stationDetail.sections")
    }

    func focusedRadioSectionButton(
        _ section: StationDetailSection,
        title: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedStationDetailSection == section

        return Button {
            AVHaptics.perform(.impactLight)
            selectedStationDetailSection = section
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
        .accessibilityIdentifier("avi.stationDetail.section.\(section.accessibilityID)")
    }

    @ViewBuilder
    func focusedRadioHistoryBlock(for station: Station, showsTitle: Bool = true) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let visibleDiscoveries = Array(stationDiscoveries.prefix(visibleFocusedRadioHistoryLimit))
        let remainingCount = max(0, stationDiscoveries.count - visibleDiscoveries.count)
        if !stationDiscoveries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if showsTitle {
                    Text(L10n.string("shell.stationDetail.tab.history"))
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                }

                ForEach(visibleDiscoveries) { discovery in
                    DiscoveryTrackCard(
                        discovery: discovery,
                        stationArtworkURL: nil,
                        feedback: libraryStore.feedback(for: discovery),
                        showsSaveButton: false,
                        openAviActionsID: $openArtistDetailAviActionsID,
                        openTrackInfo: { nestedMusicDetail = .track(discovery) },
                        openArtistInfo: { nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery)) },
                        openStationInfo: { showStationDetails(station, [station], .about) },
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

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.stationDetail.tab.history"),
                        remainingCount: remainingCount,
                        action: {
                            visibleFocusedRadioHistoryLimit += Self.artistDetailPageSize
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

    func focusedStationDiscoveries(for station: Station) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
            .filter { $0.stationID == station.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    func focusedNowPlayingCard(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    Text(L10n.string("shell.common.playingNow"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                Spacer()
            }

                Text(station.name)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(currentTrackTitle ?? L10n.string("player.track.liveNow"))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.74)

                Text(currentTrackArtist ?? station.primaryDetailLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(hasCurrentSongContext ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if isFocusedStationActive && !hasCurrentSongContext {
                    Text(L10n.string("player.avi.poorInfo"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("player.avi.poorInfo")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 10, y: 6)
    }

    func focusedListeningDock(for station: Station) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.string("shell.common.playingNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer()

                aviSleepTimerMenu
            }

            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        isShowingArtworkZoom = true
                    }
                } label: {
                    currentArtwork(for: station, size: 72)
                        .overlay(alignment: .topLeading) {
                            if let feedback = currentTrackFeedback {
                                feedbackStatusBadge(feedback, size: 24)
                                    .offset(x: -5, y: -5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
                .accessibilityIdentifier("avi.nowPlaying.artworkZoom")

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(currentTrackArtist ?? L10n.string("player.track.liveNow"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(hasCurrentSongContext ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(currentTrackTitle ?? station.primaryDetailLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("player.dock.summary")
            }

            HStack(spacing: 18) {
                Spacer(minLength: 0)

                queueSourceDockButton

                queueDockButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)

                Button(action: openPlayer) {
                    ZStack {
                        Circle()
                            .fill(isPlaying ? TuneAVTheme.brandGraphite : TuneAVTheme.highlight)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: primaryFocusedActionIcon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryFocusedActionTitle)
                .accessibilityIdentifier("avi.controls.playPause")

                queueDockButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)

                closeSignalDockButton

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [TuneAVTheme.glassStroke, TuneAVTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.glassShadow.opacity(0.7), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.dock")
    }
}
