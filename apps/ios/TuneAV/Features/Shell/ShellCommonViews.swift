import AVSettingsFoundation
import SwiftUI

struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct ShellRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        AVSettingsInfoRow(systemImage: systemImage, title: title, detail: detail)
    }
}

struct ShellStatusPill: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TuneAVTheme.highlight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
    }
}

struct EmptyLibraryState: View {
    let title: String
    let detail: String
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSystemImage ?? "arrow.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }
}
