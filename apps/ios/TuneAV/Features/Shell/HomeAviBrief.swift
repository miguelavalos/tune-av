import AVAviFoundation
import SwiftUI

struct HomeAviBrief: View {
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    var returningStation: HomeReturningStation? = nil
    /// One line Avi says after "Surprise me"; while present it replaces the brief and Avi looks curious.
    var surpriseReason: String? = nil
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
            AviStableEmotionImage(emotion: displayedEmotion, assetVariant: .head, width: 58, height: 58)
        }
    }

    private var displayedEmotion: TuneAVAviEmotion {
        surpriseReason == nil ? emotion : AviScreenReaction.curious.emotion
    }

    private var briefDetail: String {
        Self.detail(
            currentStation: currentStation,
            recentCount: recentCount,
            favoriteCount: favoriteCount,
            returningStation: returningStation,
            surpriseReason: surpriseReason
        )
    }

    /// Order: Avi's surprise reason, the radio playing now, a radio the listener keeps returning to,
    /// what Avi has to work with, and finally the invitation to start.
    static func detail(
        currentStation: Station?,
        recentCount: Int,
        favoriteCount: Int,
        returningStation: HomeReturningStation?,
        surpriseReason: String?
    ) -> String {
        if let surpriseReason {
            return surpriseReason
        }
        if let currentStation {
            return L10n.string("shell.home.aviBrief.listening", currentStation.name)
        }
        if let returningStation {
            return L10n.string("shell.home.aviBrief.returning", returningStation.name, returningStation.count)
        }
        if recentCount > 0 || favoriteCount > 0 {
            let recentText = L10n.plural(singular: "shell.count.recent.short.one", plural: "shell.count.recent.short.other", count: recentCount, recentCount)
            let favoriteText = L10n.plural(singular: "shell.count.saved.short.one", plural: "shell.count.saved.short.other", count: favoriteCount, favoriteCount)
            return L10n.string("shell.home.aviBrief.localSignals", recentText, favoriteText)
        }
        return L10n.string("shell.home.aviBrief.empty")
    }
}
