import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var aviContextHeader: some View {
        Group {
            if focusedDetailIsEmpty {
                AviScreenHeader(
                    emotion: aviEmotion,
                    title: L10n.string("shell.avi.title"),
                    summary: aviContextMeta,
                    showsAviImage: false,
                    accessibilityIdentifier: "avi.context.header"
                )
            } else if isNowPlayingFullPlayer, activeMusicDetail == nil {
                FullPlayerAviHeader(
                    emotion: aviEmotion,
                    reactionEmotion: aviReaction?.emotion,
                    reactionStartedAt: aviReaction == nil ? nil : aviReactionStartedAt,
                    label: fullPlayerAviCopy.label,
                    title: fullPlayerAviCopy.title,
                    summary: fullPlayerAviCopy.summary
                )
            } else {
                if activeMusicDetail != nil {
                    DetailTopHeader(
                        title: focusedDetailTypeTitle,
                        subtitle: aviContextTitle == aviContextMeta ? aviContextTitle : "\(aviContextTitle) · \(aviContextMeta)",
                        status: nil,
                        showsBackButton: true,
                        accessibilityIdentifier: "avi.detail.header",
                        goBack: closeActiveDetail
                    )
                } else {
                    DetailTopHeader(
                        title: focusedDetailTypeTitle,
                        subtitle: aviContextTitle == aviContextMeta ? aviContextTitle : "\(aviContextTitle) · \(aviContextMeta)",
                        status: nil,
                        feedback: focusedStation.flatMap { stationFeedback[$0.id] },
                        showsBackButton: true,
                        accessibilityIdentifier: "avi.detail.header",
                        goBack: closeFocusedDetail
                    )
                }
            }
        }
        .frame(height: isNowPlayingFullPlayer ? 96 : nil, alignment: .center)
    }

    var focusedDetailTypeTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track:
                return L10n.string("shell.avi.music.track.label")
            case .artist:
                return L10n.string("shell.avi.music.artist.label")
            }
        }
        return L10n.string("shell.common.radio")
    }

    var focusedDetailStatus: String? {
        if activeMusicDetail != nil {
            return L10n.string("tab.music")
        }
        guard focusedStation != nil else { return nil }
        return isFocusedStationActive ? L10n.string("shell.avi.status.playing") : L10n.string("shell.avi.status.info")
    }

    var aviContextTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.title
            case .artist(let summary):
                return summary.name
            }
        }
        return focusedStation?.name ?? L10n.string("shell.avi.context.emptyTitle")
    }

    var fullPlayerAviHeadline: String {
        guard isFocusedStationActive else {
            return L10n.string("shell.avi.mood.ready")
        }
        return L10n.string("shell.avi.mood.vibing")
    }

    var fullPlayerAviCopy: AviHeaderCopy {
        guard let station = focusedStation ?? currentStation else {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.ready.label"),
                title: L10n.string("shell.avi.header.ready.title"),
                summary: L10n.string("shell.avi.header.ready.summary")
            )
        }

        if isLoading {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.tuning.label"),
                title: L10n.string("shell.avi.header.tuning.title"),
                summary: L10n.string("shell.avi.header.tuning.summary")
            )
        }

        let feedback = focusedPrimaryFeedback(for: station)
        let hasSong = isFocusedStationActive && hasCurrentSongContext
        let isTrackSaved = hasSong && isCurrentTrackSaved(for: station)

        if isTrackSaved {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.saved.label"),
                title: L10n.string("shell.avi.header.saved.title"),
                summary: L10n.string("shell.avi.header.saved.summary")
            )
        }

        if let feedback {
            switch feedback {
            case .liked:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.learning.label"),
                    title: hasSong ? L10n.string("shell.avi.header.likedSong.title") : L10n.string("shell.avi.header.likedStation.title"),
                    summary: hasSong ? L10n.string("shell.avi.header.likedSong.summary") : L10n.string("shell.avi.header.likedStation.summary")
                )
            case .notForMe:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.adjusting.label"),
                    title: L10n.string("shell.avi.header.notForMe.title"),
                    summary: L10n.string("shell.avi.header.notForMe.summary")
                )
            case .disliked:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.discarding.label"),
                    title: L10n.string("shell.avi.header.disliked.title"),
                    summary: hasSong ? L10n.string("shell.avi.header.dislikedSong.summary") : L10n.string("shell.avi.header.dislikedStation.summary")
                )
            }
        }

        if hasSong {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.listening.label"),
                title: L10n.string("shell.avi.header.track.title"),
                summary: currentTrackArtist.map { L10n.string("shell.avi.header.trackWithArtist.summary", $0) } ?? L10n.string("shell.avi.header.track.summary")
            )
        }

        if libraryStore.isFavorite(station) {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.known.label"),
                title: L10n.string("shell.avi.header.favorite.title"),
                summary: L10n.string("shell.avi.header.favorite.summary")
            )
        }

        if station.displayArtworkURL != nil || station.editorial != nil {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.exploring.label"),
                title: L10n.string("shell.avi.header.context.title"),
                summary: station.category.map { L10n.string("shell.avi.header.contextWithCategory.summary", $0) } ?? L10n.string("shell.avi.header.context.summary")
            )
        }

        return AviHeaderCopy(
            label: isFocusedStationActive ? L10n.string("shell.avi.header.reading.label") : L10n.string("shell.avi.header.exploring.label"),
            title: isFocusedStationActive ? L10n.string("shell.avi.header.reading.title") : L10n.string("shell.avi.header.discover.title"),
            summary: isFocusedStationActive ? L10n.string("shell.avi.header.reading.summary") : L10n.string("shell.avi.header.discover.summary")
        )
    }

    var aviCommandEyebrow: String {
        if activeMusicDetail != nil {
            return L10n.string("tab.music")
        }
        if focusedStation != nil {
            return isFocusedStationActive ? L10n.string("shell.common.playingNow") : L10n.string("shell.common.radio")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.title")
        }
        return L10n.string("shell.avi.state.thinking")
    }

    var aviCommandTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.title
            case .artist(let summary):
                return summary.name
            }
        }
        if let focusedStation {
            return isFocusedStationActive
                ? (currentTrackTitle ?? focusedStation.name)
                : focusedStation.name
        }
        if let currentStation {
            if let currentTrackTitle {
                return currentTrackTitle
            }
            return L10n.string("shell.avi.command.tuning", currentStation.name)
        }
        return L10n.string("shell.avi.mood.ready")
    }

    var aviCommandDetail: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return "\(discovery.artistDisplayText) · \(discovery.stationName)"
            case .artist(let summary):
                return L10n.plural(
                    singular: "shell.library.discoveries.artistSongs.one",
                    plural: "shell.library.discoveries.artistSongs.other",
                    count: summary.trackCount,
                    summary.trackCount
                )
            }
        }
        if let focusedStation {
            if isNowPlayingFullPlayer && hasCurrentSongContext {
                return [currentTrackArtist, focusedStation.name].compactMap { $0 }.joined(separator: " · ")
            }
            return defaultPublicSignalInfo(for: focusedStation)
        }
        if let currentStation {
            if hasCurrentSongContext {
                return [currentTrackArtist, currentStation.name]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
            return L10n.string("shell.avi.command.readingSignal", currentStation.name)
        }
        return L10n.string("shell.avi.detail.ready")
    }

    var aviCurrentSignalTitle: String {
        if let currentTrackTitle {
            return currentTrackTitle
        }
        if let currentStation {
            return currentStation.name
        }
        return L10n.string("shell.avi.context.emptyTitle")
    }

    var aviCurrentSignalDetail: String {
        guard let currentStation else {
            return L10n.string("shell.avi.detail.ready")
        }

        if let currentTrackArtist {
            return L10n.string("shell.avi.currentSignal.artistDetail", currentTrackArtist, currentStation.name)
        }

        if let currentTrackTitle {
            return L10n.string("shell.avi.currentSignal.titleDetail", currentTrackTitle, currentStation.name)
        }

        return L10n.string("shell.avi.currentSignal.radioDetail", currentStation.name)
    }

    var aviContextMeta: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.artistDisplayText
            case .artist(let summary):
                return L10n.plural(
                    singular: "shell.library.discoveries.artistSongs.one",
                    plural: "shell.library.discoveries.artistSongs.other",
                    count: summary.trackCount,
                    summary.trackCount
                )
            }
        }
        if focusedStation != nil {
            if isNowPlayingFullPlayer {
                return L10n.string("shell.avi.context.currentRadio")
            }
            return focusedStation.map(defaultPublicSignalInfo(for:)) ?? L10n.string("shell.common.radio")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.primary.reacting")
        }
        return L10n.string("shell.avi.context.emptyDetail")
    }
}
