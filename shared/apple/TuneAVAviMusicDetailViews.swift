import AVAviFoundation
import AVAppShellFoundation
import SwiftUI

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
