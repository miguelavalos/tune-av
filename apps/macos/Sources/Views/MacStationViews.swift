import AVAviFoundation
import AppKit
import SwiftUI

struct MacStationCollectionView: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let title: String
    let stations: [Station]
    var emptyMessage: String = L10n.string("mac.stations.empty")

    private let columns = [
        GridItem(.adaptive(minimum: 258, maximum: 340), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                if stations.isEmpty {
                    ContentUnavailableView(emptyMessage, systemImage: "radio")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(stations) { station in
                            MacStationCard(station: station)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MacStationCard: View {
    let station: Station

    var body: some View {
        MacStationArtworkCard(station: station)
    }
}

struct MacStationArtworkCard: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.macStationPlaybackQueue) private var playbackQueue

    let station: Station

    private enum Metrics {
        static let cardHeight: CGFloat = 112
        static let artworkSize: CGFloat = 82
        static let favoriteButtonSize: CGFloat = 44
        static let playBadgeSize: CGFloat = 36
    }

    var body: some View {
        Button {
            model.openStationDetail(station, queue: effectiveQueue)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                artworkStack

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(primaryLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryLineColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(secondaryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        if let feedback = model.stationFeedback[station.id] {
                            Image(systemName: feedback.systemImage)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(TuneAVTheme.brandGraphite)
                                .frame(width: 20, height: 20)
                                .background(TuneAVTheme.highlight.opacity(0.16), in: Circle())
                        }
                        stationQualityBadges
                    }
                    .frame(height: 20, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: Metrics.cardHeight, maxHeight: Metrics.cardHeight, alignment: .topLeading)
            .background(TuneAVTheme.cardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
            }
            .shadow(color: TuneAVTheme.softShadow.opacity(0.08), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stationCard.\(station.id)")
    }

    private var artworkStack: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                playCompactStation()
            } label: {
                ZStack {
                    MacStationThumbnailView(
                        station: station,
                        size: Metrics.artworkSize,
                        textMode: .none,
                        animationOverlay: .none,
                        isAnimationActive: isPlayingCurrentStation
                    )

                    if isCurrentStationActive {
                        Color.white.opacity(0.18)
                            .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: Metrics.artworkSize), style: .continuous))
                    }

                    if isCurrentStationActive {
                        currentStationOverlay
                    }
                }
                .frame(width: Metrics.artworkSize, height: Metrics.artworkSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayingCurrentStation ? L10n.string("player.control.pause") : L10n.string("player.control.play"))

            favoriteButton
                .offset(x: 5, y: -5)
        }
        .frame(width: Metrics.artworkSize, height: Metrics.artworkSize)
    }

    private var currentStationOverlay: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .stroke(TuneAVTheme.highlight.opacity(0.28), lineWidth: 1)
                }

            Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(TuneAVTheme.brandBlack)
                .offset(x: isPlayingCurrentStation ? 0 : 1)
        }
        .frame(width: Metrics.playBadgeSize, height: Metrics.playBadgeSize)
    }

    private var favoriteButton: some View {
        Button {
            model.toggleFavorite(station)
        } label: {
            TuneAVSavedStationIcon(isSaved: model.isFavorite(station), size: 16, inactiveColor: TuneAVTheme.textSecondary)
                .frame(width: Metrics.favoriteButtonSize, height: Metrics.favoriteButtonSize)
                .background(model.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.16) : TuneAVTheme.cardSurface.opacity(0.92), in: Circle())
                .overlay {
                    Circle()
                        .stroke(model.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.3) : TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
    }

    private var stationQualityBadges: some View {
        HStack(spacing: 5) {
            ForEach(compactBadges.prefix(2), id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(TuneAVTheme.elevatedSurface.opacity(0.82), in: Capsule())
            }
        }
    }

    private var compactBadges: [String] {
        let tags = station.tagsList
            .compactMap(TuneAVMusicGenreCatalog.canonicalTag(for:))
            .map { L10n.genreLabel(for: $0).capitalized(with: L10n.locale) }
        if !tags.isEmpty {
            return Array(tags.prefix(2))
        }
        let language = station.language.trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? [] : [language]
    }

    private var primaryLine: String {
        if isCurrentStation, let displayLines = model.nowPlayingDisplayLines {
            return displayLines.trackTitleLine
        }
        if let feedback = model.stationFeedback[station.id] {
            return feedback.localizedState
        }
        return localizedCountryLine
    }

    private var secondaryLine: String {
        if isCurrentStation, let displayLines = model.nowPlayingDisplayLines {
            return displayLines.trackSupportingLine
        }
        if let detail = station.cardDetailText(
            preferCountryName: false,
            unknownValues: Station.unknownDetailValues,
            locale: L10n.locale
        ) {
            return detail
        }
        return compactBadges.first ?? station.language
    }

    private var localizedCountryLine: String {
        let country: String
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            country = L10n.countryName(for: countryCode)
        } else {
            country = station.country
        }
        return station.flagEmoji.map { "\($0) \(country)" } ?? country
    }

    private var primaryLineColor: Color {
        isCurrentStation && model.nowPlayingDisplayLines != nil ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9)
    }

    private var isCurrentStation: Bool {
        model.currentStation?.id == station.id
    }

    private var isCurrentStationActive: Bool {
        isCurrentStation && (model.isPlaying || model.playbackStatus.isLoading)
    }

    private var isPlayingCurrentStation: Bool {
        isCurrentStation && model.isPlaying
    }

    private var effectiveQueue: [Station] {
        playbackQueue.isEmpty ? [station] : playbackQueue
    }

    private func playCompactStation() {
        if isCurrentStation {
            model.togglePlayback()
        } else {
            model.play(station, queue: effectiveQueue)
        }
    }
}

