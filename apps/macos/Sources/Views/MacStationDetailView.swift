import AppKit
import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct MacStationDetailView: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.openURL) private var openURL
    @State private var selectedSection: MacStationDetailSection
    @State private var copiedShareText = false

    let station: Station
    let queue: [Station]
    let initialSection: MacStationDetailSection

    init(station: Station, queue: [Station], initialSection: MacStationDetailSection = .about) {
        self.station = station
        self.queue = queue
        self.initialSection = initialSection
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionPicker

                    switch selectedSection {
                    case .about:
                        overviewSection
                        metadataSection
                        tagsSection
                        stationGuideSection
                        discoverySection
                    case .history:
                        historySection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 640, idealHeight: 760)
        .background(TuneAVTheme.shellBackground)
        .onAppear {
            selectedSection = initialSection
        }
        .onChange(of: initialSection) { _, newValue in
            selectedSection = newValue
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            MacStationThumbnailView(station: station, size: 64, textMode: .none)

            VStack(alignment: .leading, spacing: 7) {
                Text(station.name)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(station.primaryDetailLine.isEmpty ? station.shortMeta : station.primaryDetailLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if isCurrentStation {
                        MacStationDetailBadge(
                            title: L10n.string(isPlayingStation ? "player.header.nowPlaying" : "player.control.pause"),
                            systemImage: isPlayingStation ? "waveform" : "pause.fill",
                            isHighlighted: true
                        )
                    }

                    if let code = TuneAVCountry.sanitizedCode(station.countryCode) {
                        MacStationDetailBadge(
                            title: [TuneAVCountry(code: code, name: code).flag, L10n.countryName(for: code)]
                                .compactMap { $0 }
                                .joined(separator: " "),
                            systemImage: nil,
                            isHighlighted: false
                        )
                    }
                }
            }

            Spacer()

            Button(action: { model.closeStationDetail() }) {
                Label(L10n.string("common.back"), systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(TuneAVTheme.borderSubtle.opacity(0.88), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            AVAviPrimaryActionButton(
                title: isCurrentStation ? L10n.string("player.header.nowPlaying") : L10n.string("shell.stationDetail.playRadio"),
                systemImage: isPlayingStation ? "pause.fill" : "play.fill",
                accessibilityIdentifier: "station.detail.play"
            ) {
                toggleStationPlayback()
            }
            .frame(width: 170)

            AVAppShellIconButton(
                systemName: model.isFavorite(station) ? "bookmark.slash.fill" : "bookmark",
                accessibilityLabel: stationSaveActionTitle,
                accessibilityIdentifier: "station.detail.save",
                isSelected: model.isFavorite(station)
            ) {
                model.toggleFavorite(station)
            }

            AVAppShellIconButton(
                systemName: copiedShareText ? "checkmark" : "square.and.arrow.up",
                accessibilityLabel: copiedShareText ? L10n.string("common.done") : L10n.string("common.share"),
                accessibilityIdentifier: "station.detail.share",
                isSelected: copiedShareText
            ) {
                shareStation()
            }

            AVAppShellIconButton(
                systemName: "xmark",
                accessibilityLabel: L10n.string("common.back"),
                accessibilityIdentifier: "station.detail.close"
            ) {
                model.closeStationDetail()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(TuneAVTheme.elevatedSurface.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TuneAVTheme.borderSubtle.opacity(0.78))
                .frame(height: 1)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            sectionButton(.about, title: L10n.string("shell.stationDetail.section.about"), systemImage: "info.circle.fill", badge: nil)
            sectionButton(.history, title: L10n.string("shell.stationDetail.tab.history"), systemImage: "clock.arrow.circlepath", badge: stationDiscoveries.isEmpty ? nil : "\(stationDiscoveries.count)")
        }
        .padding(4)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("mac.stationDetail.sections")
    }

    private func sectionButton(_ section: MacStationDetailSection, title: String, systemImage: String, badge: String?) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
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
                        .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
                }
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.elevatedSurface.opacity(0.72))
                    )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle.opacity(0.78), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var overviewSection: some View {
        MacStationDetailCard(title: L10n.string("shell.stationDetail.section.about")) {
            if let summary = TuneAVText.normalizedValue(station.editorial?.summary) {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(TuneAVTheme.textPrimary)
            } else {
                Text(station.primaryDetailLine.isEmpty ? station.shortMeta : station.primaryDetailLine)
                    .font(.body)
                    .foregroundStyle(TuneAVTheme.textPrimary)
            }

            HStack(spacing: 10) {
                if let homepageURL = station.resolvedHomepageURL {
                    MacStationDetailTextButton(title: L10n.string("player.menu.openWebsite"), systemImage: "safari") {
                        openURL(homepageURL)
                    }
                }

                MacStationDetailTextButton(title: copiedShareText ? L10n.string("common.done") : L10n.string("common.share"), systemImage: copiedShareText ? "checkmark" : "square.and.arrow.up") {
                    shareStation()
                }
            }
        }
    }

    @ViewBuilder
    private var discoverySection: some View {
        if let profile = station.editorial?.discoveryProfile {
            MacStationDetailCard(title: L10n.string("shell.stationDetail.discovery.bestFor")) {
                StationInfoDiscoverySnapshot(profile: profile)

                if !profile.bestFor.isEmpty {
                    Text(L10n.string("shell.stationDetail.discovery.bestFor"))
                        .font(.headline)
                    MacStationDetailTagCloud(tags: profile.bestFor)
                }
            }
        }
    }

    private var metadataSection: some View {
        MacStationDetailCard(title: L10n.string("shell.stationDetail.tab.profile")) {
            MacStationDetailField(title: L10n.string("shell.stationDetail.field.country"), value: stationCountry)
            MacStationDetailField(title: L10n.string("shell.stationDetail.field.language"), value: station.language)
            if let state = TuneAVText.normalizedValue(station.state) {
                MacStationDetailField(title: L10n.string("shell.stationDetail.field.state"), value: state)
            }
            if let code = TuneAVCountry.sanitizedCode(station.countryCode) {
                MacStationDetailField(title: L10n.string("shell.stationDetail.field.code"), value: code)
            }
            if let homepage = station.resolvedHomepageURL?.absoluteString {
                MacStationDetailField(title: L10n.string("shell.stationDetail.field.website"), value: homepage)
            }
            if let lastCheck = TuneAVText.normalizedValue(station.lastCheckOKAt) {
                MacStationDetailField(title: L10n.string("shell.stationDetail.field.lastCheck"), value: lastCheck)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if stationDiscoveries.isEmpty {
            MacStationDetailCard(title: L10n.string("shell.stationDetail.tab.history")) {
                Text(L10n.string("shell.stationDetail.history.empty"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }
        } else {
            MacStationDetailCard(title: L10n.string("shell.stationDetail.tab.history")) {
                Text(L10n.string("shell.stationDetail.history.copy"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                VStack(spacing: 10) {
                    ForEach(stationDiscoveries) { discovery in
                        MacDiscoveryCard(
                            discovery: discovery,
                            showsSaveButton: false,
                            openTrackInfo: { model.openMusicTrackDetail(discovery) },
                            openArtistInfo: { model.openMusicArtistDetail(discovery.artistDisplayText) },
                            openStationInfo: { model.openStationDetail(station, queue: queue) },
                            hideAction: nil,
                            removeAction: nil,
                            openYouTube: { openDiscoverySearch(discovery, destination: .youtube) },
                            openLyrics: { openDiscoverySearch(discovery, destination: .web, suffix: "lyrics") },
                            openAppleMusic: { openDiscoverySearch(discovery, destination: .appleMusic) },
                            openSpotify: { openDiscoverySearch(discovery, destination: .spotify) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let tags = stationDetailTags
        if !tags.isEmpty {
            MacStationDetailCard(title: L10n.string("shell.stationDetail.section.tags")) {
                MacStationDetailTagCloud(tags: tags)
            }
        }
    }

    @ViewBuilder
    private var stationGuideSection: some View {
        if let editorial = station.editorial {
            let guideTags = stationGuideTags(for: editorial)
            if !guideTags.isEmpty || !editorial.confidence.isEmpty || !editorial.primaryFormat.isEmpty {
                MacStationDetailCard(title: L10n.string("shell.stationDetail.section.editorial")) {
                    HStack(spacing: 18) {
                        if !editorial.confidence.isEmpty {
                            MacStationDetailInlineValue(
                                title: L10n.string("shell.stationDetail.editorial.confidence", editorial.confidence),
                                value: editorial.confidence
                            )
                        }

                        if !editorial.primaryFormat.isEmpty {
                            MacStationDetailInlineValue(
                                title: L10n.string("shell.stationDetail.discovery.music"),
                                value: L10n.genreLabel(for: editorial.primaryFormat)
                            )
                        }
                    }

                    if !guideTags.isEmpty {
                        MacStationDetailTagCloud(tags: guideTags)
                    }
                }
            }
        }
    }

    private var stationDetailTags: [String] {
        var tags = station.tagsList.map(L10n.genreLabel(for:))
        tags.append(contentsOf: station.popularityBadges)
        tags.append(contentsOf: station.technicalBadges)
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
    }

    private func stationGuideTags(for editorial: StationEditorial) -> [String] {
        var tags = editorial.programming.map(L10n.genreLabel(for:))
        tags.append(contentsOf: editorial.secondaryFormats.map(L10n.genreLabel(for:)))
        tags.append(contentsOf: editorial.discoveryProfile?.bestFor ?? [])
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
    }

    private var stationCountry: String {
        if let code = TuneAVCountry.sanitizedCode(station.countryCode) {
            let flag = TuneAVCountry(code: code, name: code).flag.map { "\($0) " } ?? ""
            return flag + L10n.countryName(for: code)
        }
        return station.country
    }

    private var isCurrentStation: Bool {
        model.currentStation?.id == station.id
    }

    private var isPlayingStation: Bool {
        isCurrentStation && model.isPlaying
    }

    private var stationSaveActionTitle: String {
        model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save")
    }

    private var stationDiscoveries: [MacDiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(model.discoveredTracks)
            .filter { $0.stationID == station.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func toggleStationPlayback() {
        if isCurrentStation {
            model.togglePlayback()
        } else {
            model.play(station, queue: queue)
        }
    }

    private func shareStation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(station.shareText, forType: .string)
        copiedShareText = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedShareText = false
        }
    }

    private func openDiscoverySearch(_ discovery: MacDiscoveredTrack, destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        let query = [discovery.searchQuery, suffix].compactMap { $0 }.joined(separator: " ")
        guard model.canPerformPremiumAviSearch(destination: destination, suffix: suffix, usageKey: query) else { return }
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        openURL(url)
    }
}

enum MacStationDetailSection: String, CaseIterable {
    case about
    case history
}

private struct MacStationDiscoverySnapshot: View {
    let profile: StationDiscoveryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("shell.stationDetail.discovery.score"))
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(discoveryScoreLabel)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                }

                Spacer()

                Text("\(profile.musicDiscoveryScore)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TuneAVTheme.highlight)
            }

            VStack(spacing: 8) {
                MacStationMetricRow(title: L10n.string("shell.stationDetail.discovery.music"), level: profile.musicLevel)
                MacStationMetricRow(title: L10n.string("shell.stationDetail.discovery.speech"), level: profile.speechLevel)
                MacStationMetricRow(title: L10n.string("shell.stationDetail.discovery.news"), level: profile.newsLevel)
                MacStationMetricRow(title: L10n.string("shell.stationDetail.discovery.sports"), level: profile.sportsLevel)
                MacStationMetricRow(title: L10n.string("shell.stationDetail.discovery.ads"), level: profile.adLoad)
            }
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }

    private var discoveryScoreLabel: String {
        switch profile.musicDiscoveryScore {
        case 75...100:
            return L10n.string("shell.stationDetail.discovery.scoreHigh")
        case 40..<75:
            return L10n.string("shell.stationDetail.discovery.scoreMedium")
        default:
            return L10n.string("shell.stationDetail.discovery.scoreLow")
        }
    }
}

private struct MacStationMetricRow: View {
    let title: String
    let level: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 74, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TuneAVTheme.elevatedSurface)

                    Capsule()
                        .fill(metricColor.opacity(0.84))
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 8)

            Text(localizedLevel)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var progress: Double {
        switch level {
        case "high": return 1
        case "medium": return 0.6
        case "low": return 0.28
        default: return 0.12
        }
    }

    private var metricColor: Color {
        switch level {
        case "high": return TuneAVTheme.highlight
        case "medium": return TuneAVTheme.highlight.opacity(0.72)
        case "low": return TuneAVTheme.textSecondary.opacity(0.52)
        default: return TuneAVTheme.borderStrong
        }
    }

    private var localizedLevel: String {
        switch level {
        case "high": return L10n.string("shell.stationDetail.discovery.level.high")
        case "medium": return L10n.string("shell.stationDetail.discovery.level.medium")
        case "low": return L10n.string("shell.stationDetail.discovery.level.low")
        default: return L10n.string("shell.stationDetail.discovery.level.unknown")
        }
    }
}

private struct MacStationDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
    }
}

private struct MacStationDetailField: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .textCase(.uppercase)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}

private struct MacStationDetailInlineValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacStationDetailTagCloud: View {
    let tags: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 180), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.system(size: 11, weight: .black))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(TuneAVTheme.mutedSurface, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
                    }
            }
        }
    }
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }
}

