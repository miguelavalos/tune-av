import SwiftUI
import WidgetKit

struct TuneAVMyRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TuneAVWidgetKind.myRadio, provider: TuneAVWidgetProvider()) { entry in
            TuneAVMyRadioWidgetView(entry: entry)
                .tuneAVWidgetBackground()
        }
        .configurationDisplayName(TuneAVWidgetText.string("widget.myRadio.title", fallback: "My radio"))
        .description(TuneAVWidgetText.string("widget.myRadio.description", fallback: "Start your radio with one tap."))
        .supportedFamilies([.systemSmall])
    }
}

struct TuneAVMyRadioWidgetView: View {
    let entry: TuneAVWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let radio = snapshot.myRadio {
                content(snapshot: snapshot, radio: radio)
            } else {
                TuneAVWidgetEmptyView(strings: entry.strings, isCompact: true)
            }
        }
        .tuneAVWidgetDynamicTypeLimit()
        .widgetURL(entry.compactTapURL)
    }

    private func content(snapshot: TuneAVWidgetSnapshot, radio: TuneAVWidgetStation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                TuneAVActivityArtwork(fileName: radio.artworkFileName, size: 52, cornerRadius: 14, location: .widgets)
                Spacer(minLength: 0)
                TuneAVWidgetPlayControl(
                    station: radio,
                    snapshot: snapshot,
                    isFavoriteShortcut: false,
                    accessibilityText: snapshot.playbackActionLabel,
                    allowsLink: false
                ) {
                    TuneAVWidgetPlayGlyph(isActive: snapshot.isPlaybackActive, size: 46)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                TuneAVWidgetStatusRow(snapshot: snapshot)
                Text(radio.name)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(TuneAVWidgetBrand.paper)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(snapshot.strings.openPlayer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
