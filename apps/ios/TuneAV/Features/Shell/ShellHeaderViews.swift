import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct DetailTopHeader: View {
    let title: String
    var entityName: String? = nil
    let subtitle: String
    var status: String?
    var feedback: TuneAVStationFeedback?
    var showsBackButton = true
    var accessibilityIdentifier: String
    let goBack: () -> Void

    var body: some View {
        AVAppShellDetailHeaderScaffold(
            title: title,
            entityName: entityName,
            subtitle: subtitle,
            status: status,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            leadingControl
        } accessory: {
            if let feedback {
                feedbackBadge(feedback)
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if showsBackButton {
            AVAppShellIconButton(
                systemName: "chevron.left",
                accessibilityLabel: L10n.string("common.back"),
                accessibilityIdentifier: "\(accessibilityIdentifier).back",
                action: goBack
            )
        } else {
            AviStableEmotionImage(emotion: .focused, assetVariant: .head, width: 40)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .overlay {
                    Circle().stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
    }

    private func feedbackBadge(_ feedback: TuneAVStationFeedback) -> some View {
        TuneAVFeedbackBadge(feedback: feedback, size: 20, fontSize: 9, borderOpacity: 0.74)
    }
}

struct AviScreenHeader: View {
    let emotion: TuneAVAviEmotion
    let title: String
    let summary: String
    var status: String? = nil
    var showsAviImage = true
    var accessibilityIdentifier: String

    var body: some View {
        AVAviScreenHeader(
            title: title,
            summary: summary,
            status: status,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            if showsAviImage {
                AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 54)
                    .accessibilityLabel(L10n.string("shell.avi.title"))
            } else {
                EmptyView()
            }
        }
    }
}