private struct MacStationDetailBadge: View {
    let title: String
    let systemImage: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(isHighlighted ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((isHighlighted ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(isHighlighted ? TuneAVTheme.highlight.opacity(0.32) : TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
        }
    }
}

struct MacStationDetailPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MacStationDetailTextButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.88), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct MacStationDetailIconButton<LabelContent: View>: View {
    let help: String
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                .frame(width: 38, height: 36)
                .background(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.35) : TuneAVTheme.borderSubtle.opacity(0.88), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MacStationHistoryRow: View {
    let discovery: MacDiscoveredTrack

    var body: some View {
        HStack(spacing: 12) {
            MacStationHistoryArtwork(discovery: discovery)

            VStack(alignment: .leading, spacing: 3) {
                Text(discovery.title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(discovery.artistDisplayText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(discovery.playedAt, style: .date)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
        .padding(10)
        .background(TuneAVTheme.elevatedSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct MacStationHistoryArtwork: View {
    let discovery: MacDiscoveredTrack

    var body: some View {
        Group {
            if let url = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
                TuneAVRemoteArtworkImage(url: url, size: 42, scale: NSScreen.main?.backingScaleFactor ?? 2) {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 42), style: .continuous))
        .background(Color.white, in: RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 42), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 42), style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Image(systemName: "music.note")
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(TuneAVTheme.highlight)
            .frame(width: 42, height: 42)
            .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
