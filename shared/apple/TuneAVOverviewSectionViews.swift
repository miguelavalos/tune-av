import AVAppShellFoundation
import SwiftUI

struct RadioOverviewCarouselSection<Content: View>: View {
    let title: String
    let subtitle: String
    var accessibilityIdentifier: String?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if let accessibilityIdentifier {
            section
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            section
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(L10n.string("common.view"))
                            .font(.system(size: 13, weight: .black))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .black))
                    }
                    .foregroundStyle(TuneAVTheme.highlight)
                }
                .buttonStyle(.plain)
            }

            content()
        }
    }
}

struct RadioOverviewMetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            content
        }
    }
}
