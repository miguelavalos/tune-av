import SwiftUI

struct AviSignalActionChip: View {
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
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(TuneAVTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AviSignalStep: View {
    let index: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 24, height: 24)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }
}

struct AviSignalChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(TuneAVTheme.highlight)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
    }
}

struct AviSignalRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 28, height: 28)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
