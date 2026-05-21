import AVAviFoundation
import SwiftUI

struct AviFocusedTrackSummaryCard: View {
    @Environment(\.displayScale) private var displayScale

    let discovery: DiscoveredTrack
    let feedback: TuneAVStationFeedback?

    var body: some View {
        AVAviFocusedSummaryCard(
            title: discovery.title,
            subtitle: "\(discovery.artistDisplayText) · \(discovery.stationName)",
            metadata: "\(L10n.string("shell.avi.music.lastSeen")) · \(discovery.playedAt.formatted(date: .numeric, time: .omitted))",
            artwork: {
                artwork
            },
            badge: {
                if let feedback {
                    TuneAVFeedbackBadge(feedback: feedback, size: 24)
                        .offset(x: -5, y: -5)
                }
            }
        )
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
        AVAviFocusedSummaryCard(
            title: summary.name,
            subtitle: summaryLine,
            metadata: latestDiscoveryTitle.map { "\(L10n.string("shell.avi.music.latestSong")) · \($0)" }
        ) {
            artwork
        }
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
            AVAviStatPill(
                title: L10n.string("shell.avi.music.artist.label"),
                value: artistName,
                systemImage: "person.fill"
            )

            AVAviStatPill(
                title: L10n.string("shell.avi.music.station"),
                value: stationName,
                systemImage: "dot.radiowaves.left.and.right"
            )

            AVAviStatPill(
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
            AVAviStatPill(
                title: L10n.string("shell.avi.music.artist.savedSongs"),
                value: "\(savedSongsCount)",
                systemImage: "bookmark.fill"
            )

            AVAviStatPill(
                title: L10n.string("shell.avi.music.artist.radios"),
                value: "\(stationCount)",
                systemImage: "dot.radiowaves.left.and.right"
            )

            AVAviStatPill(
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
                AVAviInfoLine(title: L10n.string("shell.avi.music.artist.label"), value: artistName)
                AVAviInfoLine(title: L10n.string("shell.avi.music.station"), value: stationName)
                AVAviInfoLine(title: L10n.string("shell.avi.music.lastSeen"), value: lastSeenLabel)
                AVAviInfoLine(title: L10n.string("shell.avi.music.feedback"), value: feedbackLabel)
                AVAviInfoLine(
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