struct MacStationThumbnailView: View {
    let station: Station
    let size: CGFloat
    var surfaceStyle: StationArtworkView.SurfaceStyle = .light
    var textMode: StationArtworkView.TextMode = .initials
    var animationOverlay: StationArtworkView.AnimationOverlay = .none
    var isAnimationActive = false

    private var cornerRadius: CGFloat {
        StationArtworkView.ArtworkStyle.cornerRadius(for: size)
    }

    var body: some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: surfaceStyle,
            textMode: textMode,
            animationOverlay: animationOverlay,
            isAnimationActive: isAnimationActive
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(thumbnailBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(thumbnailBorder, lineWidth: 1)
        }
        .shadow(color: thumbnailShadow, radius: size * 0.08, y: size * 0.03)
    }

    private var thumbnailBackground: Color {
        switch surfaceStyle {
        case .light:
            return Color.white
        case .dark:
            return TuneAVTheme.darkSurface
        }
    }

    private var thumbnailBorder: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.borderSubtle
        case .dark:
            return Color.white.opacity(0.08)
        }
    }

    private var thumbnailShadow: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.softShadow.opacity(0.08)
        case .dark:
            return TuneAVTheme.softShadow.opacity(0.18)
        }
    }
}

struct MacCompactStationCard: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.macStationPlaybackQueue) private var playbackQueue
    @State private var isShowingAviActions = false

    let station: Station

    private var isCurrentStationActive: Bool {
        model.currentStation?.id == station.id && (model.isPlaying || model.playbackStatus.isLoading)
    }

    private var primaryLine: String {
        if model.currentStation?.id == station.id, let displayLines = model.nowPlayingDisplayLines {
            return displayLines.trackTitleLine
        }
        return compactStationContext ?? L10n.string("shell.station.row.defaultDetail")
    }

    private var secondaryLine: String? {
        guard model.currentStation?.id == station.id, let displayLines = model.nowPlayingDisplayLines else {
            return nil
        }
        return TuneAVDisplayMetadata.normalized(displayLines.trackSupportingLine)
    }

    private var isPlayingCurrentStation: Bool {
        model.currentStation?.id == station.id && model.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.play(station, queue: playbackQueue.isEmpty ? [station] : playbackQueue)
            } label: {
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(primaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                    .lineLimit(1)

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    if let feedback = model.stationFeedback[station.id] {
                        Image(systemName: feedback.systemImage)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TuneAVTheme.brandGraphite)
                            .frame(width: 22, height: 22)
                            .background(TuneAVTheme.highlight.opacity(0.16), in: Circle())
                    }
                    stationQualityBadges
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture {
                model.openStationDetail(station, queue: playbackQueue)
            }

            Button {
                model.toggleFavorite(station)
            } label: {
                TuneAVSavedStationIcon(isSaved: model.isFavorite(station), size: 16, inactiveColor: TuneAVTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TuneAVTheme.cardSurface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))

            aviActionsMenu
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TuneAVTheme.cardSurface.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.3) : TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            model.openStationDetail(station, queue: playbackQueue)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stationRow.\(station.id)")
    }

    private var stationQualityBadges: some View {
        HStack(spacing: 5) {
            ForEach(compactBadges.prefix(2), id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(TuneAVTheme.mutedSurface, in: Capsule())
            }
        }
    }

    private var aviActionsMenu: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                isShowingAviActions.toggle()
            }
        } label: {
            AVAviAvatarBadge(backgroundStyle: .muted) {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(.plain)
        .help(L10n.string("shell.avi.actions.askShort"))
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
            TuneAviPopoverActionsPanel(close: closeAviActions) {
                AVAviPanelOptionButton(
                    title: model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save"),
                    systemImage: model.isFavorite(station) ? "bookmark.slash" : "bookmark"
                ) {
                    model.toggleFavorite(station)
                    closeAviActions()
                }

                AVAviPanelOptionButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "info.circle") {
                    model.openStationDetail(station, queue: playbackQueue)
                    closeAviActions()
                }

                if let homepageURL = station.resolvedHomepageURL {
                    AVAviPanelOptionButton(title: L10n.string("player.menu.openWebsite"), systemImage: "safari") {
                        NSWorkspace.shared.open(homepageURL)
                        closeAviActions()
                    }
                }
            }
            .frame(width: 278)
        }
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingAviActions = false
        }
    }

    private var compactBadges: [String] {
        var badges = station.tagsList.prefix(2).map { L10n.genreLabel(for: $0) }
        if badges.isEmpty, !station.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            badges.append(station.language)
        }
        return badges
    }

    private var compactStationContext: String? {
        let countryName: String?
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            countryName = L10n.countryName(for: countryCode)
        } else {
            countryName = TuneAVText.normalizedValue(station.country, excluding: Station.unknownDetailValues, locale: L10n.locale)
        }
        let country = countryName.map { name in
            station.flagEmoji.map { "\($0) \(name)" } ?? name
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
}

