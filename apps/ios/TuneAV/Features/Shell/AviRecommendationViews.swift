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
            AVAviRecommendationItemRow(
                title: station.name,
                detail: reason,
                playAccessibilityLabel: L10n.string("shell.avi.recommendation.play"),
                detailsAccessibilityLabel: L10n.string("shell.avi.recommendation.details"),
                accessibilityIdentifier: "avi.recommendation.secondary",
                playAction: playAction,
                detailsAction: detailsAction
            ) {
                feedbackIndicator
            }

            AviCompactFeedbackControl(
                feedbackIdentity: "station:\(station.id)",
                selectedFeedback: selectedFeedback,
                selectFeedback: feedbackAction,
                clearFeedback: clearFeedback
            )
        }
    }

    @ViewBuilder
    private var feedbackIndicator: some View {
        if let selectedFeedback {
            Image(systemName: selectedFeedback.systemImage)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(selectedFeedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .accessibilityLabel(selectedFeedback.localizedState)
        }
    }
}

struct AviRelatedStationRow: View {
    let station: Station
    let reason: String
    let playAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        AVAviRecommendationItemRow(
            title: station.name,
            detail: reason,
            playAccessibilityLabel: L10n.string("shell.avi.recommendation.play"),
            detailsAccessibilityLabel: L10n.string("shell.avi.recommendation.details"),
            accessibilityIdentifier: "avi.related.row",
            playAction: playAction,
            detailsAction: detailsAction
        )
    }
}
