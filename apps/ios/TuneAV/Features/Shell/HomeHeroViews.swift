import SwiftUI

struct HomeTuningDeskHero: View {
    @Environment(\.colorScheme) private var colorScheme

    let station: Station
    let presentation: HomeStationPresentation
    let isFavorite: Bool
    let isCurrentStation: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let stationFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let feedbackAction: (TuneAVStationFeedback) -> Void
    let detailsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroHeader

            VStack(alignment: .leading, spacing: 14) {
                stationText
                    .layoutPriority(1)

                deskControls

                AviCompactFeedbackControl(
                    feedbackIdentity: "station:\(station.id)",
                    selectedFeedback: stationFeedback,
                    selectFeedback: feedbackAction,
                    clearFeedback: {
                        if let stationFeedback {
                            feedbackAction(stationFeedback)
                        }
                    }
                )
                .accessibilityIdentifier("home.hero.feedback")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture(perform: detailsAction)
        .accessibilityElement(children: .contain)
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            HomeDeskSignalPill(title: presentation.label)

            if isCurrentStation {
                HomeLiveStatePill(isPlaying: isPlaying, isLoading: isLoading)
            }

            Spacer(minLength: 8)

            if presentation.tier == .rich {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(9)
                    .background(Color.white.opacity(0.62), in: Circle())
                    .accessibilityHidden(true)
            }
        }
    }

    private var stationText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 29, weight: .black))
                    .foregroundStyle(heroTitleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let stationFeedback {
                    StationFeedbackBadge(feedback: stationFeedback, size: 24, fontSize: 11, borderWidth: 1)
                        .accessibilityLabel(stationFeedback.localizedState)
                }
            }

            if let primaryLine = presentation.primaryLine {
                Text(primaryLine)
                    .font(.system(size: presentation.tier == .rich ? 15 : 14, weight: .semibold))
                    .foregroundStyle(heroSecondaryColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let secondaryLine = presentation.secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(heroSecondaryColor.opacity(0.78))
                    .lineLimit(1)
            }

            if !presentation.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(presentation.badges, id: \.self) { badge in
                        HomeDeskBadge(title: badge)
                    }
                }
            }
        }
    }

    private var deskControls: some View {
        HStack(spacing: 10) {
            Button(action: playAction) {
                Image(systemName: playIconName)
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 56, height: 56)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playTitle)

            Button(action: favoriteAction) {
                TuneAVSavedStationIcon(isSaved: isFavorite, size: 18)
                    .frame(width: 50, height: 50)
                    .background(
                        isFavorite ? TuneAVTheme.highlight.opacity(colorScheme == .dark ? 0.28 : 0.18) : heroControlSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isFavorite ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.brandGraphite.opacity(0.12), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
            .accessibilityIdentifier("home.hero.favorite.\(station.id)")

            Button(action: detailsAction) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(heroControlIconColor)
                    .frame(width: 50, height: 50)
                    .background(heroControlSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(heroControlStroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.more"))
        }
    }

    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return ZStack(alignment: .bottomTrailing) {
            StationThumbnailView(
                station: station,
                size: 220,
                animationOverlay: .none,
                isAnimationActive: false
            )
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
                        colors: heroBackgroundColors,
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
        }
        .overlay {
            shape
                .stroke(heroBorderColor, lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 18, y: 8)
    }

    private var heroBackgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.13, green: 0.16, blue: 0.14),
                Color(red: 0.09, green: 0.11, blue: 0.10)
            ]
        }

        return [
            Color(red: 0.99, green: 0.97, blue: 0.91),
            Color(red: 0.96, green: 0.94, blue: 0.87)
        ]
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

    private var playIconName: String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    private var playTitle: String {
        if isPlaying {
            return L10n.string("player.control.pause")
        }
        return L10n.string("shell.featured.play")
    }
}

private struct HomeLiveStatePill: View {
    let isPlaying: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(0.7)
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(TuneAVTheme.highlight.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
    }

    private var title: String {
        if isLoading {
            return L10n.string("audio.status.loading").uppercased(with: .current)
        }
        if isPlaying {
            return L10n.string("audio.status.playing").uppercased(with: .current)
        }
        return L10n.string("shell.status.live").uppercased(with: .current)
    }
}

private struct HomeDeskBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.76))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.58), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct HomeDeskSignalPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 12, weight: .black))
                .tracking(0.9)
                .foregroundStyle(TuneAVTheme.brandGraphite)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.62), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
        }
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
        .accessibilityHidden(true)
    }
}
