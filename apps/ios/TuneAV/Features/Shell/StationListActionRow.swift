import AVAviFoundation
import AVHaptics
import SwiftUI

struct StationListActionRow: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let isFavorite: Bool
    let nowPlayingTrack: NowPlayingTrack?
    var stationFeedback: TuneAVStationFeedback? = nil
    let toggleFavorite: () -> Void
    let playAction: () -> Void
    let openWebsiteAction: () -> Void
    let detailsAction: () -> Void
    @State private var isShowingAviActions = false

    private var isPlayingCurrentStation: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isPlaying
    }

    private var isCurrentStationActive: Bool {
        audioPlayer.isCurrent(station) && (audioPlayer.isPlaying || audioPlayer.isLoading)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playStation) {
                ZStack {
                    Circle()
                        .fill(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.highlight.opacity(0.14))

                    Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(isCurrentStationActive ? TuneAVTheme.brandBlack : TuneAVTheme.highlight)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayingCurrentStation ? L10n.string("player.control.pause") : L10n.string("player.control.play"))
            .accessibilityIdentifier("stationRow.play.\(station.id)")

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(primaryDetailLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryDetailIsNowPlaying ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                HStack(spacing: 6) {
                    feedbackBadgeIfNeeded
                    stationQualityBadges
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)

            aviActionsMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TuneAVTheme.cardSurface.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.3) : TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: detailsAction)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stationRow.\(station.id)")
    }

    @ViewBuilder
    private var feedbackBadgeIfNeeded: some View {
        if let stationFeedback {
            StationFeedbackBadge(feedback: stationFeedback, size: 20, fontSize: 9)
                .accessibilityLabel(stationFeedback.localizedState)
                .accessibilityIdentifier("stationRow.feedback.\(station.id)")
        }
    }

    private var stationQualityBadges: some View {
        HStack(spacing: 5) {
            ForEach(station.userSignalBadges(hasNowPlaying: primaryDetailIsNowPlaying, isTemporarilyUnstable: audioPlayer.isTemporarilyUnstable(station)), id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule())
            }
        }
    }

    private var aviActionsMenu: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                isShowingAviActions.toggle()
            }
        } label: {
            AVAviAvatarBadge(backgroundStyle: .elevated) {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
        .accessibilityIdentifier("stationRow.aviActions.\(station.id)")
        .popover(
            isPresented: Binding(
                get: { isShowingAviActions },
                set: { if !$0 { closeAviActions() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            aviActionsPanel
                .frame(width: 278)
                .presentationCompactAdaptation(.none)
        }
    }

    private var aviActionsPanel: some View {
        AviRowActionsPanel(close: closeAviActions) {
            AviRowActionButton(
                title: isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"),
                systemImage: isFavorite ? "bookmark.slash" : "bookmark"
            ) {
                toggleFavorite()
                closeAviActions()
            }
            AviRowActionButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "info.circle") {
                detailsAction()
                closeAviActions()
            }
            if station.resolvedHomepageURL != nil {
                AviRowActionButton(title: L10n.string("player.menu.openWebsite"), systemImage: "safari") {
                    openWebsiteAction()
                    closeAviActions()
                }
            }
        }
    }

    private func playStation() {
        if audioPlayer.isCurrent(station) {
            AVHaptics.perform(.playbackToggle)
            audioPlayer.togglePlayback()
        } else {
            playAction()
        }
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingAviActions = false
        }
    }

    private var primaryDetailIsNowPlaying: Bool {
        reliableArtist != nil || reliableTitle != nil
    }

    private var primaryDetailLine: String {
        if let reliableArtist, let reliableTitle {
            return "\(reliableArtist) · \(reliableTitle)"
        }

        if let reliableArtist {
            return reliableArtist
        }

        if let reliableTitle {
            return reliableTitle
        }

        return compactStationContext ?? L10n.string("shell.station.row.defaultDetail")
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
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

struct AviRowActionsPanel<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        AVAviPopoverActionPanel(
            title: L10n.string("shell.avi.actions.ask"),
            pageLabel: L10n.string("shell.avi.actions.page", 1, 1),
            previousAccessibilityLabel: L10n.string("shell.avi.actions.previousOptions"),
            nextAccessibilityLabel: L10n.string("shell.avi.actions.moreOptions"),
            closeAccessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
            close: close
        ) {
            content()
        }
    }
}

struct AviRowActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        AVAviPanelOptionButton(title: title, systemImage: systemImage, role: role, action: action)
    }
}
