import Foundation

struct ShellUITestTrackMetadataOverride: Equatable {
    let title: String?
    let artist: String?
}

enum ShellUITestBootstrapOverrides {
    static func trackMetadata(from launchContext: LaunchContext) -> ShellUITestTrackMetadataOverride? {
        guard launchContext.isUITesting else { return nil }
        guard launchContext.uiTestTrackTitle != nil || launchContext.uiTestTrackArtist != nil else { return nil }

        return ShellUITestTrackMetadataOverride(
            title: launchContext.uiTestTrackTitle,
            artist: launchContext.uiTestTrackArtist
        )
    }

    static func upgradePromptFeature(from launchContext: LaunchContext) -> LimitedFeature? {
        guard launchContext.isUITesting else { return nil }
        return launchContext.uiTestUpgradePromptFeature
    }
}
