import SwiftUI

struct HomeMoodGenreSuggestion: Hashable {
    let tag: String
    let title: String
}

struct HomeMoodGenreDesk: View {
    let tags: [HomeMoodGenreSuggestion]
    let selectTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("shell.home.moodsGenres.title"))
                .tuneScaledFont(size: 20, weight: .bold)
                .foregroundStyle(TuneAVTheme.textPrimary)

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(tags, id: \.self) { suggestion in
                    HomeMoodGenrePill(title: suggestion.title, accessibilityID: "home.moodGenre.\(suggestion.tag)") {
                        selectTag(suggestion.tag)
                    }
                }
            }
            // FlowLayout gives each pill its one-line width and wraps rows at 320 pt: past the
            // second accessibility size a long genre pill would run off the row.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.section.moodsGenres")
    }
}

private struct HomeMoodGenrePill: View {
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 36

    let title: String
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkle")
                .tuneScaledFont(size: 13, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: pillHeight)
                .background(TuneAVTheme.elevatedSurface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}
