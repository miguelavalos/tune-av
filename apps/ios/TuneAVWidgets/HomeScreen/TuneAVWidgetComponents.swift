import AppIntents
import SwiftUI
import WidgetKit

struct TuneAVWidgetStatusRow: View {
    let snapshot: TuneAVWidgetSnapshot

    var body: some View {
        HStack(spacing: 5) {
            TuneAVLiveBars(isLive: snapshot.playback == .playing)
                .frame(width: 11, height: 10)
            Text(snapshot.statusText)
                .textCase(.uppercase)
                .font(.system(.caption2, design: .rounded).weight(.black))
                .tracking(0.6)
                .foregroundStyle(snapshot.playback == .playing ? TuneAVWidgetBrand.green : TuneAVWidgetBrand.paper.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct TuneAVWidgetPlayGlyph: View {
    let isActive: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: isActive ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.38, weight: .black))
            .foregroundStyle(TuneAVWidgetBrand.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(TuneAVWidgetBrand.green))
            .accessibilityHidden(true)
    }
}

struct TuneAVWidgetPlayControl<Label: View>: View {
    let station: TuneAVWidgetStation
    let snapshot: TuneAVWidgetSnapshot
    let isFavoriteShortcut: Bool
    let accessibilityText: String
    var allowsLink = true
    @ViewBuilder let label: () -> Label

    var body: some View {
        if snapshot.opensAppToPlay {
            if allowsLink, let url = TuneAVWidgetDeepLink.play(stationID: station.id, isFavoriteShortcut: isFavoriteShortcut).url() {
                Link(destination: url) {
                    label()
                }
                .accessibilityLabel(accessibilityText)
            } else {
                label()
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityText)
            }
        } else {
            Button(intent: TuneAVPlayStationIntent(stationID: station.id, isFavoriteShortcut: isFavoriteShortcut)) {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
        }
    }
}

struct TuneAVWidgetEmptyView: View {
    let strings: TuneAVWidgetStrings
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            TuneAVMark()
                .frame(height: isCompact ? 16 : 18)
            Spacer(minLength: 0)
            Text(strings.emptyTitle)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(TuneAVWidgetBrand.paper)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(strings.emptyMessage)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(TuneAVWidgetBrand.paper.opacity(0.74))
                .lineLimit(isCompact ? 4 : 3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func tuneAVWidgetBackground() -> some View {
        containerBackground(TuneAVWidgetBrand.ink, for: .widget)
    }

    func tuneAVWidgetDynamicTypeLimit() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
