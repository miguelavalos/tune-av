import SwiftUI

struct AviSignalInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct ArtistStatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(height: 68, alignment: .topLeading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

struct AviFocusedTrackSummaryCard: View {
    @Environment(\.displayScale) private var displayScale

    let discovery: DiscoveredTrack
    let feedback: TuneAVStationFeedback?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artwork
                    .overlay(alignment: .topLeading) {
                        if let feedback {
                            TuneAVFeedbackBadge(feedback: feedback, size: 24)
                                .offset(x: -5, y: -5)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(discovery.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text("\(discovery.artistDisplayText) · \(discovery.stationName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    Text("\(L10n.string("shell.avi.music.lastSeen")) · \(discovery.playedAt.formatted(date: .numeric, time: .omitted))")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 62
        if let artworkURL = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                AviMusicArtworkFallback(systemImage: "music.note", size: size)
            }
            .frame(width: size, height: size)
            .clipShape(AviMusicArtworkShape(size: size))
            .overlay {
                AviMusicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            AviMusicArtworkFallback(systemImage: "music.note", size: size)
        }
    }
}

struct AviFocusedArtistSummaryCard: View {
    @Environment(\.displayScale) private var displayScale

    let summary: DiscoveryArtistSummary
    let summaryLine: String
    let latestDiscoveryTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(summaryLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    if let latestDiscoveryTitle {
                        Text("\(L10n.string("shell.avi.music.latestSong")) · \(latestDiscoveryTitle)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 62
        if let artworkURL = summary.displayArtworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                AviMusicArtworkFallback(systemImage: "person.fill", size: size)
            }
            .frame(width: size, height: size)
            .clipShape(AviMusicArtworkShape(size: size))
            .overlay {
                AviMusicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            AviMusicArtworkFallback(systemImage: "person.fill", size: size)
        }
    }
}

struct AviFocusedTrackStats: View {
    let artistName: String
    let stationName: String
    let feedbackLabel: String

    var body: some View {
        HStack(spacing: 7) {
            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.label"),
                value: artistName,
                systemImage: "person.fill"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.station"),
                value: stationName,
                systemImage: "dot.radiowaves.left.and.right"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.feedback"),
                value: feedbackLabel,
                systemImage: "heart.fill"
            )
        }
    }
}

struct AviFocusedArtistStats: View {
    let savedSongsCount: Int
    let stationCount: Int
    let latestSeenLabel: String

    var body: some View {
        HStack(spacing: 7) {
            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.savedSongs"),
                value: "\(savedSongsCount)",
                systemImage: "bookmark.fill"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.radios"),
                value: "\(stationCount)",
                systemImage: "dot.radiowaves.left.and.right"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.lastSeen"),
                value: latestSeenLabel,
                systemImage: "clock.fill"
            )
        }
    }
}

struct AviFocusedTrackArticle: View {
    let artistName: String
    let stationName: String
    let lastSeenLabel: String
    let feedbackLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("shell.stationInfo.title"))
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                AviSignalInfoLine(title: L10n.string("shell.avi.music.artist.label"), value: artistName)
                AviSignalInfoLine(title: L10n.string("shell.avi.music.station"), value: stationName)
                AviSignalInfoLine(title: L10n.string("shell.avi.music.lastSeen"), value: lastSeenLabel)
                AviSignalInfoLine(title: L10n.string("shell.avi.music.feedback"), value: feedbackLabel)
                AviSignalInfoLine(
                    title: L10n.string("shell.stationInfo.summary"),
                    value: L10n.string("shell.avi.music.track.future")
                )
            }
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
    }
}

struct AviFocusedArtistArticle<SummaryCard: View, Stats: View, Services: View, SavedSongs: View, Stations: View>: View {
    @ViewBuilder let summaryCard: () -> SummaryCard
    @ViewBuilder let stats: () -> Stats
    @ViewBuilder let services: () -> Services
    @ViewBuilder let savedSongs: () -> SavedSongs
    @ViewBuilder let stations: () -> Stations

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryCard()
            stats()
            services()
            savedSongs()
            stations()
        }
    }
}

struct AviFocusedTrackQuickActions: View {
    let discovery: DiscoveredTrack
    let selectedFeedback: TuneAVStationFeedback?
    let toggleSaved: () -> Void
    let openArtist: () -> Void
    let selectFeedback: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggleSaved) {
                    Label(
                        discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                        systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark"
                    )
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(discovery.isMarkedInteresting ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.detail.track.save")

                Button(action: openArtist) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.searchArtist"))
            }

            StationFeedbackControl(
                feedbackIdentity: "track:\(discovery.discoveryID)",
                selectedFeedback: selectedFeedback,
                selectFeedback: selectFeedback,
                clearFeedback: clearFeedback
            )
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct AviMusicArtworkFallback: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        AviMusicArtworkShape(size: size)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                AviMusicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }
}

private struct AviMusicArtworkShape: Shape {
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size),
            style: .continuous
        )
        .path(in: rect)
    }
}
