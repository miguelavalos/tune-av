import AppIntents
import Foundation

enum TuneAVControlKind {
    static let myRadio = "TuneAVMyRadioControl"
}

struct TuneAVMyRadioControlIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "widget.myRadio.title"
    static let isDiscoverable = false

    @Parameter(title: "control.intent.isPlaying")
    var value: Bool

    init() {}

    static func appLink(after outcome: TuneAVWidgetActionOutcome, startingPlayback: Bool) -> TuneAVWidgetDeepLink? {
        switch outcome {
        case let .needsApp(link):
            return link
        case .noStation where startingPlayback:
            return .home
        default:
            return nil
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let outcome = await TuneAVWidgetActionRouter.perform(value ? .startMyRadio : .pausePlayback)
        if #available(iOS 18.2, *), let link = Self.appLink(after: outcome, startingPlayback: value) {
            return .result(opensIntent: TuneAVContinueInAppIntent(link: link))
        }
        return .result()
    }
}

struct TuneAVContinueInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.action.openPlayer"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "control.intent.link")
    var link: String

    init() {}

    init(link: TuneAVWidgetDeepLink) {
        self.link = link.url()?.absoluteString ?? ""
    }

    var deepLink: TuneAVWidgetDeepLink? {
        URL(string: link).flatMap { TuneAVWidgetDeepLink(url: $0) }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let deepLink {
            TuneAVWidgetActionRouter.appLinkHandler?(deepLink)
        }
        return .result()
    }
}