struct MacNowPlayingBar: View {
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        HStack(spacing: 14) {
            if let currentStation = model.currentStation {
                MacStationThumbnailView(station: currentStation, size: 42, textMode: .none)
            } else {
                Image("AviFooterIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.nowPlayingDisplayLines?.trackTitleLine ?? model.currentStation?.name ?? L10n.string("app.name"))
                    .font(.headline)
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(model.nowPlayingDisplayLines?.trackSupportingLine ?? model.currentStation?.country ?? L10n.string("home.hero.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)

                if let statusLine = nowPlayingStatusLine {
                    Text(statusLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusLineColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                model.playPreviousInQueue()
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canCyclePlaybackQueue)

            Button {
                model.togglePlayback()
            } label: {
                if model.playbackStatus.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.playNextInQueue()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canCyclePlaybackQueue)

            Button {
                model.selectedSection = .home
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TuneAVTheme.borderSubtle)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var nowPlayingStatusLine: String? {
        switch model.playbackStatus {
        case .idle:
            return nil
        case .loading:
            return L10n.string("audio.status.loading")
        case .playing:
            return L10n.string("shell.status.live")
        case .paused:
            return L10n.string("audio.status.paused")
        case let .failed(message):
            return message
        }
    }

    private var statusLineColor: Color {
        if model.playbackStatus.failureMessage != nil {
            return .red
        }
        if model.isPlaying {
            return TuneAVTheme.highlight
        }
        return TuneAVTheme.textSecondary
    }
}
