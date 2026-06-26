import AVAppShellFoundation
import AVHaptics
import SwiftUI

private enum StationCompactMetrics {
    static let cardWidth: CGFloat = 258
    static let cardHeight: CGFloat = 112
    static let artworkSize: CGFloat = 82
    static let favoriteButtonSize: CGFloat = 44
    static let playBadgeSize: CGFloat = 36
    static let textLineHeight: CGFloat = 13
}

struct StationCompactCarousel: View {
    let stations: [Station]
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationInsight: (Station) -> String?
    var stationFeedback: [String: TuneAVStationFeedback] = [:]
    var layoutClass: TuneLayoutClass = .compact
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(stations) { station in
                    StationCompactCard(
                        station: station,
                        isFavorite: favoriteStationIDs.contains(station.id),
                        nowPlayingTrack: nowPlayingTracks[station.id],
                        recommendationInsight: stationInsight(station),
                        stationFeedback: stationFeedback[station.id],
                        toggleFavorite: { toggleFavorite(station) },
                        playAction: { playStation(station, queueSource, queueStations) },
                        detailsAction: { showStationDetails(station, queueSource, queueStations) }
                    )
                    .frame(width: cardWidth)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var cardWidth: CGFloat {
        switch layoutClass {
        case .compact:
            StationCompactMetrics.cardWidth
        case .regular:
            286
        case .expansive:
            304
        }
    }

    private var cardSpacing: CGFloat {
        layoutClass.isTabletLike ? 14 : 12
    }
}

private struct StationCompactCard: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let isFavorite: Bool
    let nowPlayingTrack: NowPlayingTrack?
    let recommendationInsight: String?
    var stationFeedback: TuneAVStationFeedback? = nil
    let toggleFavorite: () -> Void
    let playAction: () -> Void
    let detailsAction: () -> Void

