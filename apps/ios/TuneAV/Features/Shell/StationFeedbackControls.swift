import AVAviFoundation
import SwiftUI

struct StationFeedbackControl: View {
    var feedbackIdentity: String = "stationFeedback"
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.string("shell.stationFeedback.title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: clearFeedback) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .opacity(selectedFeedback == nil ? 0 : 1)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(selectedFeedback == nil)
                .accessibilityHidden(selectedFeedback == nil)
                .accessibilityLabel(L10n.string("shell.stationFeedback.clear"))
                .accessibilityIdentifier("stationFeedback.clear")
            }
            .frame(height: 24)

            Group {
                if let selectedFeedback {
                    SelectedStationFeedbackStatus(feedback: selectedFeedback)
                } else {
                    HStack(spacing: 8) {
                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.like"),
                            systemImage: "hand.thumbsup.fill",
                            feedback: .liked,
                            isSelected: false,
                            action: { selectFeedback(.liked) }
                        )

                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.notForMe"),
                            systemImage: "minus.circle.fill",
                            feedback: .notForMe,
                            isSelected: false,
                            action: { selectFeedback(.notForMe) }
                        )

                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.dislike"),
                            systemImage: "hand.thumbsdown.fill",
                            feedback: .disliked,
                            isSelected: false,
                            action: { selectFeedback(.disliked) }
                        )
                    }
                }
            }
            .frame(height: 38)
        }
        .frame(height: 72, alignment: .top)
        .id(feedbackIdentity)
        .accessibilityIdentifier("stationFeedback.control")
    }
}

struct AviCompactFeedbackControl: View {
    var feedbackIdentity: String = "aviFeedback"
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void
    var clearFeedback: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TuneAVStationFeedback.displayOrder, id: \.self) { feedback in
                AVAviCompactFeedbackButton(
                    systemImage: feedback.systemImage,
                    accessibilityLabel: feedback.localizedState,
                    accessibilityIdentifier: "avi.recommendation.feedback.\(feedback.rawValue)"
                ) {
                    selectFeedback(feedback)
                }
            }
        }
        .frame(height: 30)
        .opacity(selectedFeedback == nil ? 1 : 0)
        .disabled(selectedFeedback != nil)
        .accessibilityHidden(selectedFeedback != nil)
        .id(feedbackIdentity)
        .accessibilityIdentifier("avi.recommendation.feedback")
    }
}

struct SelectedStationFeedbackStatus: View {
    let feedback: TuneAVStationFeedback

    var body: some View {
        AVAviSelectedFeedbackStatus(
            title: feedback.localizedState,
            systemImage: feedback.systemImage,
            accessibilityLabel: feedback.localizedState
        )
    }
}

struct StationFeedbackButton: View {
    let title: String
    let systemImage: String
    let feedback: TuneAVStationFeedback
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        AVAviFeedbackOptionButton(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            accessibilityIdentifier: "stationFeedback.\(feedback.rawValue)",
            action: action
        )
        .accessibilityValue(isSelected ? L10n.string("common.selected") : "")
    }
}
