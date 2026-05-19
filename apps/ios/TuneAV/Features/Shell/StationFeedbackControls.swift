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
                Button {
                    selectFeedback(feedback)
                } label: {
                    Image(systemName: feedback.systemImage)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(
                            TuneAVTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feedback.localizedState)
                .accessibilityIdentifier("avi.recommendation.feedback.\(feedback.rawValue)")
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
        HStack(spacing: 10) {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(TuneAVTheme.brandBlack)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight, in: Circle())

            Text(feedback.localizedState)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(TuneAVTheme.highlight.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel(feedback.localizedState)
    }
}

struct StationFeedbackButton: View {
    let title: String
    let systemImage: String
    let feedback: TuneAVStationFeedback
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    isSelected ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.62) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? L10n.string("common.selected") : "")
        .accessibilityIdentifier("stationFeedback.\(feedback.rawValue)")
    }
}
