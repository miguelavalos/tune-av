import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var aviCommandCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                aviHeroImage(width: 64)
                    .padding(6)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(aviCommandEyebrow)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(aviCommandTitle)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(aviCommandDetail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 8) {
                if let focusedStation {
                    focusedStationPrimaryCommands(for: focusedStation)
                } else if let activeMusicDetail {
                    focusedMusicPrimaryCommands(for: activeMusicDetail)
                } else if let currentStation {
                    currentSignalPrimaryCommands(for: currentStation)
                } else {
                    defaultAviPrimaryCommands
                }
            }
            .accessibilityIdentifier("avi.commandCenter.actions")
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.22), radius: 14, y: 8)
        .accessibilityIdentifier("avi.commandCenter")
    }

    @ViewBuilder
    func focusedStationPrimaryCommands(for station: Station) -> some View {
        AVAviCommandButton(
            title: hasCurrentSongContext ? L10n.string("shell.avi.actions.searchLyrics") : L10n.string("shell.avi.actions.searchPublicInfo"),
            systemImage: hasCurrentSongContext ? "text.quote" : "info.circle",
            accessibilityIdentifier: "avi.command.primary.search"
        ) {
            if hasCurrentSongContext {
                openAviSearch(for: station, destination: .web, suffix: "lyrics")
            } else {
                openAviStationSearch(for: station)
            }
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            showStationDetails(station, [station], .history)
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.actions.findRelatedRadios"),
            systemImage: "sparkles",
            accessibilityIdentifier: "avi.command.primary.relatedRadios"
        ) {
            showRelatedStations(for: station)
        }
    }

    @ViewBuilder
    func focusedMusicPrimaryCommands(for detail: SelectedMusicAviDetail) -> some View {
        switch detail {
        case .track(let discovery):
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchLyrics"),
                systemImage: "text.quote",
                accessibilityIdentifier: "avi.command.primary.music.lyrics"
            ) {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.music.youtube"
            ) {
                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.music.artist"
            ) {
                openExternalSearch(query: discovery.artistDisplayText)
            }
        case .artist(let summary):
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.artist.search"
            ) {
                openExternalSearch(query: summary.name)
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.artist.youtube"
            ) {
                openExternalSearch(query: summary.name, destination: .youtube)
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.findRelatedRadios"),
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "avi.command.primary.artist.searchRadio"
            ) {
                if let stationID = latestDiscovery(for: summary)?.stationID,
                   let station = artistStation(for: stationID) {
                    showRelatedStations(for: station)
                } else {
                    openSearch()
                }
            }
        }
    }

    @ViewBuilder
    func currentSignalPrimaryCommands(for station: Station) -> some View {
        AVAviCommandButton(
            title: hasCurrentSongContext ? L10n.string("shell.avi.actions.searchLyrics") : L10n.string("shell.avi.actions.searchPublicInfo"),
            systemImage: hasCurrentSongContext ? "text.quote" : "info.circle",
            accessibilityIdentifier: hasCurrentSongContext ? "avi.command.primary.searchLyrics" : "avi.command.primary.searchRadio"
        ) {
            if hasCurrentSongContext {
                openAviSearch(for: station, destination: .web, suffix: "lyrics")
            } else {
                openAviStationSearch(for: station)
            }
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            showStationDetails(station, [station], .history)
        }
    }

    @ViewBuilder
    var defaultAviPrimaryCommands: some View {
        if currentStation != nil {
            AVAviCommandButton(
                title: L10n.string("shell.avi.action.nowPlaying"),
                systemImage: "waveform",
                accessibilityIdentifier: "avi.command.primary.currentPlayer"
            ) {
                openPlayer()
            }
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.action.findStation"),
            systemImage: "sparkles",
            accessibilityIdentifier: "avi.command.primary.findStation"
        ) {
            openSearch()
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.action.saved"),
            systemImage: "bookmark.fill",
            accessibilityIdentifier: "avi.command.primary.saved"
        ) {
            openLibrary()
        }

        if let recommendation = topRecommendation {
            AVAviCommandButton(
                title: L10n.string("shell.avi.recommendation.play"),
                systemImage: "play.fill",
                accessibilityIdentifier: "avi.command.primary.recommendation"
            ) {
                playStation(recommendation.station, recommendationQueue)
            }
        }
    }

    @ViewBuilder
    var aviCurrentSignalCard: some View {
        if currentStation != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.currentSignal"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviCurrentSignalTitle)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)

                Text(aviCurrentSignalDetail)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.live")
        } else if let recommendation = topRecommendation {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("shell.avi.recommendation.title"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(recommendation.station.name)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)

                Text(recommendation.reason)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.recommendation")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.signals.title"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(L10n.string("shell.avi.context.emptyTitle"))
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.avi.detail.ready"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.empty")
        }
    }

    @ViewBuilder
    var aviSuggestionStack: some View {
        if topRecommendation != nil {
            recommendationPanel
        } else {
            quickActions
        }
    }

    var aviListeningSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.avi.signals.using"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            if hasCurrentSongContext {
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.currentSong.title"),
                    detail: currentTrackArtist.map { L10n.string("shell.avi.signals.currentSong.detailWithArtist", $0) } ?? L10n.string("shell.avi.signals.currentSong.detail"),
                    systemImage: "music.note",
                    accessibilityIdentifier: "avi.signals.currentSong"
                )
            } else if let currentStation {
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.currentRadio.title"),
                    detail: L10n.string("shell.avi.signals.currentRadio.detail", currentStation.name),
                    systemImage: "dot.radiowaves.left.and.right",
                    accessibilityIdentifier: "avi.signals.currentRadio"
                )
            }

            if let recommendation = topRecommendation {
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.next.title"),
                    detail: "\(recommendation.station.name): \(recommendation.reason)",
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.signals.nextRecommendation"
                )
            }

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.feedback.title"),
                detail: feedbackSignalCount == 0 ? L10n.string("shell.avi.signals.feedback.emptyDetail") : L10n.plural(singular: "shell.avi.signals.feedback.count.one", plural: "shell.avi.signals.feedback.count.other", count: feedbackSignalCount, feedbackSignalCount),
                systemImage: "hand.thumbsup",
                accessibilityIdentifier: "avi.signals.feedback"
            )
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    @ViewBuilder
    func focusedMusicExperience(_ detail: SelectedMusicAviDetail) -> some View {
        switch detail {
        case .track(let discovery):
            focusedTrackInfo(discovery)
        case .artist(let summary):
            focusedArtistInfo(summary)
        }
    }
}
