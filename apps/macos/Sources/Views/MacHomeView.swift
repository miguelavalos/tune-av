import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct MacHomeView: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let openSearchTag: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let station = model.heroStation {
                    MacHomeHeroCard(station: station)
                }

                if !model.moodGenreSuggestions.isEmpty {
                    MacHomeMoodGenreDesk(tags: model.moodGenreSuggestions, selectTag: openSearchTag)
                }

                if !model.aviPickStations.isEmpty {
                    MacHomeStationSection(
                        title: L10n.string("shell.home.aviPicks.title"),
                        subtitle: L10n.string("shell.home.aviPicks.subtitle"),
                        stations: model.aviPickStations,
                        fullStations: model.allAviPickStations,
                        listID: "aviPicks"
                    )
                }

                if !model.aroundYouStations.isEmpty {
                    MacHomeStationSection(
                        title: L10n.string("shell.home.aroundYou.title"),
                        subtitle: L10n.string("shell.home.aroundYou.subtitle"),
                        stations: model.aroundYouStations,
                        fullStations: model.allAroundYouStations,
                        listID: "aroundYou"
                    )
                }

                if !model.recentAndFavoriteStations.isEmpty {
                    MacHomeStationSection(
                        title: L10n.string("shell.home.recentsFavorites.title"),
                        subtitle: L10n.string("shell.home.recentsFavorites.subtitle"),
                        stations: Array(model.recentAndFavoriteStations.prefix(8)),
                        fullStations: model.recentAndFavoriteStations,
                        listID: "recentsFavorites"
                    )
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("shell.home.title"))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(L10n.string("shell.home.subtitle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MacHomeHeroCard: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.colorScheme) private var colorScheme

    let station: Station

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    MacHomeSignalPill(title: heroLabel)

                    if model.currentStation?.id == station.id {
                        MacHomeLiveStatePill(isPlaying: model.isPlaying, isLoading: model.playbackStatus.isLoading)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(station.name)
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(heroTitleColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if let stationFeedback {
                        TuneAVFeedbackBadge(feedback: stationFeedback, size: 24, fontSize: 11, borderOpacity: 0.82)
                            .accessibilityLabel(stationFeedback.localizedState)
                    }

                    Text(stationContextLine)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(heroSecondaryColor)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button {
                        model.play(station, queue: [station] + model.aviPickStations + model.aroundYouStations)
                    } label: {
                        Image(systemName: model.isPlaying && model.currentStation?.id == station.id ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(TuneAVTheme.brandBlack)
                            .frame(width: 54, height: 54)
                            .background(TuneAVTheme.highlight, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isPlaying && model.currentStation?.id == station.id ? L10n.string("player.control.pause") : L10n.string("shell.featured.play"))
                    .accessibilityIdentifier("home.hero.play")

                    Button {
                        model.toggleFavorite(station)
                    } label: {
                        TuneAVSavedStationIcon(isSaved: model.isFavorite(station), size: 18, inactiveColor: heroControlIconColor)
                            .frame(width: 48, height: 48)
                            .background(
                                model.isFavorite(station) ? TuneAVTheme.highlight.opacity(colorScheme == .dark ? 0.28 : 0.18) : heroControlSurface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(model.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.34) : heroControlStroke, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
                    .accessibilityIdentifier("home.hero.favorite")

                    Button {
                        model.openStationDetail(station, queue: [station] + model.aviPickStations + model.aroundYouStations)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(heroControlIconColor)
                            .frame(width: 48, height: 48)
                            .background(heroControlSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(heroControlStroke, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("common.more"))
                    .accessibilityIdentifier("home.hero.details")
                }

                MacAviCompactFeedbackControl(
                    feedbackIdentity: "station:\(station.id)",
                    selectedFeedback: stationFeedback,
                    selectFeedback: { feedback in
                        let nextFeedback = stationFeedback == feedback ? nil : feedback
                        model.setFeedback(nextFeedback, for: station)
                    }
                )
                .accessibilityIdentifier("home.hero.feedback")
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            MacHomeHeroArtwork(station: station)
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 282, alignment: .leading)
        .background(heroBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(heroBorderColor, lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 18, y: 8)
    }

    private var stationFeedback: TuneAVStationFeedback? {
        model.stationFeedback[station.id]
    }

    private var heroLabel: String {
        if model.currentStation?.id == station.id {
            return L10n.string("shell.liveNow.title").uppercased(with: L10n.locale)
        }
        if model.recentStations.first?.id == station.id {
            return L10n.string("shell.home.featured.continueListening").uppercased(with: L10n.locale)
        }
        return L10n.string("shell.home.featured.popular").uppercased(with: L10n.locale)
    }

    private var stationContextLine: String {
        let country = station.flagEmoji.map { "\($0) \(localizedCountry)" } ?? localizedCountry
        let values = [country, station.language]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.joined(separator: " · ")
    }

    private var localizedCountry: String {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }
        return station.country
    }

    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return ZStack(alignment: .bottomTrailing) {
            MacStationThumbnailView(station: station, size: 220, textMode: .none)
                .scaleEffect(1.18)
                .opacity(colorScheme == .dark ? 0.16 : 0.18)
                .blur(radius: 1.8)
                .offset(x: -84, y: 52)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .clipShape(shape)

            shape
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.13, green: 0.16, blue: 0.14), Color(red: 0.09, green: 0.11, blue: 0.10)]
                            : [Color(red: 0.99, green: 0.97, blue: 0.91), Color(red: 0.96, green: 0.94, blue: 0.87)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(colorScheme == .dark ? 0.96 : 0.9)

            ZStack(alignment: .bottomTrailing) {
                Image("AviOnboardingHeroStatic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250)
                    .opacity(colorScheme == .dark ? 0.1 : 0.16)
                    .offset(x: 56, y: 34)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HomeDeskSketchBackdrop()
                    .foregroundStyle(TuneAVTheme.highlight.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .padding(.bottom, 112)
                    .padding(.trailing, 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
        }
        .clipShape(shape)
    }

    private var heroTitleColor: Color {
        colorScheme == .dark ? TuneAVTheme.textPrimary : TuneAVTheme.brandGraphite
    }

    private var heroSecondaryColor: Color {
        colorScheme == .dark ? TuneAVTheme.textSecondary : TuneAVTheme.neutral600
    }

    private var heroControlSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.74)
    }

    private var heroControlIconColor: Color {
        colorScheme == .dark ? TuneAVTheme.textPrimary : TuneAVTheme.brandGraphite
    }

    private var heroControlStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : TuneAVTheme.brandGraphite.opacity(0.12)
    }

    private var heroBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : TuneAVTheme.brandGraphite.opacity(0.12)
    }
}

private struct MacHomeHeroArtwork: View {
    let station: Station

    var body: some View {
        ZStack {
            Circle()
                .fill(TuneAVTheme.highlight.opacity(0.12))
                .frame(width: 238, height: 238)

            MacStationThumbnailView(station: station, size: 176, textMode: .none)
                .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 22, y: 10)
        }
        .frame(width: 260, height: 220)
        .accessibilityHidden(true)
    }
}

private struct MacHomeMoodGenreDesk: View {
    let tags: [MacHomeMoodGenreSuggestion]
    let selectTag: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacHomeSectionHeader(
                title: L10n.string("shell.home.moodsGenres.title"),
                subtitle: L10n.string("shell.home.moodsGenres.subtitle")
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { suggestion in
                    Button {
                        selectTag(suggestion.tag)
                    } label: {
                        Label(suggestion.title, systemImage: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(TuneAVTheme.elevatedSurface, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.moodGenre.\(suggestion.tag)")
                }
            }
        }
    }
}

private struct MacHomeStationSection: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let title: String
    let subtitle: String
    let stations: [Station]
    let fullStations: [Station]
    let listID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                MacHomeSectionHeader(title: title, subtitle: subtitle)

                Spacer(minLength: 12)

                Button {
                    model.openHomeStationList(
                        id: listID,
                        title: title,
                        subtitle: subtitle,
                        stations: fullStations.isEmpty ? stations : fullStations
                    )
                } label: {
                    Label(L10n.string("common.seeAll"), systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TuneAVTheme.highlight)
                .accessibilityIdentifier("home.section.\(listID).seeAll")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(stations) { station in
                        MacHomeStationCard(station: station)
                            .frame(width: 258, height: 112)
                            .environment(\.macStationPlaybackQueue, stations)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .accessibilityIdentifier("home.section.\(listID)")
    }
}

private struct MacHomeStationCard: View {
    let station: Station

    var body: some View {
        MacStationArtworkCard(station: station)
            .accessibilityIdentifier("home.stationCard.\(station.id)")
    }
}

private struct MacHomeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacHomeStationListPage: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let route: MacHomeStationListRoute

    private let columns = [
        GridItem(.adaptive(minimum: 258, maximum: 340), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        model.homeStationListRoute = nil
                    } label: {
                        Label(L10n.string("common.back"), systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TuneAVTheme.textPrimary)

                    Spacer()
                }

                MacHomeSectionHeader(title: route.title, subtitle: route.subtitle)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(route.stations) { station in
                        MacStationArtworkCard(station: station)
                            .frame(height: 112)
                            .environment(\.macStationPlaybackQueue, route.stations)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("home.stationList.\(route.id)")
    }
}

private struct MacHomeSignalPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(TuneAVTheme.brandGraphite)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.62), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct MacHomeLiveStatePill: View {
    let isPlaying: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(TuneAVTheme.highlight.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
    }

    private var title: String {
        if isLoading {
            return L10n.string("audio.status.loading").uppercased(with: L10n.locale)
        }
        if isPlaying {
            return L10n.string("audio.status.playing").uppercased(with: L10n.locale)
        }
        return L10n.string("shell.status.live").uppercased(with: L10n.locale)
    }
}

private struct HomeDeskSketchBackdrop: View {
    var body: some View {
        ZStack {
            ForEach([42.0, 72.0, 104.0], id: \.self) { size in
                Circle()
                    .stroke(lineWidth: 1.2)
                    .frame(width: size, height: size)
            }

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .light))
                .offset(x: -36, y: 34)
        }
        .frame(width: 126, height: 126)
    }
}

struct TuneAVFeedbackBadge: View {
    let feedback: TuneAVStationFeedback
    var size: CGFloat = 22
    var fontSize: CGFloat?
    var borderOpacity: Double = 0.78

    var body: some View {
        AVFeedbackStatusBadge(
            systemImage: feedback.systemImage,
            accessibilityLabel: feedback.localizedState,
            isHighlighted: feedback == .liked,
            size: size,
            fontSize: fontSize,
            borderOpacity: borderOpacity
        )
    }
}

private struct MacAviCompactFeedbackControl: View {
    var feedbackIdentity: String = "aviFeedback"
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TuneAVStationFeedback.displayOrder, id: \.self) { feedback in
                AVAviCompactFeedbackButton(
                    systemImage: feedback.systemImage,
                    accessibilityLabel: feedback.localizedState,
                    accessibilityIdentifier: "avi.recommendation.feedback.\(feedback.rawValue)"
                ) {
                    selectFeedback(feedback)
                }
            }
        }
        .frame(height: 30)
        .opacity(selectedFeedback == nil ? 1 : 0)
        .disabled(selectedFeedback != nil)
        .accessibilityHidden(selectedFeedback != nil)
        .id(feedbackIdentity)
        .accessibilityIdentifier("avi.recommendation.feedback")
    }
}
