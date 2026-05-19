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
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("shell.home.moodsGenres.title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.home.moodsGenres.subtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(tags, id: \.self) { suggestion in
                    HomeMoodGenrePill(title: suggestion.title, accessibilityID: "home.moodGenre.\(suggestion.tag)") {
                        selectTag(suggestion.tag)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.section.moodsGenres")
    }
}

private struct HomeMoodGenrePill: View {
    let title: String
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 36)
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