    private var isPlayingCurrentStation: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isPlaying
    }

    private var isCurrentStationActive: Bool {
        audioPlayer.isCurrent(station) && (audioPlayer.isPlaying || audioPlayer.isLoading)
    }

    private var compactPrimaryLine: String {
        if let reliableArtist {
            return reliableArtist
        }

        if let reliableTitle {
            return reliableTitle
        }

        return compactStationContext ?? L10n.string("shell.station.row.defaultDetail")
    }

    private var compactSecondaryLine: String {
        if reliableArtist != nil, let reliableTitle {
            return reliableTitle
        }
        if reliableArtist != nil || reliableTitle != nil {
            return compactMetadataContextLine
        }
        return compactContextLine
    }

    private var compactTertiaryLine: String {
        if let stationFeedback {
            return stationFeedback.localizedState
        }
        return L10n.string("shell.station.row.aviCanTune")
    }

    private var compactContextLine: String {
        if reliableArtist != nil || reliableTitle != nil {
            return compactMetadataContextLine
        }
        return compactUniqueLine(
            candidates: [
                stationFeedback == nil ? recommendationInsight : nil,
                compactGenreLine,
                contextFallbackLine,
                L10n.string("shell.stationDetail.suggestedSignal")
            ],
            excluding: [compactPrimaryLine, compactStationContext]
        ) ?? L10n.string("shell.stationDetail.suggestedSignal")
    }

    private var compactMetadataContextLine: String {
        compactUniqueInsight(excluding: [compactPrimaryLine])
            ?? contextFallbackLine
    }

    private var contextFallbackLine: String {
        if isFavorite {
            return L10n.string("player.station.savedShort")
        }
        if audioPlayer.isCurrent(station) {
            return isPlayingCurrentStation ? L10n.string("player.track.liveNow") : L10n.string("audio.status.paused")
        }
        return L10n.string("shell.station.row.nearRecents")
    }

    private var compactGenreLine: String? {
        let tags = station.normalizedTags
            .compactMap(TuneAVMusicGenreCatalog.canonicalTag(for:))
            .map { L10n.genreLabel(for: $0) }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }
        guard !tags.isEmpty else { return nil }
        return tags.prefix(2).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                Button(action: playCompactStation) {
                    StationThumbnailView(
                        station: station,
                        size: StationCompactMetrics.artworkSize,
                        textMode: .none,
                        animationOverlay: .none,
                        isAnimationActive: false
                    )
                    .overlay {
                        artworkShape
                            .fill(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.16) : .clear)
                    }
                    .overlay {
                        if audioPlayer.isCurrent(station) {
                            currentStationOverlay
                        }
                    }
                    .overlay {
                        artworkShape
                            .stroke(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isCurrentStationActive ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationRow.play.\(station.id)")

                favoriteButton
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(compactPrimaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(reliableArtist != nil || reliableTitle != nil ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(compactSecondaryLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    feedbackBadgeIfNeeded

                    stationQualityBadges(hasNowPlaying: reliableArtist != nil || reliableTitle != nil)

                    if compactStatusBadges.isEmpty {
                        Text(compactTertiaryLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: StationCompactMetrics.artworkSize, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stationRow.\(station.id)")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.cardSurface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: detailsAction)
    }

    @ViewBuilder
    private var feedbackBadgeIfNeeded: some View {
        if let stationFeedback {
            TuneAVFeedbackBadge(feedback: stationFeedback, size: 22, fontSize: 10, borderOpacity: 0.82)
                .accessibilityLabel(stationFeedback.localizedState)
                .accessibilityIdentifier("stationRow.feedback.\(station.id)")
        }
    }

    private var currentStationOverlay: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .stroke(TuneAVTheme.highlight.opacity(0.42), lineWidth: 1)
            Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(isPlayingCurrentStation ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
        }
        .frame(width: StationCompactMetrics.playBadgeSize, height: StationCompactMetrics.playBadgeSize)
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            TuneAVSavedStationIcon(isSaved: isFavorite, size: 16)
                .frame(width: StationCompactMetrics.favoriteButtonSize, height: StationCompactMetrics.favoriteButtonSize)
                .background(isFavorite ? TuneAVTheme.highlight.opacity(0.14) : Color.white.opacity(0.72), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isFavorite ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle.opacity(0.65), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
        .accessibilityIdentifier("stationRow.favorite.\(station.id)")
    }

    private func stationQualityBadges(hasNowPlaying: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(compactStatusBadges(hasNowPlaying: hasNowPlaying), id: \.self) { badge in
                AVCompactStatusBadge(title: badge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactStatusBadges: [String] {
        compactStatusBadges(hasNowPlaying: reliableArtist != nil || reliableTitle != nil)
    }

    private func compactStatusBadges(hasNowPlaying: Bool) -> [String] {
        Array(station.userSignalBadges(
            hasNowPlaying: hasNowPlaying,
            isTemporarilyUnstable: audioPlayer.isTemporarilyUnstable(station)
        ).prefix(2))
    }

    private func playCompactStation() {
        if audioPlayer.isCurrent(station) {
            AVHaptics.perform(.primaryAction)
            audioPlayer.togglePlayback()
        } else {
            playAction()
        }
    }

    private func compactUniqueInsight(excluding lines: [String?]) -> String? {
        guard let insight = TuneAVText.normalizedValue(recommendationInsight) else {
            return nil
        }
        return compactUniqueLine(candidates: [insight], excluding: lines)
    }

    private func compactUniqueLine(candidates: [String?], excluding lines: [String?]) -> String? {
        let repeatedLines = lines.compactMap { TuneAVText.normalizedValue($0) }
        return candidates
            .compactMap { TuneAVText.normalizedValue($0) }
            .first { candidate in
                !repeatedLines.contains { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }
            }
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: StationCompactMetrics.artworkSize),
            style: .continuous
        )
    }

    private var reliableArtist: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackArtist : nowPlayingTrack?.artist
        guard let artist = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: station.name) else { return nil }
        return artist
    }

    private var reliableTitle: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackTitle : nowPlayingTrack?.title
        guard let title = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: station.name) else { return nil }
        return title
    }

    private var compactStationContext: String? {
        let country = compactCountryName.map { countryName in
            if let flag = station.flagEmoji {
                return "\(flag) \(countryName)"
            }
            return countryName
        }
        let language = TuneAVText.normalizedValue(station.language, excluding: Station.unknownDetailValues, locale: L10n.locale)
        let values = [country, language]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }

        guard !values.isEmpty else { return nil }
        return values.prefix(2).joined(separator: " · ")
    }

    private var compactCountryName: String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return TuneAVText.normalizedValue(station.country, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }
}
