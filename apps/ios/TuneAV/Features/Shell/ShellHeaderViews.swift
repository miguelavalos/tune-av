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
        HStack(alignment: .top, spacing: 13) {
            if showsBackButton {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(TuneAVTheme.elevatedSurface, in: Circle())
                        .overlay {
                            Circle().stroke(TuneAVTheme.borderSubtle.opacity(0.52), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("common.back"))
                .accessibilityIdentifier("\(accessibilityIdentifier).back")
            } else {
                AviStableEmotionImage(emotion: .focused, assetVariant: .head, width: 40)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                    .overlay {
                        Circle().stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let status {
                        Text(status)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)
                            .lineLimit(1)
                    }

                    if let feedback {
                        feedbackBadge(feedback)
                    }
                }

                Text(title)
                    .font(.system(size: entityName == nil ? 25 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(entityName == nil ? 2 : 1)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                if let entityName {
                    Text(entityName)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func feedbackBadge(_ feedback: TuneAVStationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
            .frame(width: 20, height: 20)
            .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.86), in: Circle())
            .overlay {
                Circle().stroke(Color.white.opacity(0.74), lineWidth: 1)
            }
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
        HStack(alignment: .top, spacing: 12) {
            if showsAviImage {
                AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 54)
                    .accessibilityLabel(L10n.string("shell.avi.title"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 7) {
                    Text(summary)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let status {
                        Text(status)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(TuneAVTheme.highlight.opacity(0.11), in: Capsule(style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
