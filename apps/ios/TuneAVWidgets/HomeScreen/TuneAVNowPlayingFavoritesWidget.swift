import SwiftUI
import WidgetKit

struct TuneAVNowPlayingFavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TuneAVWidgetKind.nowPlayingFavorites, provider: TuneAVWidgetProvider()) { entry in
            TuneAVNowPlayingFavoritesWidgetView(entry: entry)
                .tuneAVWidgetBackground()
        }
        .configurationDisplayName(TuneAVWidgetText.string("widget.favorites.title", fallback: "Radio and favorites"))
        .description(TuneAVWidgetText.string(
            "widget.favorites.description",
            fallback: "Your radio, the song and your favorite stations, one tap away."
        ))
        .supportedFamilies([.systemMedium])
    }
}

struct TuneAVNowPlayingFavoritesWidgetView: View {
    let entry: TuneAVWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if let radio = snapshot.myRadio {
                        nowPlaying(snapshot: snapshot, radio: radio)
                    }
                    if !snapshot.favorites.isEmpty {
                        TuneAVWidgetFavoritesGrid(snapshot: snapshot)
                            .frame(width: snapshot.myRadio == nil ? nil : 150)
                    }
                }
            } else {
                TuneAVWidgetEmptyView(strings: entry.strings, isCompact: false)
            }
        }
        .tuneAVWidgetDynamicTypeLimit()
        .widgetURL(entry.tapURL)
    }

    private func nowPlaying(snapshot: TuneAVWidgetSnapshot, radio: TuneAVWidgetStation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                TuneAVActivityArtwork(fileName: radio.artworkFileName, size: 46, cornerRadius: 12, location: .widgets)
                VStack(alignment: .leading, spacing: 3) {
                    TuneAVWidgetStatusRow(snapshot: snapshot)
                    if snapshot.songTitle != nil {
                        Text(radio.name)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(TuneAVWidgetBrand.green)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.songTitle ?? radio.name)
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundStyle(TuneAVWidgetBrand.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    if let artist = snapshot.songArtist {
                        Text(artist)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(TuneAVWidgetBrand.paper.opacity(0.74))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityHint(snapshot.strings.openPlayer)

                TuneAVWidgetPlayControl(
                    station: radio,
                    snapshot: snapshot,
                    isFavoriteShortcut: false,
                    accessibilityText: snapshot.playbackActionLabel
                ) {
                    TuneAVWidgetPlayGlyph(isActive: snapshot.isPlaybackActive, size: 42)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TuneAVWidgetFavoritesGrid: View {
    let snapshot: TuneAVWidgetSnapshot

    private var rows: [[TuneAVWidgetStation]] {
        stride(from: 0, to: snapshot.favorites.count, by: 2).map {
            Array(snapshot.favorites[$0..<min($0 + 2, snapshot.favorites.count)])
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.id) { station in
                        tile(for: station)
                    }
                    if row.count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(for station: TuneAVWidgetStation) -> some View {
        TuneAVWidgetPlayControl(
            station: station,
            snapshot: snapshot,
            isFavoriteShortcut: true,
            accessibilityText: snapshot.strings.playStation(station.name)
        ) {
            VStack(spacing: 4) {
                TuneAVActivityArtwork(fileName: station.artworkFileName, size: 28, cornerRadius: 8, location: .widgets)
                Text(station.name)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(TuneAVWidgetBrand.paper)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TuneAVWidgetBrand.inkRaised)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
