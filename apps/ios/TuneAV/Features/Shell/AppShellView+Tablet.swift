import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    var tabletShell: some View {
        NavigationStack {
            HStack(spacing: 0) {
                tabletSidebar

                Divider()

                tabletContentArea
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .accessibilityIdentifier("tune.shell.tablet")
        }
    }

    var tabletContentArea: some View {
        ZStack {
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            tabletContentFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var tabletContentFooter: some View {
        ZStack(alignment: .bottom) {
            if audioPlayer.currentStation != nil {
                LinearGradient(
                    stops: [
                        .init(color: TuneAVTheme.footerBackdrop.opacity(0), location: 0),
                        .init(color: TuneAVTheme.footerBackdrop.opacity(0.94), location: 0.48),
                        .init(color: TuneAVTheme.footerBackdrop, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: shellFooterBackdropHeight)
                .allowsHitTesting(false)
            }

            compactFooterPlayer
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: tabletContentFooterPlayerMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("tune.shell.tablet.footerPlayer")
    }

    var tabletContentFooterPlayerMaxWidth: CGFloat {
        isAviFullPlayerActive ? 940 : 760
    }

    var tabletSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabletSidebarBrandHeader
                .padding(.bottom, 12)

            ForEach([AppShellTab.home, .library, .music, .search, .avi], id: \.self) { tab in
                tabletSidebarButton(tab: tab, isSelected: selectedTab == tab)
            }

            Spacer(minLength: 16)

            tabletChromeButton(
                title: L10n.string("profile.settingsScreen.title"),
                systemImage: "gearshape.fill",
                isSelected: selectedTab == .profile && profileMode == .settings,
                accessibilityIdentifier: "tune.sidebar.settings"
            ) {
                openChromeRequest(.settings)
            }

            tabletChromeButton(
                title: L10n.string("profile.accountScreen.title"),
                systemImage: "person.crop.circle.fill",
                isSelected: selectedTab == .profile && profileMode == .account,
                accessibilityIdentifier: "tune.sidebar.account"
            ) {
                openChromeRequest(.account)
            }
        }
        .padding(.horizontal, AVAppShellTabletSidebarMetric.horizontalPadding)
        .padding(.vertical, AVAppShellTabletSidebarMetric.verticalPadding)
        .frame(width: 264, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityIdentifier("tune.shell.tablet.sidebar")
    }

    var tabletSidebarBrandHeader: some View {
        AVAppShellTabletSidebarBrandHeader(
            logoAssetName: appExperience.visualAssets?.headerLogoName ?? "HeaderWordmark",
            accessibilityLabel: appExperience.identity.displayName,
            logoWidth: 138,
            logoHeight: 44,
            logoLeadingCorrection: -16
        )
    }

    func tabletSidebarButton(tab: AppShellTab, isSelected: Bool) -> some View {
        AVAppShellTabletSidebarButton(
            title: tabletTitle(for: tab),
            systemImage: tabletSystemImage(for: tab),
            isSelected: isSelected
        ) {
            selectTabletTab(tab)
        }
        .accessibilityIdentifier("tune.sidebar.\(tabletAccessibilityID(for: tab))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tabletTitle(for: tab))
    }

    func tabletChromeButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        AVAppShellTabletSidebarButton(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            fontSize: 15,
            action: action
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    func selectTabletTab(_ tab: AppShellTab) {
        if tab == .avi {
            openContextualAvi()
        } else {
            selectedTab = tab
        }
    }

    func tabletTitle(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return L10n.string("tab.home")
        case .library:
            return L10n.string("tab.library")
        case .music:
            return L10n.string("tab.music")
        case .search:
            return L10n.string("tab.search")
        case .avi:
            return appExperience.identity.assistantName
        case .profile:
            return L10n.string("profile.settingsScreen.title")
        }
    }

    func tabletSystemImage(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return "house.fill"
        case .library:
            return "dot.radiowaves.left.and.right"
        case .music:
            return "music.note.list"
        case .search:
            return "magnifyingglass"
        case .avi:
            return "sparkles"
        case .profile:
            return "gearshape.fill"
        }
    }

    func tabletAccessibilityID(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return "home"
        case .library:
            return "library"
        case .music:
            return "music"
        case .search:
            return "search"
        case .avi:
            return "avi"
        case .profile:
            return "profile"
        }
    }
}
