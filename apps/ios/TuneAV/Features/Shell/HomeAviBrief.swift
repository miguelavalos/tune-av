import SwiftUI

struct HomeAviBrief: View {
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    let emotion: TuneAVAviEmotion
    let openAvi: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 58, height: 58)
                .padding(6)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("shell.home.aviBrief.title"))
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(briefDetail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: openAvi) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 42, height: 42)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.home.aviBrief.action"))
            .accessibilityIdentifier("home.aviBrief.open")
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
        }
    }

    private var briefDetail: String {
        if let currentStation {
            return L10n.string("shell.home.aviBrief.listening", currentStation.name)
        }
        if recentCount > 0 || favoriteCount > 0 {
            let recentText = L10n.plural(singular: "shell.count.recent.short.one", plural: "shell.count.recent.short.other", count: recentCount, recentCount)
            let favoriteText = L10n.plural(singular: "shell.count.saved.short.one", plural: "shell.count.saved.short.other", count: favoriteCount, favoriteCount)
            return L10n.string("shell.home.aviBrief.localSignals", recentText, favoriteText)
        }
        return L10n.string("shell.home.aviBrief.empty")
    }
}
