import AVAviFoundation
import SwiftUI

struct HomeAviBrief: View {
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    let emotion: TuneAVAviEmotion
    let openAvi: () -> Void
    @Environment(\.avCommonAppExperience) private var appExperience

    var body: some View {
        AVAviHomeBriefCard(
            identity: appExperience.identity,
            detail: briefDetail,
            actionAccessibilityLabel: L10n.string("shell.home.aviBrief.action"),
            accessibilityIdentifier: "home.aviBrief.open",
            openAvi: openAvi
        ) {
            AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 58, height: 58)
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
