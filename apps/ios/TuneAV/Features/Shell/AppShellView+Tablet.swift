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

            ForEach(AppShellTab.navigationTabs + [.avi], id: \.self) { tab in
                tabletSidebarButton(tab: tab, isSelected: selectedTab.navigationTab == tab)
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
            systemImage: tab.navigationSystemImage,
            isSelected: isSelected
        ) {
            selectTabletTab(tab)
        }
        .accessibilityIdentifier(tab.navigationAccessibilityIdentifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tabletTitle(for: tab))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            selectNavigationTab(tab)
        }
    }

    func tabletTitle(for tab: AppShellTab) -> String {
        tab == .avi ? appExperience.identity.assistantName : tab.navigationTitle
    }
}
