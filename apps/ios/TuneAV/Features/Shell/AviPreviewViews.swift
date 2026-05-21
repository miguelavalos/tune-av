import AVAviFoundation
import SwiftUI

struct AviPreviewCapabilityRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AviPreviewPrimaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        AVAviPreviewPrimaryButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}

struct AviPreviewSecondaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        AVAviPreviewSecondaryButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}
