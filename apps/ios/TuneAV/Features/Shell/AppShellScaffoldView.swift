import AVAppShellFoundation
import SwiftUI

struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    @Environment(\.avCommonAppExperience) private var appExperience

    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
    let hasAviActiveContext: Bool
    let footerBackdropHeight: CGFloat
    let footerPlayerTabSpacing: CGFloat
    let searchAction: () -> Void
    let aviAction: () -> Void
    let selectTab: (AppShellTab) -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerPlayer: () -> FooterPlayer

    var body: some View {
        AVAppShellConfiguredScaffold(
            selectedTabID: selectedTab,
            tabs: footerTabs,
            assistantID: AppShellTab.avi,
            assistant: footerAssistant,
            hasAssistantActiveContext: hasAviActiveContext,
            footerConfiguration: footerConfiguration,
            onSelectTab: { tab in
                if tab == .search {
                    searchAction()
                } else {
                    selectTab(tab)
                }
            },
            onSelectAssistant: aviAction,
            content: content,
            footerPlayer: footerPlayer
        )
    }

    private var footerAssistant: AVAppShellConfiguredAssistant {
        AVAppShellConfiguredAssistant(
            name: appExperience.identity.assistantName,
            accessibilityIdentifier: "tab.avi",
            assetName: appExperience.visualAssets?.footerAssistantName ?? "AviFooterIcon"
        )
    }

    private var footerTabs: [AVAppShellTab<AppShellTab>] {
        [
            AVAppShellTab(
                id: .home,
                title: L10n.string("tab.home"),
                systemImage: "house.fill",
                accessibilityIdentifier: "tab.home"
            ),
            AVAppShellTab(
                id: .library,
                title: L10n.string("tab.library"),
                systemImage: "dot.radiowaves.left.and.right",
                accessibilityIdentifier: "tab.library"
            ),
            AVAppShellTab(
                id: .music,
                title: L10n.string("tab.music"),
                systemImage: "music.note.list",
                accessibilityIdentifier: "tab.music"
            ),
            AVAppShellTab(
                id: .search,
                title: L10n.string("tab.search"),
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "tab.search"
            )
        ]
    }

    private var footerConfiguration: AVAppShellFooterConfiguration {
        AVAppShellFooterConfiguration(
            backdropHeight: footerBackdropHeight,
            playerTabSpacing: footerPlayerTabSpacing
        )
    }
}
