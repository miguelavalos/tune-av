import SwiftUI

struct StationInfoDiscoverySnapshot: View {
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

                Spacer(minLength: 12)

                Text("\(profile.musicDiscoveryScore)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .monospacedDigit()
            }

            VStack(spacing: 8) {
                StationInfoMetricRow(title: L10n.string("shell.stationDetail.discovery.music"), level: profile.musicLevel)
                StationInfoMetricRow(title: L10n.string("shell.stationDetail.discovery.speech"), level: profile.speechLevel)
                StationInfoMetricRow(title: L10n.string("shell.stationDetail.discovery.news"), level: profile.newsLevel)
                StationInfoMetricRow(title: L10n.string("shell.stationDetail.discovery.sports"), level: profile.sportsLevel)
                StationInfoMetricRow(title: L10n.string("shell.stationDetail.discovery.ads"), level: profile.adLoad)
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

private struct StationInfoMetricRow: View {
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
                        .frame(width: max(8, proxy.size.width * metricProgress))
                }
            }
            .frame(height: 8)

            Text(localizedLevel)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var metricProgress: CGFloat {
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
