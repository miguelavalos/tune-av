import AVAviFoundation
import SwiftUI

struct AviRecommendationRow: View {
    let station: Station
    let reason: String
    let selectedFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let feedbackAction: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .frame(width: 32, height: 32)
                        .background(TuneAVTheme.highlight, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.recommendation.play"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(reason)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(1)

                        if let selectedFeedback {
                            Image(systemName: selectedFeedback.systemImage)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(selectedFeedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                                .accessibilityLabel(selectedFeedback.localizedState)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: detailsAction) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.recommendation.details"))
            }

            AviCompactFeedbackControl(
                feedbackIdentity: "station:\(station.id)",
                selectedFeedback: selectedFeedback,
                selectFeedback: feedbackAction,
                clearFeedback: clearFeedback
            )
        }
        .padding(10)
        .background(TuneAVTheme.highlight.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("avi.recommendation.secondary")
    }
}

struct AviRelatedStationRow: View {
    let station: Station
    let reason: String
    let playAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: playAction) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 32, height: 32)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.avi.recommendation.play"))

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(reason)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: detailsAction) {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.avi.recommendation.details"))
        }
        .padding(10)
        .background(TuneAVTheme.highlight.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("avi.related.row")
    }
}
