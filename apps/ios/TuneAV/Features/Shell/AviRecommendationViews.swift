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

struct AviActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct AviPromptButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .foregroundStyle(TuneAVTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
