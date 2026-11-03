import SwiftUI
import WidgetKit

struct TuneAVLockScreenRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TuneAVWidgetKind.lockScreen, provider: TuneAVWidgetProvider()) { entry in
            TuneAVLockScreenRadioWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(TuneAVWidgetText.string("widget.lockScreen.title", fallback: "Play my radio"))
        .description(TuneAVWidgetText.string(
            "widget.lockScreen.description",
            fallback: "Start your radio from the Lock Screen."
        ))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct TuneAVLockScreenRadioWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TuneAVWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            default:
                rectangular
            }
        }
        .widgetURL(entry.compactTapURL)
    }

    @ViewBuilder
    private var circular: some View {
        if let snapshot = entry.snapshot, let radio = snapshot.myRadio {
            TuneAVWidgetPlayControl(
                station: radio,
                snapshot: snapshot,
                isFavoriteShortcut: false,
                accessibilityText: snapshot.playbackActionLabel,
                allowsLink: false
            ) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: snapshot.isPlaybackActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .black))
                        .widgetAccentable()
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                TuneAVMark(color: .primary, lineWidthRatio: 0.22)
                    .frame(width: 26)
            }
            .accessibilityElement()
            .accessibilityLabel(entry.strings.emptyTitle)
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let snapshot = entry.snapshot, let radio = snapshot.myRadio {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.statusText)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(radio.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                TuneAVWidgetPlayControl(
                    station: radio,
                    snapshot: snapshot,
                    isFavoriteShortcut: false,
                    accessibilityText: snapshot.playbackActionLabel,
                    allowsLink: false
                ) {
                    Image(systemName: snapshot.isPlaybackActive ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .widgetAccentable()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.strings.emptyTitle)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.strings.emptyMessage)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
