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
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.textInverse.opacity(0.16), in: Circle())

                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
            }
            .foregroundStyle(TuneAVTheme.textInverse)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .padding(.horizontal, 14)
            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: TuneAVTheme.highlight.opacity(0.24), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct AviPreviewSecondaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
